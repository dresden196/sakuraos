#include "backend.h"

#include <QJsonArray>
#include <algorithm>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariant>
#include <QDir>
#include <QFile>
#include <QFileInfo>
#include <QStandardPaths>
#include <QUrl>
#include <QDBusConnection>
#include <QDBusMessage>
#include <pwd.h>
#include <unistd.h>

namespace {
constexpr auto ENGINE = "/usr/bin/sakura-store";

QVariantMap toMap(const QJsonObject &o)
{
    return o.toVariantMap();
}
} // namespace

Backend::Backend(QObject *parent) : QObject(parent) {
    // The source list comes from the engine too. It was a hardcoded literal
    // that listed Snap and the AUR unconditionally, so a machine without
    // snapd showed a filter that could only ever return nothing -- the same
    // fault the category list was deliberately built to avoid.
    {
        QProcess p;
        p.start(QString::fromLatin1(ENGINE),
                {QStringLiteral("sources"), QStringLiteral("--json")});
        if (p.waitForFinished(6000)) {
            const QJsonArray rows =
                QJsonDocument::fromJson(p.readAllStandardOutput()).array();
            for (const QJsonValue &v : rows) {
                m_sources.append(toMap(v.toObject()));
            }
        }
    }

    // The category vocabulary lives in the engine, which is also what knows
    // that it applies to Flatpak and the repositories but not to the AUR.
    {
        QProcess p;
        p.start(QString::fromLatin1(ENGINE),
                {QStringLiteral("categories"), QStringLiteral("--json")});
        if (p.waitForFinished(4000)) {
            const QJsonArray rows =
                QJsonDocument::fromJson(p.readAllStandardOutput()).array();
            for (const QJsonValue &v : rows) {
                m_categories.append(toMap(v.toObject()));
            }
        }
    }
}

QProcess *Backend::run(const QStringList &args)
{
    auto *p = new QProcess(this);
    p->start(QString::fromLatin1(ENGINE), args);
    return p;
}

void Backend::search(const QString &query, const QString &source)
{
    // Moving somewhere else clears a failure from the last thing. Left in
    // place it reappears over a page it has nothing to do with, which reads
    // as the new page having failed.
    m_error.clear();
    m_errorDetail.clear();
    if (query.trimmed().isEmpty()) {
        m_results.clear();
        Q_EMIT resultsChanged();
        return;
    }
    m_searching = true;
    Q_EMIT stateChanged();

    QStringList args{QStringLiteral("search"), query, QStringLiteral("--json")};
    if (!source.isEmpty() && source != QLatin1String("all")) {
        args << QStringLiteral("--source") << source;
    }

    auto *p = run(args);
    connect(p, &QProcess::finished, this, [this, p] {
        const QJsonObject root =
            QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        p->deleteLater();

        m_results.clear();
        for (const QJsonValue &v : root[QStringLiteral("apps")].toArray()) {
            m_results.append(toMap(v.toObject()));
        }
        // Kept distinct from "no matches": a source we could not reach is a
        // different answer, and saying so is the whole point.
        m_unavailable = root[QStringLiteral("unavailable")].toObject().toVariantMap();
        m_searching = false;
        Q_EMIT stateChanged();
        Q_EMIT resultsChanged();
    });
}

void Backend::loadFeatured()
{
    // Flathub publishes real collections. The front page used to run a search
    // for the word "editor" and label the result "Popular right now", which
    // was not true, and then reused those same six apps for the grid below the
    // carousel -- so the page showed one list twice. Trending drives the
    // carousel because it turns over; popular drives the grid because it does
    // not. Both update themselves; nobody has to curate a promo slot.
    loadCollection(QStringLiteral("trending"), 8, m_featured);
    loadCollection(QStringLiteral("popular"), 12, m_popular);
}

void Backend::loadCollection(const QString &name, int limit, QVariantList &into)
{
    auto *p = run({QStringLiteral("collection"), name,
                   QStringLiteral("--limit"), QString::number(limit),
                   QStringLiteral("--json")});
    connect(p, &QProcess::finished, this, [this, p, &into] {
        const QJsonObject root =
            QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        p->deleteLater();
        into.clear();
        for (const QJsonValue &v : root[QStringLiteral("apps")].toArray()) {
            into.append(toMap(v.toObject()));
        }
        // The front page has to report a failing engine too, not just search.
        m_unavailable = root[QStringLiteral("unavailable")].toObject().toVariantMap();
        Q_EMIT resultsChanged();
        Q_EMIT featuredChanged();
    });
}

