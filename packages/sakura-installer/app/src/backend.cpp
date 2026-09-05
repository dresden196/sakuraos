#include "backend.h"

#include <QDir>
#include <QFile>
#include <QLocale>
#include <QDateTime>
#include <QTimer>
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

QVariantList Backend::timezoneChoices() const
{
    // The raw identifiers are what the system wants and the wrong thing to
    // search: "America/New_York" does not contain "new york", so typing the
    // name of the city found nothing. Each entry carries a searchable form
    // with the region stripped and the underscores gone, and the city is
    // shown first because that is what people know their zone by.
    QVariantList out;
    for (const QString &id : timezones()) {
        const int slash = id.lastIndexOf(QLatin1Char('/'));
        QString city = (slash < 0 ? id : id.mid(slash + 1));
        city.replace(QLatin1Char('_'), QLatin1Char(' '));
        QString region = slash < 0 ? QString() : id.left(id.indexOf(QLatin1Char('/')));
        region.replace(QLatin1Char('_'), QLatin1Char(' '));

        out.append(QVariantMap{
            {QStringLiteral("id"), id},
            {QStringLiteral("city"), city},
            {QStringLiteral("region"), region},
            // Everything a person might type, lowercased once here rather
            // than on every keystroke for four hundred entries.
            {QStringLiteral("search"),
             QStringLiteral("%1 %2 %3").arg(city, region, id).toLower()},
        });
    }
    return out;
}

