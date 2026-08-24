#include "backend.h"

#include <QJsonArray>
#include <algorithm>
#include <QJsonDocument>
#include <QJsonObject>
#include <QVariant>

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

void Backend::install(const QString &id, const QString &source)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_error.clear();
    m_percent = 0;
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
            } else {
                m_stage = stage;
                if (o.contains(QStringLiteral("percent"))) {
                    m_percent = o[QStringLiteral("percent")].toInt();
                }
                const QString d = o[QStringLiteral("detail")].toString();
                if (!d.isEmpty()) {
                    m_detail = d;
                }
            }
            Q_EMIT progressChanged();
        }
    });
    connect(p, &QProcess::finished, this, [this, p, id] {
        p->deleteLater();
        m_busy = false;
        if (m_error.isEmpty()) {
            m_stage = QStringLiteral("done");
            m_percent = 100;
        }
        Q_EMIT progressChanged();
        openApp(id);
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
        Q_EMIT removed(id, source);
    });
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