void Backend::loadCategory(const QString &id, const QString &label)
{
    m_loadingCategory = true;
    m_categoryName = label;
    m_categoryApps.clear();
    Q_EMIT categoryChanged();
    auto *p = run({QStringLiteral("category"), id,
                   QStringLiteral("--limit"), QStringLiteral("36"),
                   QStringLiteral("--json")});
    connect(p, &QProcess::finished, this, [this, p] {
        const QJsonObject root =
            QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        p->deleteLater();
        m_categoryApps.clear();
        for (const QJsonValue &v : root[QStringLiteral("apps")].toArray()) {
            m_categoryApps.append(toMap(v.toObject()));
        }
        m_unavailable = root[QStringLiteral("unavailable")].toObject().toVariantMap();
        Q_EMIT resultsChanged();
        m_loadingCategory = false;
        Q_EMIT categoryChanged();
    });
}

void Backend::checkUpdates()
{
    m_checkingUpdates = true;
    Q_EMIT updatesChanged();
    auto *p = run({QStringLiteral("updates"), QStringLiteral("--json")});
    connect(p, &QProcess::finished, this, [this, p] {
        const QJsonObject root =
            QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        p->deleteLater();
        m_updates.clear();
        for (const QJsonValue &v : root[QStringLiteral("updates")].toArray()) {
            m_updates.append(toMap(v.toObject()));
        }
        m_unavailable = root[QStringLiteral("unavailable")].toObject().toVariantMap();
        m_checkingUpdates = false;
        Q_EMIT updatesChanged();
        Q_EMIT resultsChanged();
    });
}

void Backend::applyUpdates(const QString &id, const QString &source)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_error.clear();
    m_errorDetail.clear();
    m_percent = 0;
    m_bytes = m_total = 0;
    m_count = m_countTotal = 0;
    m_stage = QStringLiteral("resolving");
    Q_EMIT progressChanged();

    QStringList args{QStringLiteral("update")};
    if (!id.isEmpty()) {
        args << QStringLiteral("--id") << id;
    }
    if (!source.isEmpty()) {
        args << QStringLiteral("--source") << source;
    }

    auto *p = run(args);
    p->setProcessChannelMode(QProcess::MergedChannels);
    connect(p, &QProcess::readyReadStandardOutput, this, [this, p] {
        while (p->canReadLine()) {
            const QJsonObject o =
                QJsonDocument::fromJson(p->readLine()).object();
            if (o.isEmpty()) {
                continue;
            }
            const QString stage = o[QStringLiteral("stage")].toString();
            if (stage == QLatin1String("failed")) {
                m_error = o[QStringLiteral("error")].toString();
                m_errorDetail = o[QStringLiteral("detail")].toString();
            } else {
                m_stage = stage;
                const QString d = o[QStringLiteral("detail")].toString();
                if (!d.isEmpty()) {
                    m_detail = d;
                }
                if (o.contains(QStringLiteral("percent"))) {
                    m_percent = o[QStringLiteral("percent")].toInt();
                }
                // Sizes only arrive while something is being fetched. Cleared
                // on any other stage so that "48 MB of 96 MB" does not sit
                // under a progress bar that has moved on to installing.
                if (o.contains(QStringLiteral("total"))) {
                    m_bytes = static_cast<qint64>(
                        o[QStringLiteral("bytes")].toDouble());
                    m_total = static_cast<qint64>(
                        o[QStringLiteral("total")].toDouble());
                }
                if (o.contains(QStringLiteral("count_total"))) {
                    m_count = o[QStringLiteral("count")].toInt();
                    m_countTotal = o[QStringLiteral("count_total")].toInt();
                }
                if (stage != QLatin1String("downloading")
                        && stage != QLatin1String("installing")
                        && stage != QLatin1String("removing")) {
                    m_bytes = m_total = 0;
                    m_count = m_countTotal = 0;
                }
            }
            Q_EMIT progressChanged();
        }
    });
    connect(p, &QProcess::finished, this,
            [this, p](int code, QProcess::ExitStatus status) {
        const QString trailing = QString::fromUtf8(p->readAll()).trimmed();
        p->deleteLater();
        m_busy = false;
        if (m_error.isEmpty() && (code != 0 || status != QProcess::NormalExit)) {
            m_error = trailing.isEmpty() ? tr("Some updates did not finish.")
                                         : trailing.section(QLatin1Char('\n'), -1);
        }
        m_stage = m_error.isEmpty() ? QStringLiteral("done")
                                    : QStringLiteral("failed");
        Q_EMIT progressChanged();
        // The list has changed either way, and what is left is what failed.
        checkUpdates();
        loadInstalled();
    });
}

