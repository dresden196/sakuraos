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
// Overridable so the queue can be exercised against a stub engine that emits
// scripted progress. The queue's whole job is deciding what may run beside what
// and what must wait, and that is not observable by installing one package by
// hand -- it needs several transactions, with known timing, run repeatedly.
// Nothing in a package ever sets this; the default is the real engine.
// A function holding a QString, not a const char* taken from a temporary.
//
// The first version of this was
//     const auto ENGINE = ... ? qgetenv(...).constData() : "/usr/bin/...";
// which is a dangling pointer: qgetenv returns a QByteArray by value, the
// temporary dies at the end of the expression, and ENGINE is left pointing at
// freed memory. Every QProcess::start then failed to launch, every job failed,
// and because failed jobs stay in the queue on purpose the whole thing looked
// like a queue that never drained. Nine tests caught it at once, which is
// precisely what they were written for.
static QString enginePath()
{
    static const QString path =
        qEnvironmentVariableIsSet("SAKURA_STORE_ENGINE")
            ? QString::fromLocal8Bit(qgetenv("SAKURA_STORE_ENGINE"))
            : QStringLiteral("/usr/bin/sakura-store");
    return path;
}

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
        p.start(enginePath(),
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
        p.start(enginePath(),
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
    p->start(enginePath(), args);
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
    Job j;
    // An update of everything has no id of its own, so it gets a stable one:
    // two "update everything" presses are one job, not two, and the queue can
    // find it again like any other.
    j.id = id.isEmpty() ? QStringLiteral("*") : id;
    j.source = source;
    j.kind = QStringLiteral("update");
    j.stage = QStringLiteral("queued");
    j.name = id.isEmpty() ? tr("All updates") : id;
    j.args = QStringList{QStringLiteral("update")};
    if (!id.isEmpty()) {
        j.args << QStringLiteral("--id") << id;
    }
    if (!source.isEmpty()) {
        j.args << QStringLiteral("--source") << source;
    }
    m_error.clear();
    m_errorDetail.clear();
    enqueue(j);
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

// ---------------------------------------------------------------- the queue

QString Backend::laneOf(const QString &source)
{
    // What actually serialises, rather than what the user picked. pacman takes
    // an exclusive lock on its database, and an AUR build ends in pacman -U, so
    // those two share a lane and everything else gets one of its own. Two
    // flatpaks in a row is a queue; a flatpak beside a pacman install is two
    // things happening at once, which is the whole point.
    if (source.isEmpty() || source == QLatin1String("pacman")
            || source == QLatin1String("aur")) {
        return QStringLiteral("pacman");
    }
    return source;
}

int Backend::indexOfJob(const QString &id, const QString &source) const
{
    for (int i = 0; i < m_jobs.size(); ++i) {
        if (m_jobs.at(i).id == id && m_jobs.at(i).source == source) {
            return i;
        }
    }
    return -1;
}

QVariantMap Backend::jobToMap(const Job &j) const
{
    QVariantMap m;
    m.insert(QStringLiteral("id"), j.id);
    m.insert(QStringLiteral("source"), j.source);
    m.insert(QStringLiteral("name"), j.name.isEmpty() ? j.id : j.name);
    m.insert(QStringLiteral("kind"), j.kind);
    m.insert(QStringLiteral("stage"), j.stage);
    m.insert(QStringLiteral("detail"), j.detail);
    m.insert(QStringLiteral("error"), j.error);
    m.insert(QStringLiteral("errorDetail"), j.errorDetail);
    m.insert(QStringLiteral("percent"), j.percent);
    m.insert(QStringLiteral("running"), j.proc != nullptr);
    m.insert(QStringLiteral("queued"),
             j.proc == nullptr && j.stage == QLatin1String("queued"));
    m.insert(QStringLiteral("failed"), j.stage == QLatin1String("failed"));
    m.insert(QStringLiteral("progress"), formatProgress(j.bytes, j.total,
                                                        j.count, j.countTotal,
                                                        j.stage));
    return m;
}

QVariantList Backend::jobs() const
{
    QVariantList out;
    out.reserve(m_jobs.size());
    for (const Job &j : m_jobs) {
        out.append(jobToMap(j));
    }
    return out;
}

QVariantMap Backend::jobFor(const QString &id, const QString &source) const
{
    const int k = indexOfJob(id, source);
    return k < 0 ? QVariantMap() : jobToMap(m_jobs.at(k));
}

void Backend::cancelJob(const QString &id, const QString &source)
{
    const int k = indexOfJob(id, source);
    if (k < 0 || m_jobs.at(k).proc) {
        // Running jobs are left alone deliberately. Killing pacman part way
        // through a transaction leaves a half-installed package and a stale
        // lock, and the person who pressed cancel would then own a problem
        // considerably larger than the one they were trying to avoid.
        return;
    }
    m_jobs.remove(k);
    Q_EMIT jobsChanged();
    syncCurrentFromJobs();
}

void Backend::dismissJob(const QString &id, const QString &source)
{
    const int k = indexOfJob(id, source);
    if (k < 0 || m_jobs.at(k).proc) {
        return;
    }
    m_jobs.remove(k);
    Q_EMIT jobsChanged();
    syncCurrentFromJobs();
}

void Backend::enqueue(const Job &job)
{
    // Asking twice for the same thing is a double click, not a second install.
    if (indexOfJob(job.id, job.source) >= 0) {
        return;
    }
    m_jobs.append(job);
    Q_EMIT jobsChanged();
    pump();
}

void Backend::pump()
{
    QSet<QString> busyLanes;
    for (const Job &j : m_jobs) {
        if (j.proc) {
            busyLanes.insert(laneOf(j.source));
        }
    }

    for (int i = 0; i < m_jobs.size(); ++i) {
        if (m_jobs.at(i).proc
                || m_jobs.at(i).stage == QLatin1String("failed")
                || m_jobs.at(i).stage == QLatin1String("done")) {
            continue;
        }
        const QString lane = laneOf(m_jobs.at(i).source);
        if (busyLanes.contains(lane)) {
            continue;
        }
        busyLanes.insert(lane);

        const QString id = m_jobs.at(i).id;
        const QString src = m_jobs.at(i).source;
        auto *proc = new QProcess(this);
        proc->setProcessChannelMode(QProcess::MergedChannels);
        m_jobs[i].proc = proc;
        m_jobs[i].stage = QStringLiteral("resolving");

        // The job is found again by id rather than captured by index: the
        // vector moves as jobs finish and are removed, and an index captured
        // here would be pointing at somebody else's work by the time a line
        // arrives.
        connect(proc, &QProcess::readyReadStandardOutput, this,
                [this, proc, id, src] {
            while (proc->canReadLine()) {
                const QJsonObject o =
                    QJsonDocument::fromJson(proc->readLine()).object();
                if (o.isEmpty()) {
                    continue;
                }
                const int k = indexOfJob(id, src);
                if (k < 0) {
                    continue;
                }
                onJobLine(k, o);
            }
        });
        connect(proc, &QProcess::finished, this,
                [this, proc, id, src](int code, QProcess::ExitStatus status) {
            const QString trailing = QString::fromUtf8(proc->readAll()).trimmed();
            proc->deleteLater();
            const int k = indexOfJob(id, src);
            if (k >= 0) {
                m_jobs[k].proc = nullptr;
                finishJob(k, code, status != QProcess::NormalExit, trailing);
            }
            // Whatever was waiting on this lane can start now.
            pump();
        });
        proc->start(enginePath(), m_jobs.at(i).args);
    }

    Q_EMIT jobsChanged();
    syncCurrentFromJobs();
}

void Backend::onJobLine(int index, const QJsonObject &o)
{
    Job &j = m_jobs[index];
    const QString stage = o[QStringLiteral("stage")].toString();
    if (stage == QLatin1String("failed")) {
        j.error = o[QStringLiteral("error")].toString();
        j.errorDetail = o[QStringLiteral("detail")].toString();
    } else {
        j.stage = stage;
        if (o.contains(QStringLiteral("percent"))) {
            j.percent = o[QStringLiteral("percent")].toInt();
        }
        if (o.contains(QStringLiteral("total"))) {
            j.bytes = static_cast<qint64>(o[QStringLiteral("bytes")].toDouble());
            j.total = static_cast<qint64>(o[QStringLiteral("total")].toDouble());
        }
        if (o.contains(QStringLiteral("count_total"))) {
            j.count = o[QStringLiteral("count")].toInt();
            j.countTotal = o[QStringLiteral("count_total")].toInt();
        }
        // Sizes belong to fetching. Left standing they sit under a bar that has
        // moved on to installing, describing a download that finished.
        if (stage != QLatin1String("downloading")
                && stage != QLatin1String("installing")
                && stage != QLatin1String("removing")) {
            j.bytes = j.total = 0;
            j.count = j.countTotal = 0;
        }
        const QString d = o[QStringLiteral("detail")].toString();
        if (!d.isEmpty()) {
            j.detail = d;
        }
    }
    Q_EMIT jobsChanged();
    syncCurrentFromJobs();
}

void Backend::finishJob(int index, int code, bool crashed, const QString &trailing)
{
    Job j = m_jobs.at(index);

    if (j.error.isEmpty() && (code != 0 || crashed)) {
        // A process that failed must never render as done. It did exactly
        // that once: the engine died with a PermissionError, emitted no failed
        // event because a traceback is not JSON, and the store showed a
        // completed install that had not happened.
        const QString last = trailing.section(QLatin1Char('\n'), -1).trimmed();
        j.error = last.isEmpty()
            ? tr("The job did not finish (exit code %1).").arg(code)
            : last;
    }

    if (j.error.isEmpty()) {
        j.stage = QStringLiteral("done");
        j.percent = 100;
        if (j.kind == QLatin1String("remove")) {
            notify(tr("%1 has been removed").arg(j.name));
        } else if (j.kind == QLatin1String("update")) {
            notify(tr("Updates have been installed"));
        } else {
            notify(tr("%1 has been installed").arg(j.name));
        }
    } else {
        j.stage = QStringLiteral("failed");
    }
    m_jobs[index] = j;

    if (j.error.isEmpty()) {
        // Record the outcome now rather than when the lookup returns. The app
        // page re-query takes several seconds, and until it came back the page
        // still said "Install" -- immediately after saying the install had
        // finished.
        if (j.kind == QLatin1String("install")) {
            markInstalled(j.id, j.source, true);
        } else if (j.kind == QLatin1String("remove")) {
            markInstalled(j.id, j.source, false);
            Q_EMIT removed(j.id, j.source);
        }
        // Succeeded jobs leave the queue; there is nothing further to say
        // about them and a list of completed work is not what the panel is
        // for. Failures stay until dismissed, because a failure nobody sees
        // is the same as one that did not happen.
        m_jobs.remove(index);
    }

    Q_EMIT jobsChanged();
    syncCurrentFromJobs();

    if (j.error.isEmpty()) {
        loadInstalled();
        const QString shown = m_app.value(QStringLiteral("id")).toString();
        if (!shown.isEmpty()) {
            refreshApp(shown);
        }
    }
}

void Backend::markInstalled(const QString &id, const QString &source, bool state)
{
    if (m_app.isEmpty()) {
        return;
    }
    // The entry that was actually acted on, not the first one on the page.
    // The option list is the primary followed by also_from, and only the
    // primary reads its flag from the top level. Marking the primary for an
    // install that came from the repositories flagged the wrong source -- and
    // since the picker selects the first installed option, it also quietly
    // moved the page to Flatpak.
    if (m_app.value(QStringLiteral("id")).toString() == id
            && m_app.value(QStringLiteral("source")).toString() == source) {
        m_app[QStringLiteral("installed")] = state;
        Q_EMIT appChanged();
        return;
    }
    QVariantList alts = m_app.value(QStringLiteral("also_from")).toList();
    for (int i = 0; i < alts.size(); ++i) {
        QVariantMap e = alts.at(i).toMap();
        if (e.value(QStringLiteral("id")).toString() == id
                && e.value(QStringLiteral("source")).toString() == source) {
            e[QStringLiteral("installed")] = state;
            alts[i] = e;
            m_app[QStringLiteral("also_from")] = alts;
            Q_EMIT appChanged();
            return;
        }
    }
}

void Backend::syncCurrentFromJobs()
{
    // The single set of progress fields still exists, and still means what it
    // always did -- except that "the transaction" is now "the job belonging to
    // the application on screen". A transaction for something else no longer
    // drives this page's bar, and no longer greys out its button.
    const QString appId = m_app.value(QStringLiteral("id")).toString();
    int k = -1;
    if (!appId.isEmpty()) {
        for (int i = 0; i < m_jobs.size(); ++i) {
            if (m_jobs.at(i).id == appId) {
                k = i;
                break;
            }
        }
        if (k < 0) {
            const QVariantList alts =
                m_app.value(QStringLiteral("also_from")).toList();
            for (const QVariant &v : alts) {
                const QVariantMap e = v.toMap();
                const int c = indexOfJob(e.value(QStringLiteral("id")).toString(),
                                         e.value(QStringLiteral("source")).toString());
                if (c >= 0) {
                    k = c;
                    break;
                }
            }
        }
    }

    if (k < 0) {
        // Nothing running for this page. The last stage is left standing on
        // purpose: a finished install should keep saying so rather than
        // blanking the moment its job leaves the queue.
        m_busy = false;
        m_busyId.clear();
    } else {
        const Job &j = m_jobs.at(k);
        m_busy = j.stage != QLatin1String("failed");
        m_busyId = j.id;
        m_stage = j.stage;
        m_percent = j.percent;
        m_detail = j.detail;
        m_bytes = j.bytes;
        m_total = j.total;
        m_count = j.count;
        m_countTotal = j.countTotal;
        m_error = j.error;
        m_errorDetail = j.errorDetail;
    }
    Q_EMIT progressChanged();
}

void Backend::install(const QString &id, const QString &source)
{
    Job j;
    j.id = id;
    j.source = source;
    j.kind = QStringLiteral("install");
    j.stage = QStringLiteral("queued");
    // The display name if the page knows one, so a notification can say
    // "Sober has been installed" rather than an application id.
    const QString shownId = m_app.value(QStringLiteral("id")).toString();
    j.name = (shownId == id)
        ? m_app.value(QStringLiteral("name")).toString()
        : QString();
    if (j.name.isEmpty()) {
        j.name = id;
    }
    j.args = QStringList{QStringLiteral("install"), id,
                         QStringLiteral("--source"), source};
    m_error.clear();
    m_errorDetail.clear();
    enqueue(j);
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
    Job j;
    j.id = id;
    j.source = source;
    j.kind = QStringLiteral("remove");
    j.stage = QStringLiteral("queued");
    j.deleteData = deleteData;
    const QString shownId = m_app.value(QStringLiteral("id")).toString();
    j.name = (shownId == id)
        ? m_app.value(QStringLiteral("name")).toString()
        : QString();
    if (j.name.isEmpty()) {
        j.name = id;
    }
    j.args = QStringList{QStringLiteral("remove"), id,
                         QStringLiteral("--source"), source};
    if (deleteData) {
        j.args << QStringLiteral("--delete-data");
    }
    m_error.clear();
    m_errorDetail.clear();
    enqueue(j);
}

void Backend::installLocalAppImage(const QString &path)
{
    // Through the queue like everything else. Left on the old single-flag path
    // it fought the queue for the same variable: any job event re-derived
    // m_busy from the job list, which knew nothing about this install, so the
    // flag flicked off under a transaction that was still running.
    Job j;
    j.id = QFileInfo(path).fileName();
    j.source = QStringLiteral("appimage");
    j.kind = QStringLiteral("install");
    j.stage = QStringLiteral("queued");
    j.name = j.id;
    j.args = QStringList{QStringLiteral("install"), QStringLiteral("--source"),
                         QStringLiteral("appimage"), QStringLiteral("--file"),
                         path};
    m_error.clear();
    m_errorDetail.clear();
    enqueue(j);
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

QString Backend::formatProgress(qint64 bytesIn, qint64 totalIn,
                                int countIn, int countTotalIn,
                                const QString &stageIn) const
{
    // Same words for one job as for the app on screen: the queue panel
    // and the app page were formatting the same numbers two ways, and the
    // two drifted the moment either was touched.
    const qint64 m_bytes = bytesIn;
    const qint64 m_total = totalIn;
    const int m_count = countIn;
    const int m_countTotal = countTotalIn;
    const QString m_stage = stageIn;
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

    // A known size with no position in it. The size is all that gets said,
    // and the ring spins rather than filling, which is what not knowing looks
    // like.
    //
    // Not restricted to the downloading stage, because flatpak reports one
    // line -- "Installing app/..." -- and then works in silence for the whole
    // transfer. Dropping the size the moment it says that would leave several
    // hundred megabytes of waiting with nothing on screen at all.
    if (m_total > 0) {
        // Pick the unit rather than always saying MB. A snap can be twenty
        // kilobytes, and "0.0 MB" is a worse answer than no answer.
        if (m_total >= 1000 * 1000 * 1000) {
            return tr("%1 GB").arg(m_total / (mb * 1000), 0, 'f', 1);
        }
        if (m_total >= 1000 * 1000) {
            return tr("%1 MB").arg(m_total / mb, 0, 'f', 1);
        }
        return tr("%1 kB").arg(m_total / 1000.0, 0, 'f', 1);
    }
    return QString();
}

QString Backend::downloadProgress() const
{
    return formatProgress(m_bytes, m_total, m_count, m_countTotal, m_stage);
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
    // Not m_busy: that is derived from the job queue now, so any transaction
    // event would have re-computed it mid-export and cleared a flag this had
    // set. Writing a list is not a transaction and does not belong in the
    // queue either -- it takes no lock and blocks nothing.
    m_stage = QStringLiteral("Writing the list");
    m_exporting = true;
    Q_EMIT progressChanged();

    auto *p = run({QStringLiteral("export-list"), QStringLiteral("--output"), file});
    connect(p, &QProcess::finished, this, [this, p, file] {
        const QJsonObject o = QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        p->deleteLater();
        m_exporting = false;
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
