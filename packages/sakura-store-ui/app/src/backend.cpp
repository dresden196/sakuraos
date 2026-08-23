#include "backend.h"

#include <QJsonArray>
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

Backend::Backend(QObject *parent) : QObject(parent) {}

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
    // No editorial list yet, so the front page is drawn from what people
    // actually install rather than from a hand-picked promo slot nobody has
    // curated. Honest, and it stays useful without a human maintaining it.
    auto *p = run({QStringLiteral("search"), QStringLiteral("editor"),
                   QStringLiteral("--source"), QStringLiteral("flatpak"),
                   QStringLiteral("--json")});
    connect(p, &QProcess::finished, this, [this, p] {
        const QJsonObject root =
            QJsonDocument::fromJson(p->readAllStandardOutput()).object();
        p->deleteLater();
        m_featured.clear();
        for (const QJsonValue &v : root[QStringLiteral("apps")].toArray()) {
            const QVariantMap m = toMap(v.toObject());
            if (m.value(QStringLiteral("rating_count")).toInt() > 15) {
                m_featured.append(m);
            }
            if (m_featured.size() >= 6) {
                break;
            }
        }
        Q_EMIT featuredChanged();
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

void Backend::remove(const QString &id, const QString &source)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_error.clear();
    m_stage = QStringLiteral("installing");
    m_detail = tr("removing");
    Q_EMIT progressChanged();

    auto *p = run({QStringLiteral("remove"), id, QStringLiteral("--source"), source});
    connect(p, &QProcess::finished, this, [this, p, id] {
        p->deleteLater();
        m_busy = false;
        m_stage = QStringLiteral("done");
        Q_EMIT progressChanged();
        openApp(id);
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