void Backend::loadInstalled()
{
    m_loadingInstalled = true;
    Q_EMIT installedChanged();
    // The engine returns applications rather than packages -- a native
    // package list would be a thousand entries of operating system.
    auto *p = run({QStringLiteral("installed"), QStringLiteral("--json")});
    connect(p, &QProcess::finished, this, [this, p] {
        const QJsonArray rows =
            QJsonDocument::fromJson(p->readAllStandardOutput()).array();
        p->deleteLater();
        m_installed.clear();
        for (const QJsonValue &v : rows) {
            m_installed.append(toMap(v.toObject()));
        }
        // Group by source, then by the name actually shown, so the list has a
        // stable order that matches how it reads.
        std::sort(m_installed.begin(), m_installed.end(),
                  [](const QVariant &a, const QVariant &b) {
            const QVariantMap x = a.toMap(), y = b.toMap();
            const QString xs = x.value(QStringLiteral("source")).toString();
            const QString ys = y.value(QStringLiteral("source")).toString();
            if (xs != ys) {
                return xs < ys;
            }
            return x.value(QStringLiteral("name")).toString().compare(
                   y.value(QStringLiteral("name")).toString(),
                   Qt::CaseInsensitive) < 0;
        });
        m_loadingInstalled = false;
        Q_EMIT installedChanged();
    });
}

void Backend::openApp(const QString &id)
{
    // Moving somewhere else clears a failure from the last thing. Left in
    // place it reappears over a page it has nothing to do with, which reads
    // as the new page having failed.
    m_error.clear();
    m_errorDetail.clear();
    m_loadingApp = true;
    m_app.clear();
    Q_EMIT stateChanged();
    Q_EMIT appChanged();

    auto *p = run({QStringLiteral("info"), id, QStringLiteral("--json")});
    connect(p, &QProcess::finished, this, [this, p] {
        m_app = QJsonDocument::fromJson(p->readAllStandardOutput())
                    .object().toVariantMap();
        p->deleteLater();
        m_loadingApp = false;
        Q_EMIT stateChanged();
        Q_EMIT appChanged();
    });
}

// Re-reads the open page without tearing it down. openApp() clears the app
// and raises the spinner, which is right when you have navigated somewhere
// new and wrong here: it blanks the page you are looking at for as long as
// the lookup takes, immediately after telling you the install finished.
void Backend::refreshApp(const QString &id)
{
    if (id.isEmpty()) {
        return;
    }
    auto *p = run({QStringLiteral("info"), id, QStringLiteral("--json")});
    connect(p, &QProcess::finished, this, [this, p] {
        const QVariantMap m = QJsonDocument::fromJson(p->readAllStandardOutput())
                                  .object().toVariantMap();
        p->deleteLater();
        // An empty result means the lookup failed. Leaving the page a moment
        // stale beats replacing a good one with nothing.
        if (!m.isEmpty()) {
            m_app = m;
            Q_EMIT appChanged();
        }
    });
}

void Backend::clearAurReview()
{
    m_aurReview.clear();
    m_aurReviewLoading = false;
    Q_EMIT aurReviewChanged();
}

void Backend::reviewAur(const QString &name)
{
    if (m_aurReviewLoading) {
        return;
    }
    m_aurReviewLoading = true;
    m_aurReview.clear();
    Q_EMIT aurReviewChanged();

    auto *p = run({QStringLiteral("aur-review"), name});
    connect(p, &QProcess::finished, this, [this, p, name] {
        m_aurReview = QJsonDocument::fromJson(p->readAllStandardOutput())
                          .object().toVariantMap();
        p->deleteLater();
        m_aurReviewLoading = false;
        // An empty object means the engine died rather than the AUR saying
        // no; the pane has to say something either way or it sits blank.
        if (m_aurReview.isEmpty()) {
            m_aurReview.insert(QStringLiteral("error"),
                               tr("The build script for %1 could not be read.")
                                   .arg(name));
        }
        Q_EMIT aurReviewChanged();
    });
}