QVariantMap Backend::diskLayout(const QString &device) const
{
    QVariantMap out{
        {QStringLiteral("freeMiB"), 0},
        {QStringLiteral("hasEsp"), false},
        {QStringLiteral("systems"), QStringList{}},
    };
    if (device.isEmpty()) {
        return out;
    }

    // An EFI system partition already here means something else boots from
    // this disk, and that its bootloader must not be written over.
    const QString parts = runCapture(QStringLiteral("lsblk"),
        {QStringLiteral("-lnpo"), QStringLiteral("NAME,PARTTYPE,PARTLABEL,FSTYPE"),
         device});
    QStringList systems;
    for (const QString &line : parts.split(QLatin1Char('\n'))) {
        const QStringList f = line.simplified().split(QLatin1Char(' '));
        if (f.size() < 2) {
            continue;
        }
        if (f.at(1).compare(QLatin1String("c12a7328-f81f-11d2-ba4b-00a0c93ec93b"),
                            Qt::CaseInsensitive) == 0) {
            out[QStringLiteral("hasEsp")] = true;
        }
        // Named by filesystem rather than by probing: ntfs almost always
        // means Windows, and this only has to be good enough to tell somebody
        // what they are about to keep or erase.
        const QString fs = f.last();
        if (fs == QLatin1String("ntfs") && !systems.contains(QStringLiteral("Windows"))) {
            systems << QStringLiteral("Windows");
        } else if ((fs == QLatin1String("ext4") || fs == QLatin1String("btrfs")
                    || fs == QLatin1String("xfs"))
                   && !systems.contains(QStringLiteral("another Linux system"))) {
            systems << QStringLiteral("another Linux system");
        }
    }
    out[QStringLiteral("systems")] = systems;

    // The largest run of unallocated space. parted reports free regions as
    // rows of their own in machine-readable mode.
    const QString free = runCapture(QStringLiteral("parted"),
        {QStringLiteral("-ms"), device, QStringLiteral("unit"),
         QStringLiteral("MiB"), QStringLiteral("print"), QStringLiteral("free")});
    double best = 0;
    for (const QString &line : free.split(QLatin1Char('\n'))) {
        const QStringList f = line.split(QLatin1Char(':'));
        if (f.size() < 5 || !f.at(4).startsWith(QLatin1String("free"))) {
            continue;
        }
        const double size = f.at(3).chopped(3).toDouble();   // strip "MiB"
        if (size > best) {
            best = size;
        }
    }
    out[QStringLiteral("freeMiB")] = static_cast<int>(best);
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

int Backend::utcOffset(const QString &timezone) const
{
    // Asked of QTimeZone rather than worked out from the name, because the
    // answer depends on the date: half these zones are on summer time today
    // and will not be in November, and a clock that is an hour out is worse
    // than no clock -- it is the one thing on this screen somebody can check
    // against the watch on their wrist.
    const QTimeZone zone(timezone.toUtf8());
    if (!zone.isValid()) {
        return 0;
    }
    return zone.offsetFromUtc(QDateTime::currentDateTimeUtc());
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

// ---- network ------------------------------------------------------------
//
// nmcli's terse output is the interface here: -t gives colon-separated
// fields with no header and no column padding, which is the only form of
// its output that is safe to parse. Anything human-readable from nmcli
// changes with the terminal width.

QVariantMap Backend::networkState() const
{
    QVariantMap out;
    out.insert(QStringLiteral("connected"), false);

    const QString devices = runCapture(QStringLiteral("nmcli"),
        {QStringLiteral("-t"), QStringLiteral("-f"),
         QStringLiteral("DEVICE,TYPE,STATE,CONNECTION"), QStringLiteral("device")});

    for (const QString &line : devices.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        const QStringList f = line.split(QLatin1Char(':'));
        if (f.size() < 4 || f[1] == QLatin1String("loopback")) {
            continue;
        }
        if (f[2] != QLatin1String("connected")) {
            continue;
        }
        out.insert(QStringLiteral("connected"), true);
        out.insert(QStringLiteral("device"), f[0]);
        out.insert(QStringLiteral("type"), f[1]);
        out.insert(QStringLiteral("name"), f[3]);

        // The address is what tells somebody it actually worked. A device can
        // read "connected" with no lease and nothing reachable behind it.
        const QString addrs = runCapture(QStringLiteral("nmcli"),
            {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("IP4.ADDRESS"),
             QStringLiteral("device"), QStringLiteral("show"), f[0]});
        const QStringList a = addrs.split(QLatin1Char('\n'), Qt::SkipEmptyParts);
        if (!a.isEmpty()) {
            out.insert(QStringLiteral("address"),
                       a.first().section(QLatin1Char(':'), 1).trimmed());
        }
        break;
    }
    return out;
}

bool Backend::hasWifiHardware() const
{
    const QString out = runCapture(QStringLiteral("nmcli"),
        {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("TYPE"),
         QStringLiteral("device")});
    for (const QString &line : out.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        if (line.trimmed() == QLatin1String("wifi")) {
            return true;
        }
    }
    return false;
}

void Backend::rescanWifi()
{
    QProcess::execute(QStringLiteral("nmcli"),
        {QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("rescan")});
}

QVariantList Backend::wifiNetworks() const
{
    QVariantList out;
    const QString listing = runCapture(QStringLiteral("nmcli"),
        {QStringLiteral("-t"), QStringLiteral("-f"),
         QStringLiteral("IN-USE,SSID,SIGNAL,SECURITY"),
         QStringLiteral("device"), QStringLiteral("wifi"), QStringLiteral("list")});

    QSet<QString> seen;
    for (const QString &line : listing.split(QLatin1Char('\n'), Qt::SkipEmptyParts)) {
        // An SSID may contain a colon, which nmcli escapes as "\:". Splitting
        // naively would cut a network's name in half and mangle the fields
        // after it, so the escape is honoured.
        QStringList f;
        QString cur;
        for (int i = 0; i < line.size(); ++i) {
            if (line[i] == QLatin1Char('\\') && i + 1 < line.size()) {
                cur.append(line[++i]);
            } else if (line[i] == QLatin1Char(':')) {
                f.append(cur);
                cur.clear();
            } else {
                cur.append(line[i]);
            }
        }
        f.append(cur);
        if (f.size() < 4 || f[1].isEmpty()) {
            continue;
        }
        // Strongest entry wins: the same network seen through two access
        // points is one network to the person choosing it.
        if (seen.contains(f[1])) {
            continue;
        }
        seen.insert(f[1]);

        QVariantMap n;
        n.insert(QStringLiteral("active"), f[0].trimmed() == QLatin1String("*"));
        n.insert(QStringLiteral("ssid"), f[1]);
        n.insert(QStringLiteral("signal"), f[2].toInt());
        n.insert(QStringLiteral("secure"), !f[3].trimmed().isEmpty());
        out.append(n);
    }

    std::sort(out.begin(), out.end(), [](const QVariant &a, const QVariant &b) {
        return a.toMap().value(QStringLiteral("signal")).toInt()
             > b.toMap().value(QStringLiteral("signal")).toInt();
    });
    return out;
}

QString Backend::connectWifi(const QString &ssid, const QString &password)
{
    QStringList args{QStringLiteral("device"), QStringLiteral("wifi"),
                     QStringLiteral("connect"), ssid};
    if (!password.isEmpty()) {
        args << QStringLiteral("password") << password;
    }
    QProcess p;
    p.setProcessChannelMode(QProcess::MergedChannels);
    p.start(QStringLiteral("nmcli"), args);
    // Associating, authenticating and getting a lease is not a two second
    // job on a slow access point.
    p.waitForFinished(45000);
    if (p.exitCode() == 0) {
        return QString();
    }
    const QString err = QString::fromUtf8(p.readAll()).trimmed();
    // nmcli's own sentence, not a guess at what went wrong: it distinguishes
    // a wrong passphrase from a network that is not there, and the person
    // needs to know which.
    return err.isEmpty() ? tr("Could not connect to %1.").arg(ssid)
                         : err.section(QLatin1Char('\n'), -1);
}

QString Backend::applyStaticAddress(const QString &device, const QString &address,
                                    const QString &gateway, const QString &dns)
{
    // The connection currently on the device, not a new profile: adding one
    // leaves two claiming the same interface and whichever comes up second
    // silently loses.
    const QString name = runCapture(QStringLiteral("nmcli"),
        {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("GENERAL.CONNECTION"),
         QStringLiteral("device"), QStringLiteral("show"), device})
        .section(QLatin1Char(':'), 1).trimmed();
    if (name.isEmpty() || name == QLatin1String("--")) {
        return tr("That connection is not set up yet. Connect first, then set an address.");
    }

    QStringList args{QStringLiteral("connection"), QStringLiteral("modify"), name,
                     QStringLiteral("ipv4.method"), QStringLiteral("manual"),
                     QStringLiteral("ipv4.addresses"), address};
    if (!gateway.isEmpty()) {
        args << QStringLiteral("ipv4.gateway") << gateway;
    }
    if (!dns.isEmpty()) {
        args << QStringLiteral("ipv4.dns") << dns;
    }

    QProcess p;
    p.setProcessChannelMode(QProcess::MergedChannels);
    p.start(QStringLiteral("nmcli"), args);
    p.waitForFinished(15000);
    if (p.exitCode() != 0) {
        const QString err = QString::fromUtf8(p.readAll()).trimmed();
        return err.isEmpty() ? tr("That address was not accepted.")
                             : err.section(QLatin1Char('\n'), -1);
    }

    QProcess::execute(QStringLiteral("nmcli"),
        {QStringLiteral("connection"), QStringLiteral("up"), name});
    return QString();
}

QString Backend::useAutomaticAddress(const QString &device)
{
    const QString name = runCapture(QStringLiteral("nmcli"),
        {QStringLiteral("-t"), QStringLiteral("-f"), QStringLiteral("GENERAL.CONNECTION"),
         QStringLiteral("device"), QStringLiteral("show"), device})
        .section(QLatin1Char(':'), 1).trimmed();
    if (name.isEmpty() || name == QLatin1String("--")) {
        return tr("That connection is not set up yet.");
    }
    QProcess::execute(QStringLiteral("nmcli"),
        {QStringLiteral("connection"), QStringLiteral("modify"), name,
         QStringLiteral("ipv4.method"), QStringLiteral("auto"),
         QStringLiteral("ipv4.addresses"), QString(),
         QStringLiteral("ipv4.gateway"), QString(),
         QStringLiteral("ipv4.dns"), QString()});
    QProcess::execute(QStringLiteral("nmcli"),
        {QStringLiteral("connection"), QStringLiteral("up"), name});
    return QString();
}

QStringList Backend::avatars() const
{
    QStringList out;
    // GNOME's set, shipped by sakura-theme. Photographs of objects rather
    // than drawings of people: a cartoon face is a picture of somebody who
    // is not you, and the illustrated sets desktops ship read as a child's
    // avatar picker. Plasma's are deliberately not offered alongside them --
    // mixing two art styles in one ring looks like neither was chosen.
    //
    // /usr/share/sddm/faces is deliberately not read. It is a different thing
    // entirely -- per-user login pictures -- and on a fresh system it holds
    // exactly one file, root.face.icon, which is the generic outline of a
    // person that desktops use when they know nothing about you. It appeared
    // at the end of the ring as an anonymous grey figure among photographs,
    // looking like a bug because it was one.
    //
    // There is already a right answer for "no picture chosen": the initials
    // tile, which is the first thing in the ring and is selected by default.
    for (const QString &dir : {QStringLiteral("/usr/share/sakura/avatars")}) {
        QDir d(dir);
        const auto files = d.entryList({QStringLiteral("*.jpg"), QStringLiteral("*.png"),
                                        QStringLiteral("*.face.icon")},
                                       QDir::Files, QDir::Name);
        for (const QString &f : files) {
            // Several of these have spaces in the filename, so the URL has to
            // be built properly rather than by string concatenation.
            out.append(QUrl::fromLocalFile(d.absoluteFilePath(f)).toString());
        }
    }
    return out;
}

void Backend::reboot()
{
    // No pkexec. Restarting is one of the few things logind lets an active
    // local session do on its own authority, so asking for a password here
    // would be a prompt with nothing behind it.
    //
    // Detached, because this process is about to be killed by the reboot it
    // just asked for and a synchronous wait would be waiting for its own
    // death.
    QProcess::startDetached(QStringLiteral("systemctl"),
                            {QStringLiteral("reboot")});
}

void Backend::appendLog(const QString &text)
{
    m_log += text;

    // Coalesced rather than emitted per chunk. pacman draws progress bars with
    // carriage returns, so the installer produces many chunks a second, and
    // signalling each one made the interface spend the whole install rebuilding
    // a text document instead of drawing. Four updates a second is faster than
    // anyone reads and leaves the event loop time to do its other work.
    if (!m_logFlush) {
        m_logFlush = new QTimer(this);
        m_logFlush->setSingleShot(true);
        m_logFlush->setInterval(250);
        connect(m_logFlush, &QTimer::timeout, this, [this] { Q_EMIT logChanged(); });
    }
    if (!m_logFlush->isActive()) {
        m_logFlush->start();
    }
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
        QStringLiteral("--mode"), answers[QStringLiteral("diskMode")].toString(),
        QStringLiteral("--encrypt"),
        answers[QStringLiteral("encrypt")].toBool() ? QStringLiteral("on")
                                                    : QStringLiteral("off"),
        QStringLiteral("--feedback"),
        answers[QStringLiteral("crashReports")].toBool() ? QStringLiteral("on")
                                                         : QStringLiteral("off"),
        QStringLiteral("--theme"),
        answers[QStringLiteral("dark")].toBool() ? QStringLiteral("dark")
                                                 : QStringLiteral("light"),
        QStringLiteral("--yes"),
    };

    const bool encrypting = answers[QStringLiteral("encrypt")].toBool();
    if (encrypting) {
        args << QStringLiteral("--encryption-password-stdin");
    }

    const QString browser = answers[QStringLiteral("browser")].toString();
    if (!browser.isEmpty() && browser != QLatin1String("none")) {
        args << QStringLiteral("--extra-packages") << browser;
        // Also by name, so the installer can pin it to the task bar. Passing
        // it as an extra package alone says what to install and nothing about
        // what it is.
        args << QStringLiteral("--browser") << browser;
    }

    // Everything below was collected by the installer and then dropped on the
    // floor. The accent colour was the visible one -- people chose a colour on
    // the appearance screen and the installed desktop came up pink anyway --
    // but the full name, the profile picture, the clock format and all four
    // update-schedule answers went the same way.
    const QString fullname = answers[QStringLiteral("fullname")].toString();
    if (!fullname.isEmpty()) {
        args << QStringLiteral("--fullname") << fullname;
    }
    const QString avatar = answers[QStringLiteral("avatar")].toString();
    if (!avatar.isEmpty()) {
        args << QStringLiteral("--avatar") << avatar;
    }
    const QString accent = answers[QStringLiteral("accent")].toString();
    if (!accent.isEmpty()) {
        args << QStringLiteral("--accent") << accent;
    }
    args << QStringLiteral("--clock")
         << (answers[QStringLiteral("hour24")].toBool() ? QStringLiteral("24")
                                                        : QStringLiteral("12"));
    args << QStringLiteral("--auto-update")
         << (answers[QStringLiteral("autoUpdate")].toBool() ? QStringLiteral("on")
                                                            : QStringLiteral("off"));
    args << QStringLiteral("--canary-only")
         << (answers[QStringLiteral("canaryOnly")].toBool() ? QStringLiteral("on")
                                                            : QStringLiteral("off"));
    args << QStringLiteral("--ac-only")
         << (answers[QStringLiteral("acOnly")].toBool() ? QStringLiteral("on")
                                                        : QStringLiteral("off"));
    const QString updateTime = answers[QStringLiteral("updateTime")].toString();
    if (!updateTime.isEmpty()) {
        args << QStringLiteral("--update-time") << updateTime;
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

    if (encrypting) {
        // Written down the pipe rather than passed as an argument, and the
        // channel closed straight after so the installer sees end of input.
        // A passphrase in argv is readable from /proc by every process on the
        // machine, and this is the one secret here that outlives the install.
        m_proc->write(answers[QStringLiteral("encryptPassword")]
                          .toString().toUtf8() + '\n');
        m_proc->closeWriteChannel();
    }
}
