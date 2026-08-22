#include "backend.h"

#include <QDir>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTextStream>
#include <QTimeZone>

namespace {

QString runCapture(const QString &program, const QStringList &args)
{
    QProcess p;
    p.start(program, args);
    p.waitForFinished(10000);
    return QString::fromUtf8(p.readAllStandardOutput());
}

} // namespace

Backend::Backend(QObject *parent)
    : QObject(parent)
{
}

QVariantList Backend::disks() const
{
    QVariantList out;
    const QString json = runCapture(QStringLiteral("lsblk"),
        {QStringLiteral("-J"), QStringLiteral("-b"), QStringLiteral("-d"),
         QStringLiteral("-o"), QStringLiteral("NAME,SIZE,MODEL,TYPE,RM,RO")});

    const QJsonArray devices =
        QJsonDocument::fromJson(json.toUtf8()).object()[QStringLiteral("blockdevices")].toArray();

    for (const QJsonValue &value : devices) {
        const QJsonObject dev = value.toObject();
        if (dev[QStringLiteral("type")].toString() != QLatin1String("disk")) {
            continue;
        }
        if (dev[QStringLiteral("ro")].toBool()) {
            continue;
        }

        const qint64 bytes = dev[QStringLiteral("size")].toVariant().toLongLong();
        // Anything under 8 GB cannot hold the system and is almost certainly
        // the USB stick the installer is running from. Offering it invites
        // someone to erase the media mid-install.
        if (bytes < 8LL * 1024 * 1024 * 1024) {
            continue;
        }

        QVariantMap entry;
        const QString name = dev[QStringLiteral("name")].toString();
        entry[QStringLiteral("device")] = QString(QStringLiteral("/dev/") + name);
        entry[QStringLiteral("model")] = dev[QStringLiteral("model")].toString().trimmed();
        entry[QStringLiteral("removable")] = dev[QStringLiteral("rm")].toBool();
        entry[QStringLiteral("sizeText")] =
            QStringLiteral("%1 GB").arg(bytes / 1000 / 1000 / 1000);
        out.append(entry);
    }
    return out;
}

QStringList Backend::timezones() const
{
    // UTC is a legitimate answer and is what a machine with no configured
    // zone reports, so it has to be in the list -- otherwise the guessed
    // value cannot be selected and the picker opens blank.
    QStringList out{QStringLiteral("UTC")};
    const auto ids = QTimeZone::availableTimeZoneIds();
    out.reserve(ids.size() + 1);
    for (const QByteArray &id : ids) {
        const QString s = QString::fromUtf8(id);
        // Region/City only: the aliases and legacy POSIX names are noise in a
        // picker someone has to scan.
        if (s.contains(QLatin1Char('/')) && !s.startsWith(QLatin1String("Etc/"))) {
            out.append(s);
        }
    }
    out.sort();
    return out;
}

QString Backend::guessTimezone() const
{
    const QString out = runCapture(QStringLiteral("timedatectl"),
                                   {QStringLiteral("show"), QStringLiteral("-p"),
                                    QStringLiteral("Timezone"), QStringLiteral("--value")}).trimmed();
    return out.isEmpty() ? QStringLiteral("UTC") : out;
}

QVariantList Backend::keyboardLayouts() const
{
    QVariantList out;
    QFile f(QStringLiteral("/usr/share/X11/xkb/rules/base.lst"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return out;
    }

    QTextStream in(&f);
    bool inLayouts = false;
    static const QRegularExpression entry(QStringLiteral("^\\s*(\\S+)\\s+(.+?)\\s*$"));

    while (!in.atEnd()) {
        const QString line = in.readLine();
        if (line.startsWith(QLatin1String("! layout"))) {
            inLayouts = true;
            continue;
        }
        if (line.startsWith(QLatin1Char('!'))) {
            if (inLayouts) {
                break;
            }
            continue;
        }
        if (!inLayouts || line.trimmed().isEmpty()) {
            continue;
        }
        const auto m = entry.match(line);
        if (!m.hasMatch()) {
            continue;
        }
        QVariantMap item;
        item[QStringLiteral("code")] = m.captured(1);
        item[QStringLiteral("name")] = m.captured(2);
        out.append(item);
    }
    return out;
}

QStringList Backend::avatars() const
{
    QStringList out;
    for (const QString &dir : {QStringLiteral("/usr/share/sddm/faces"),
                               QStringLiteral("/usr/share/pixmaps/faces")}) {
        QDir d(dir);
        const auto files = d.entryList({QStringLiteral("*.png"), QStringLiteral("*.face.icon")},
                                       QDir::Files, QDir::Name);
        for (const QString &f : files) {
            out.append(QString(QStringLiteral("file://") + d.absoluteFilePath(f)));
        }
    }
    return out;
}

void Backend::appendLog(const QString &text)
{
    m_log += text;
    Q_EMIT logChanged();
}

void Backend::install(const QVariantMap &answers)
{
    if (m_running) {
        return;
    }

    QStringList args{
        QStringLiteral("--disk"), answers[QStringLiteral("disk")].toString(),
        QStringLiteral("--user"), answers[QStringLiteral("username")].toString(),
        QStringLiteral("--password"), answers[QStringLiteral("password")].toString(),
        QStringLiteral("--hostname"), answers[QStringLiteral("hostname")].toString(),
        QStringLiteral("--timezone"), answers[QStringLiteral("timezone")].toString(),
        QStringLiteral("--yes"),
    };

    const QString browser = answers[QStringLiteral("browser")].toString();
    if (!browser.isEmpty() && browser != QLatin1String("none")) {
        args << QStringLiteral("--extra-packages") << browser;
    }

    m_running = true;
    m_percent = 0;
    m_step = QStringLiteral("Preparing");
    Q_EMIT runningChanged();
    Q_EMIT progressChanged();

    m_proc = new QProcess(this);
    m_proc->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_proc, &QProcess::readyRead, this, [this] {
        const QString chunk = QString::fromUtf8(m_proc->readAll());
        appendLog(chunk);

        // sakura-install announces each phase as "[sakura-install] == Name ==".
        // Parsing its own output keeps the two in step without inventing a
        // second progress protocol that could disagree with reality.
        static const QRegularExpression step(
            QStringLiteral("\\[sakura-install\\] == (.+?) =="));
        auto it = step.globalMatch(chunk);
        while (it.hasNext()) {
            m_step = it.next().captured(1);
            m_percent = qMin(95, m_percent + 12);
            Q_EMIT progressChanged();
        }
    });

    connect(m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus status) {
        m_running = false;
        const bool ok = (status == QProcess::NormalExit && code == 0);
        m_percent = ok ? 100 : m_percent;
        m_step = ok ? QStringLiteral("Finished") : QStringLiteral("Failed");
        Q_EMIT runningChanged();
        Q_EMIT progressChanged();
        Q_EMIT finished(ok);
    });

    // pkexec rather than running the whole UI as root: the installer draws a
    // window, and a window is a lot of attack surface to hand uid 0.
    m_proc->start(QStringLiteral("pkexec"),
                  QStringList{QStringLiteral("/usr/bin/sakura-install")} + args);
}