void Backend::acceptAurAndInstall(const QString &name)
{
    if (m_busy) {
        return;
    }
    // Recorded first and separately: the acceptance is what a later install
    // is checked against, and it has to survive a build that fails.
    auto *p = run({QStringLiteral("aur-accept"), name});
    connect(p, &QProcess::finished, this, [this, p, name] {
        const QVariantMap m = QJsonDocument::fromJson(p->readAllStandardOutput())
                                  .object().toVariantMap();
        p->deleteLater();
        if (!m.contains(QStringLiteral("accepted"))) {
            m_error = m.value(QStringLiteral("error"))
                          .toString().isEmpty()
                      ? tr("The build script could not be recorded as read.")
                      : m.value(QStringLiteral("error")).toString();
            m_stage = QStringLiteral("failed");
            Q_EMIT progressChanged();
            return;
        }
        clearAurReview();
        install(name, QStringLiteral("aur"));
    });
}

void Backend::resetReview()
{
    m_reviewBusy = false;
    m_reviewDone = false;
    m_reviewError.clear();
    Q_EMIT reviewChanged();
}

void Backend::submitReview(const QString &id, int rating,
                           const QString &summary, const QString &description,
                           const QString &name, const QString &version)
{
    if (m_reviewBusy) {
        return;
    }
    m_reviewBusy = true;
    m_reviewDone = false;
    m_reviewError.clear();
    Q_EMIT reviewChanged();

    QStringList args{QStringLiteral("review"), id,
                     QStringLiteral("--rating"), QString::number(rating),
                     QStringLiteral("--summary"), summary,
                     QStringLiteral("--description"), description,
                     QStringLiteral("--name"), name,
                     QStringLiteral("--json")};
    if (!version.isEmpty()) {
        args << QStringLiteral("--version") << version;
    }

    auto *p = run(args);
    connect(p, &QProcess::finished, this, [this, p] {
        const QVariantMap m = QJsonDocument::fromJson(p->readAllStandardOutput())
                                  .object().toVariantMap();
        p->deleteLater();
        m_reviewBusy = false;
        // No parseable answer means the engine died rather than the service
        // refusing; saying "not accepted" would blame the wrong party.
        if (m.isEmpty()) {
            m_reviewError = tr("The review could not be sent.");
        } else {
            m_reviewDone = m.value(QStringLiteral("ok")).toBool();
            m_reviewError = m_reviewDone
                ? QString()
                : m.value(QStringLiteral("error")).toString();
        }
        Q_EMIT reviewChanged();
        if (m_reviewDone) {
            notify(tr("Your review has been published"));
        }
    });
}

