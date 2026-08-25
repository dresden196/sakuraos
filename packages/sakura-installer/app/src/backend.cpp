#include "backend.h"

#include <QDir>
#include <QFile>
#include <QLocale>
#include <QSet>
#include <algorithm>

// Key labels come from the same library the session itself uses, so what the
// installer shows is what the machine will actually type.
#include <xkbcommon/xkbcommon.h>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTextStream>
#include <QTimeZone>
#include <QUrl>

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

namespace {
// Evdev keycodes for the three letter rows and the number row, in the order
// they sit on the board. xkb keycodes are evdev + 8.
const int ROW_NUMBER[] = {49, 10, 11, 12, 13, 14, 15, 16, 17, 18, 19, 20, 21};
const int ROW_TOP[]    = {24, 25, 26, 27, 28, 29, 30, 31, 32, 33, 34, 35};
const int ROW_HOME[]   = {38, 39, 40, 41, 42, 43, 44, 45, 46, 47, 48, 51};
const int ROW_BOTTOM[] = {52, 53, 54, 55, 56, 57, 58, 59, 60, 61};

QVariantList rowFor(xkb_state *state, const int *codes, int count)
{
    QVariantList row;
    for (int i = 0; i < count; ++i) {
        char buffer[32] = {0};
        const int len = xkb_state_key_get_utf8(state, codes[i], buffer,
                                               sizeof(buffer));
        QString label = len > 0 ? QString::fromUtf8(buffer, len) : QString();
        // Dead keys produce nothing here; showing an empty cap is honest but
        // useless, so fall back to the keysym's name.
        if (label.trimmed().isEmpty()) {
            const xkb_keysym_t sym = xkb_state_key_get_one_sym(state, codes[i]);
            char name[64] = {0};
            if (xkb_keysym_get_name(sym, name, sizeof(name)) > 0) {
                label = QString::fromLatin1(name);
                if (label.startsWith(QLatin1String("dead_"))) {
                    label = label.mid(5);
                }
            }
        }
        row.append(label);
    }
    return row;
}
} // namespace

QVariantList Backend::keyboardPreview(const QString &layout) const
{
    // Asked of xkbcommon rather than kept in a table here. A table would
    // cover the handful of layouts somebody thought of and quietly show the
    // wrong characters for the other two hundred -- on the screen whose whole
    // job is letting you check the layout before you commit to it.
    QVariantList rows;
    xkb_context *ctx = xkb_context_new(XKB_CONTEXT_NO_FLAGS);
    if (!ctx) {
        return rows;
    }

    xkb_rule_names names{};
    const QByteArray layoutBytes = layout.toUtf8();
    names.layout = layoutBytes.constData();

    xkb_keymap *keymap = xkb_keymap_new_from_names(ctx, &names,
                                                   XKB_KEYMAP_COMPILE_NO_FLAGS);
    xkb_state *state = keymap ? xkb_state_new(keymap) : nullptr;
    if (state) {
        rows.append(QVariant(rowFor(state, ROW_NUMBER, 13)));
        rows.append(QVariant(rowFor(state, ROW_TOP, 12)));
        rows.append(QVariant(rowFor(state, ROW_HOME, 12)));
        rows.append(QVariant(rowFor(state, ROW_BOTTOM, 10)));
        xkb_state_unref(state);
    }
    if (keymap) {
        xkb_keymap_unref(keymap);
    }
    xkb_context_unref(ctx);
    return rows;
}

QVariantList Backend::languages() const
{
    // glibc's own list of what it can generate, which is the same list
    // locale-gen works from -- so nothing can be offered here that the
    // installed system then cannot produce.
    QVariantList out;
    QFile f(QStringLiteral("/usr/share/i18n/SUPPORTED"));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return out;
    }

    QTextStream in(&f);
    QSet<QString> seen;
    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        // "en_GB.UTF-8 UTF-8" -- only UTF-8, because shipping a system in a
        // legacy encoding in 2026 creates problems nobody asked for.
        if (!line.endsWith(QLatin1String(" UTF-8"))) {
            continue;
        }
        const QString code = line.section(QLatin1Char(' '), 0, 0);
        if (!code.endsWith(QLatin1String(".UTF-8")) || seen.contains(code)) {
            continue;
        }
        seen.insert(code);

        const QLocale locale(code.left(code.indexOf(QLatin1Char('.'))));
        // The name in the language itself. Somebody who cannot read the
        // current interface language has to be able to find their own.
        QString native = locale.nativeLanguageName();
        if (native.isEmpty()) {
            continue;
        }
        native[0] = native[0].toUpper();
        const QString territory = locale.nativeTerritoryName();

        out.append(QVariantMap{
            {QStringLiteral("code"), code},
            {QStringLiteral("native"), territory.isEmpty()
                 ? native : QStringLiteral("%1 (%2)").arg(native, territory)},
            // English too, so the list is searchable by someone helping over
            // the phone.
            {QStringLiteral("english"), QStringLiteral("%1 (%2)").arg(
                 QLocale::languageToString(locale.language()),
                 QLocale::territoryToString(locale.territory()))},
        });
    }

    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("native")).toString().localeAwareCompare(
               b.toMap().value(QStringLiteral("native")).toString()) < 0;
    });
    return out;
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
    // Plasma ships a set of these and plasma-workspace is already pulled in,
    // so there is nothing to draw or package. /usr/share/sddm/faces is a
    // different thing entirely -- it holds per-user login pictures and on a
    // fresh system contains only root.face.icon.
    for (const QString &dir : {QStringLiteral("/usr/share/plasma/avatars"),
                               QStringLiteral("/usr/share/sddm/faces")}) {
        QDir d(dir);
        const auto files = d.entryList({QStringLiteral("*.png"), QStringLiteral("*.face.icon")},
                                       QDir::Files, QDir::Name);
        for (const QString &f : files) {
            // Several of these have spaces in the filename, so the URL has to
            // be built properly rather than by string concatenation.
            out.append(QUrl::fromLocalFile(d.absoluteFilePath(f)).toString());
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
        // The keyboard screen warns that getting this wrong locks you out at
        // the first login prompt. It has to reach the backend for that warning
        // to mean anything.
        QStringLiteral("--keymap"), answers[QStringLiteral("keyboard")].toString(),
        QStringLiteral("--locale"), answers[QStringLiteral("locale")].toString(),
        QStringLiteral("--feedback"),
        answers[QStringLiteral("crashReports")].toBool() ? QStringLiteral("on")
                                                         : QStringLiteral("off"),
        QStringLiteral("--theme"),
        answers[QStringLiteral("dark")].toBool() ? QStringLiteral("dark")
                                                 : QStringLiteral("light"),
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