void Backend::install(const QString &id, const QString &source)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_busyId = id;
    // The display name if the page knows one, so the notification can say
    // "Sober has been installed" rather than an application id.
    m_busyName = m_app.value(QStringLiteral("name")).toString();
    if (m_busyName.isEmpty()) {
        m_busyName = id;
    }
    m_error.clear();
    m_errorDetail.clear();
    m_percent = 0;
    m_bytes = m_total = 0;
    m_stage = QStringLiteral("resolving");
    m_detail.clear();
    Q_EMIT progressChanged();

    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);

    connect(p, &QProcess::readyReadStandardOutput, this, [this, p] {
        // The engine emits one JSON object per line so progress can be read
        // as it happens rather than after the process ends.
        while (p->canReadLine()) {
            const QJsonObject o =
                QJsonDocument::fromJson(p->readLine()).object();
            if (o.isEmpty()) {
                continue;
            }
            const QString stage = o[QStringLiteral("stage")].toString();
            if (stage == QLatin1String("failed")) {
                m_error = o[QStringLiteral("error")].toString();
                m_errorDetail = o[QStringLiteral("detail")].toString();
            } else {
                m_stage = stage;
                if (o.contains(QStringLiteral("percent"))) {
                    m_percent = o[QStringLiteral("percent")].toInt();
                }
                // Sizes only arrive while something is being fetched. Cleared
                // on any other stage so that "48 MB of 96 MB" does not sit
                // under a progress bar that has moved on to installing.
                if (o.contains(QStringLiteral("total"))) {
                    m_bytes = static_cast<qint64>(
                        o[QStringLiteral("bytes")].toDouble());
                    m_total = static_cast<qint64>(
                        o[QStringLiteral("total")].toDouble());
                }
                if (o.contains(QStringLiteral("count_total"))) {
                    m_count = o[QStringLiteral("count")].toInt();
                    m_countTotal = o[QStringLiteral("count_total")].toInt();
                }
                if (stage != QLatin1String("downloading")
                        && stage != QLatin1String("installing")
                        && stage != QLatin1String("removing")) {
                    m_bytes = m_total = 0;
                    m_count = m_countTotal = 0;
                }
                const QString d = o[QStringLiteral("detail")].toString();
                if (!d.isEmpty()) {
                    m_detail = d;
                }
            }
            Q_EMIT progressChanged();
        }
    });
    connect(p, &QProcess::finished, this,
            [this, p, id](int code, QProcess::ExitStatus status) {
        // Anything the engine printed that was not a progress line. A crash
        // arrives as a traceback, which is not JSON, so nothing above sees it.
        const QString trailing = QString::fromUtf8(p->readAll()).trimmed();
        p->deleteLater();
        m_busy = false;
        if (m_error.isEmpty()
            && (code != 0 || status != QProcess::NormalExit)) {
            // A process that failed must never render as "done". It did
            // exactly that: the engine died with a PermissionError, emitted no
            // failed event because the traceback was not JSON, and the store
            // showed a completed install that had not happened.
            const QString last = trailing.section(QLatin1Char('\n'), -1).trimmed();
            m_error = last.isEmpty()
                ? tr("The install did not finish (exit code %1).").arg(code)
                : last;
        }
        if (m_error.isEmpty()) {
            m_stage = QStringLiteral("done");
            m_percent = 100;
            notify(tr("%1 has been installed").arg(m_busyName));
        } else {
            m_stage = QStringLiteral("failed");
        }
        m_busyId.clear();
        Q_EMIT progressChanged();
        // Re-open the app, not the package. Installing GIMP from the
        // repositories passes "gimp", and asking the app page to load "gimp"
        // finds nothing on Flathub -- so a successful install left the page
        // blank. The canonical id is whatever the page was already showing.
        const QString shown = m_app.value(QStringLiteral("id")).toString();
        refreshApp(shown.isEmpty() ? id : shown);
    });

    p->start(QString::fromLatin1(ENGINE),
             {QStringLiteral("install"), id, QStringLiteral("--source"), source});
}

void Backend::planRemoval(const QString &id, const QString &source)
{
    // Asked before anything is removed, so the confirmation can say what will
    // actually happen rather than "are you sure?" with nothing behind it.
    m_planningRemoval = true;
    m_removalPlan.clear();
    m_removalPlan.insert(QStringLiteral("id"), id);
    m_removalPlan.insert(QStringLiteral("source"), source);
    Q_EMIT removalPlanChanged();

    auto *p = run({QStringLiteral("remove-plan"), id,
                   QStringLiteral("--source"), source, QStringLiteral("--json")});
    connect(p, &QProcess::finished, this, [this, p, id, source] {
        const QJsonObject o =
            QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        p->deleteLater();
        m_removalPlan = toMap(o);
        // The id and source are what the confirmation acts on; the engine's
        // reply does not echo them back.
        m_removalPlan.insert(QStringLiteral("id"), id);
        m_removalPlan.insert(QStringLiteral("source"), source);
        m_planningRemoval = false;
        Q_EMIT removalPlanChanged();
    });
}

void Backend::clearRemovalPlan()
{
    m_removalPlan.clear();
    m_planningRemoval = false;
    Q_EMIT removalPlanChanged();
}

void Backend::remove(const QString &id, const QString &source, bool deleteData)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_error.clear();
    m_errorDetail.clear();
    m_stage = QStringLiteral("removing");
    m_detail = tr("removing");
    Q_EMIT progressChanged();
    clearRemovalPlan();

    QStringList args{QStringLiteral("remove"), id,
                     QStringLiteral("--source"), source};
    if (deleteData) {
        args << QStringLiteral("--delete-data");
    }
    auto *p = run(args);
    connect(p, &QProcess::finished, this, [this, p, id, source] {
        p->deleteLater();
        m_busy = false;
        m_stage = QStringLiteral("done");
        Q_EMIT progressChanged();
        // The view decides what to refresh. Re-opening the app page here was
        // wrong for a removal started from the Installed list, and impossible
        // for a repository-only or AUR application, which has no Flathub
        // entry for that page to load.
        const QString shown = m_app.value(QStringLiteral("id")).toString();
        Q_EMIT removed(shown.isEmpty() ? id : shown, source);
    });
}

void Backend::installLocalAppImage(const QString &path)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_error.clear();
    m_errorDetail.clear();
    m_percent = 0;
    m_bytes = m_total = 0;
    m_stage = QStringLiteral("resolving");
    m_detail.clear();
    Q_EMIT progressChanged();

    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    connect(p, &QProcess::readyReadStandardOutput, this, [this, p] {
        while (p->canReadLine()) {
            const QJsonObject o =
                QJsonDocument::fromJson(p->readLine()).object();
            if (o.isEmpty()) {
                continue;
            }
            const QString stage = o[QStringLiteral("stage")].toString();
            if (stage == QLatin1String("failed")) {
                m_error = o[QStringLiteral("error")].toString();
                m_errorDetail = o[QStringLiteral("detail")].toString();
            } else {
                m_stage = stage;
                const QString d = o[QStringLiteral("detail")].toString();
                if (!d.isEmpty()) {
                    m_detail = d;
                }
            }
            Q_EMIT progressChanged();
        }
    });
    connect(p, &QProcess::finished, this,
            [this, p](int code, QProcess::ExitStatus status) {
        const QString trailing = QString::fromUtf8(p->readAll()).trimmed();
        p->deleteLater();
        m_busy = false;
        if (m_error.isEmpty() && (code != 0 || status != QProcess::NormalExit)) {
            m_error = trailing.isEmpty()
                ? tr("The AppImage could not be installed.")
                : trailing.section(QLatin1Char('\n'), -1);
        }
        m_stage = m_error.isEmpty() ? QStringLiteral("done")
                                    : QStringLiteral("failed");
        m_percent = m_error.isEmpty() ? 100 : 0;
        Q_EMIT progressChanged();
        loadInstalled();
    });
    p->start(QString::fromLatin1(ENGINE),
             {QStringLiteral("install"), QStringLiteral("--source"),
              QStringLiteral("appimage"), QStringLiteral("--file"), path});
}

void Backend::clearError()
{
    // A failure that follows you onto the next page reads as though it just
    // happened again. It stays until the user dismisses it or starts
    // something new, and no longer than that.
    if (m_error.isEmpty() && m_errorDetail.isEmpty()) {
        return;
    }
    m_error.clear();
    m_errorDetail.clear();
    if (m_stage == QLatin1String("failed")) {
        m_stage.clear();
    }
    Q_EMIT progressChanged();
}

void Backend::openPermissions(const QString &id)
{
    // Plasma already ships this, so linking to it puts the control where the
    // user is thinking about the app rather than in a second application that
    // does the same job in another toolkit.
    //
    // systemsettings takes module arguments through --args; passing the id
    // positionally is read as a second module name and silently ignored,
    // which is why the button appeared to do nothing.
    QProcess::startDetached(QStringLiteral("systemsettings"),
                            {QStringLiteral("--args"), id,
                             QStringLiteral("kcm_app-permissions")});
}


// ---- who is signed in ------------------------------------------------------
//
// From the password database, not from a SakuraOS account, because there is no
// SakuraOS account. The store shows who you are on this machine so that "your
// apps" means something concrete; it does not sign you in to anything.

QString Backend::downloadProgress() const
{
    const bool downloading = m_stage == QLatin1String("downloading");
    const bool installing = m_stage == QLatin1String("installing")
                         || m_stage == QLatin1String("removing");
    if (!downloading && !installing) {
        return QString();
    }
    // Decimal MB, matching what the package manager and every download
    // dialogue the user has ever seen report.
    const double mb = 1000.0 * 1000.0;

    // A real byte stream: the engine is reading a single file and counting
    // what it has. Only the AppImage path can say this.
    if (m_bytes > 0 && m_total > 0) {
        // One "MB", not two. This sits inside the button that is also the
        // progress bar, and the button was asked to get smaller, not wider.
        return tr("%1 of %2 MB")
            .arg(m_bytes / mb, 0, 'f', 1)
            .arg(m_total / mb, 0, 'f', 1);
    }

    // Writing packages: one line per package as it lands, so the count is
    // real progress rather than a summary printed at the end.
    if (installing && m_countTotal > 0 && m_count > 0) {
        return tr("%1 of %2").arg(m_count).arg(m_countTotal);
    }

    // Fetching from a repository: the size is known and the position in it
    // is not, so the size is all that gets said. The ring spins rather than
    // filling, which is what not knowing looks like.
    if (downloading && m_total > 0) {
        return tr("%1 MB").arg(m_total / mb, 0, 'f', 1);
    }
    return QString();
}

QString Backend::userName() const
{
    const struct passwd *pw = getpwuid(getuid());
    return pw && pw->pw_name ? QString::fromLocal8Bit(pw->pw_name) : QString();
}

QString Backend::userDisplayName() const
{
    const struct passwd *pw = getpwuid(getuid());
    if (pw && pw->pw_gecos) {
        // GECOS is comma-separated and only the first field is the name; the
        // rest is office and phone numbers nobody has filled in since 1978.
        const QString full = QString::fromLocal8Bit(pw->pw_gecos).section(QLatin1Char(','), 0, 0).trimmed();
        if (!full.isEmpty()) {
            return full;
        }
    }
    return userName();
}

QString Backend::userAvatar() const
{
    const QString home = QDir::homePath();
    const QString user = userName();
    // The places a Plasma desktop actually keeps one, most personal first.
    const QStringList candidates{
        home + QStringLiteral("/.face.icon"),
        home + QStringLiteral("/.face"),
        QStringLiteral("/var/lib/AccountsService/icons/") + user,
    };
    for (const QString &c : candidates) {
        if (QFileInfo::exists(c)) {
            return QStringLiteral("file://") + c;
        }
    }
    return QString();   // the UI draws an initial instead
}

// ---- app lists -------------------------------------------------------------

void Backend::exportAppList(const QString &path)
{
    QString file = path;
    if (file.startsWith(QStringLiteral("file://"))) {
        file = QUrl(file).toLocalFile();
    }
    m_stage = QStringLiteral("Writing the list");
    m_busy = true;
    Q_EMIT progressChanged();

    auto *p = run({QStringLiteral("export-list"), QStringLiteral("--output"), file});
    connect(p, &QProcess::finished, this, [this, p, file] {
        const QJsonObject o = QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        p->deleteLater();
        m_busy = false;
        m_stage.clear();
        if (o.contains(QStringLiteral("written"))) {
            m_stage = tr("Saved %1 applications to %2")
                          .arg(o.value(QStringLiteral("count")).toInt())
                          .arg(QFileInfo(file).fileName());
        } else {
            m_error = tr("That list could not be written.");
        }
        Q_EMIT progressChanged();
    });
}

void Backend::readAppList(const QString &path)
{
    QString file = path;
    if (file.startsWith(QStringLiteral("file://"))) {
        file = QUrl(file).toLocalFile();
    }
    auto *p = run({QStringLiteral("read-list"), file});
    connect(p, &QProcess::finished, this, [this, p] {
        const QJsonObject o = QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        p->deleteLater();
        m_importPlan = toMap(o);
        Q_EMIT importPlanChanged();
        if (o.contains(QStringLiteral("error"))) {
            m_error = o.value(QStringLiteral("error")).toString();
            Q_EMIT progressChanged();
        }
    });
}

void Backend::clearImportPlan()
{
    m_importPlan.clear();
    Q_EMIT importPlanChanged();
}


// ---- desktop notification --------------------------------------------------

void Backend::notify(const QString &text) const
{
    // Through the desktop's own notification service rather than a banner of
    // our own. An install can take minutes; by the time it finishes the window
    // is usually behind something else, and a message drawn inside a hidden
    // window is a message nobody receives.
    QDBusMessage m = QDBusMessage::createMethodCall(
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("/org/freedesktop/Notifications"),
        QStringLiteral("org.freedesktop.Notifications"),
        QStringLiteral("Notify"));
    m << QStringLiteral("Sakura Store")
      << uint(0)
      << QStringLiteral("sakura-store")
      << text
      << QString()
      << QStringList()
      << QVariantMap{{QStringLiteral("desktop-entry"),
                      QStringLiteral("org.sakuraos.store")}}
      << 6000;
    // send(), not asyncCall(): there is no reply worth waiting for, and the
    // notification must never be able to block or fail an install.
    QDBusConnection::sessionBus().send(m);
}
