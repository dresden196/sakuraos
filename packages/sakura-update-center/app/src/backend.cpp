#include "backend.h"

#include <QDateTime>
#include <QLocale>
#include <QFile>
#include <QJsonArray>
#include <QJsonDocument>
#include <QJsonObject>
#include <QRegularExpression>
#include <QTextStream>

namespace {
constexpr auto ENGINE = "/usr/bin/sakura-update";
constexpr auto CONFIG = "/etc/sakura/sakura.conf";
constexpr auto WRITER = "/usr/lib/sakura/settings/sakura-settings-write";

QString capture(const QString &prog, const QStringList &args, int ms = 60000)
{
    QProcess p;
    p.start(prog, args);
    p.waitForFinished(ms);
    return QString::fromUtf8(p.readAllStandardOutput());
}
} // namespace

Backend::Backend(QObject *parent) : QObject(parent) {}

bool Backend::uses24Hour() const
{
    // Qt spells a 12-hour format with AP or ap in the pattern. Asking the
    // locale is the only way to stay in step with the clock chosen at install
    // time, which is stored as LC_TIME rather than as a boolean anybody could
    // read directly.
    const QString fmt = QLocale().timeFormat(QLocale::ShortFormat);
    return !fmt.contains(QLatin1String("AP"), Qt::CaseInsensitive);
}

void Backend::setBusy(bool b)
{
    m_busy = b;
    Q_EMIT stateChanged();
}

void Backend::check()
{
    if (m_busy) {
        return;
    }
    setBusy(true);
    m_error.clear();

    auto *p = new QProcess(this);
    connect(p, &QProcess::finished, this, [this, p](int code, QProcess::ExitStatus) {
        const QByteArray out = p->readAllStandardOutput();
        p->deleteLater();

        const QJsonObject root = QJsonDocument::fromJson(out).object();
        if (code != 0 && root.isEmpty()) {
            m_error = tr("Could not check for updates. Check your connection.");
            setBusy(false);
            return;
        }

        m_updates.clear();
        m_holds.clear();
        m_restart = root[QStringLiteral("restart_required")].toBool();

        for (const QJsonValue &v : root[QStringLiteral("updates")].toArray()) {
            const QJsonObject o = v.toObject();
            QStringList needed;
            for (const QJsonValue &n : o[QStringLiteral("needed_by")].toArray()) {
                needed << n.toString();
            }
            m_updates.append(QVariantMap{
                {QStringLiteral("name"), o[QStringLiteral("name")].toString()},
                {QStringLiteral("old"), o[QStringLiteral("old")].toString()},
                {QStringLiteral("new"), o[QStringLiteral("new")].toString()},
                {QStringLiteral("summary"), o[QStringLiteral("summary")].toString()},
                {QStringLiteral("neededBy"), needed.join(QStringLiteral(", "))},
                {QStringLiteral("restart"), o[QStringLiteral("restart")].toBool()},
                {QStringLiteral("held"), o[QStringLiteral("held")].toString()},
            });
        }
        for (const QJsonValue &v : root[QStringLiteral("holds")].toArray()) {
            const QJsonObject o = v.toObject();
            m_holds.append(QVariantMap{
                {QStringLiteral("title"), o[QStringLiteral("title")].toString()},
                {QStringLiteral("reason"), o[QStringLiteral("reason")].toString()},
            });
        }

        // Written the way this machine writes times. It was hardcoded to
        // HH:mm, so a machine set up with a 12-hour clock -- which the
        // installer asks about explicitly -- was still shown 14:30 here.
        m_lastChecked = QLocale().toString(QDateTime::currentDateTime(),
                                           QStringLiteral("d MMM, ")
                                           + QLocale().timeFormat(QLocale::ShortFormat));
        setBusy(false);
        Q_EMIT dataChanged();
    });
    p->start(QString::fromLatin1(ENGINE), {QStringLiteral("check"), QStringLiteral("--json")});
}

void Backend::apply()
{
    if (m_applying) {
        return;
    }
    m_applying = true;
    m_log.clear();
    m_error.clear();
    Q_EMIT stateChanged();
    Q_EMIT logChanged();

    m_proc = new QProcess(this);
    m_proc->setProcessChannelMode(QProcess::MergedChannels);

    connect(m_proc, &QProcess::readyRead, this, [this] {
        m_log += QString::fromUtf8(m_proc->readAll());
        Q_EMIT logChanged();
    });
    connect(m_proc, &QProcess::finished, this, [this](int code, QProcess::ExitStatus) {
        m_applying = false;
        const bool ok = code == 0;
        if (!ok) {
            // 126 and 127 are pkexec's own codes for dismissed and not
            // authorised. "Failed" would be wrong and alarming for what is
            // usually someone deciding not to right now.
            m_error = (code == 126 || code == 127)
                ? tr("Updates were not installed: authentication was cancelled.")
                : tr("Updates could not be installed. The log below has the detail.");
        }
        Q_EMIT stateChanged();
        Q_EMIT applyFinished(ok);
        check();
    });

    // The engine elevates itself through polkit, so this process never needs
    // to be root and the window never runs as uid 0.
    m_proc->start(QString::fromLatin1(ENGINE), {QStringLiteral("apply")});
}

namespace {
// Both actions go through the same privileged helper and differ only in the
// verb, so the plumbing is written once.
const char SNAPSHOT_HELPER[] =
    "/usr/lib/sakura/snapshot-boot/sakura-snapshot-manage";
}

void Backend::runSnapshotHelper(const QString &verb, const QString &argument)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_error.clear();
    Q_EMIT stateChanged();

    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    connect(p, &QProcess::finished, this,
            [this, p](int code, QProcess::ExitStatus status) {
        const QString out = QString::fromUtf8(p->readAll()).trimmed();
        p->deleteLater();
        m_busy = false;
        if (code != 0 || status != QProcess::NormalExit) {
            m_error = (code == 126 || code == 127)
                ? tr("Authentication was cancelled; nothing has changed.")
                : (out.isEmpty() ? tr("That did not work.")
                                 : out.section(QLatin1Char('\n'), -1));
        }
        // Reload either way: on success the list has changed, and on failure
        // it is worth showing what is actually there rather than what the
        // screen happened to be showing before.
        loadHistory();
        Q_EMIT stateChanged();
    });
    p->start(QStringLiteral("pkexec"),
             {QString::fromLatin1(SNAPSHOT_HELPER), verb, argument});
}

void Backend::createRestorePoint(const QString &description)
{
    runSnapshotHelper(QStringLiteral("create"),
                      description.trimmed().isEmpty()
                          ? tr("Saved by you") : description.trimmed());
}

void Backend::deleteRestorePoint(const QString &number)
{
    runSnapshotHelper(QStringLiteral("delete"), number);
}

void Backend::rollback(const QString &number)
{
    if (m_busy) {
        return;
    }
    m_busy = true;
    m_error.clear();
    Q_EMIT stateChanged();

    // Two steps, deliberately separate. The helper only records which restore
    // point was chosen; the rollback itself happens in the recovery
    // environment on the next boot, because a root subvolume cannot be
    // replaced while it is mounted.
    auto *p = new QProcess(this);
    p->setProcessChannelMode(QProcess::MergedChannels);
    connect(p, &QProcess::finished, this,
            [this, p](int code, QProcess::ExitStatus status) {
        const QString out = QString::fromUtf8(p->readAll()).trimmed();
        p->deleteLater();
        m_busy = false;
        if (code != 0 || status != QProcess::NormalExit) {
            // 126 and 127 are pkexec's own: dismissed, and not authorised.
            m_error = (code == 126 || code == 127)
                ? tr("Authentication was cancelled; nothing has changed.")
                : (out.isEmpty()
                   ? tr("The restore point could not be scheduled.")
                   : out.section(QLatin1Char('\n'), -1));
            Q_EMIT stateChanged();
            return;
        }
        Q_EMIT stateChanged();
        // Only reboot once the request is safely written. Rebooting first and
        // hoping would leave a machine that restarted for no reason.
        QProcess::startDetached(QStringLiteral("systemctl"),
                                {QStringLiteral("reboot")});
    });
    p->start(QStringLiteral("pkexec"),
             {QStringLiteral("/usr/lib/sakura/snapshot-boot/sakura-schedule-rollback"),
              number});
}

void Backend::loadHistory()
{
    m_history.clear();

    // Restore points are the history. snap-pac writes one before every pacman
    // transaction, so the snapshot list already is the record of what changed
    // and when -- there is no second log to keep in step.
    // Through D-Bus, deliberately. --no-dbus makes snapper read
    // /etc/snapper/configs/root directly, which is root-only, so an
    // unprivileged process got nothing back and the tab reported "no restore
    // points yet" on a machine full of them -- the safety net this project is
    // built around, apparently absent. The D-Bus path is the one that honours
    // the ALLOW_GROUPS=wheel the installer sets, and listing snapshots is not
    // a privileged act; taking or restoring one still is.
    // --csvout, not the table.
    //
    // The table was parsed with a regex expecting an ASCII pipe between the
    // columns. snapper draws it with U+2502, the box-drawing vertical, so the
    // regex matched nothing and the tab said "No restore points yet." on a
    // machine that had them -- the same wrong answer this code was already
    // fixed for once, arrived at a second way.
    //
    // A decorated table is a display format and is entitled to change. csvout
    // is the one snapper offers for reading, so nothing here depends on how it
    // chooses to draw a line.
    const QString out = capture(QStringLiteral("snapper"),
        {QStringLiteral("--csvout"), QStringLiteral("-c"), QStringLiteral("root"),
         QStringLiteral("list"), QStringLiteral("--columns"),
         QStringLiteral("number,date,description")});

    const auto lines = out.split(QLatin1Char('\n'));
    for (const QString &line : lines) {
        const QString trimmed = line.trimmed();
        if (trimmed.isEmpty() || trimmed.startsWith(QLatin1String("number"))) {
            continue;                       // header
        }
        // Split on the first two commas only: a description may contain one,
        // and it is the last field.
        const int c1 = trimmed.indexOf(QLatin1Char(','));
        if (c1 < 0) continue;
        const int c2 = trimmed.indexOf(QLatin1Char(','), c1 + 1);
        if (c2 < 0) continue;
        const QString number = trimmed.left(c1).trimmed();
        const QString date = trimmed.mid(c1 + 1, c2 - c1 - 1).trimmed();
        QString desc = trimmed.mid(c2 + 1).trimmed();
        if (desc.startsWith(QLatin1Char('"')) && desc.endsWith(QLatin1Char('"'))) {
            desc = desc.mid(1, desc.size() - 2);
        }
        // 0 is the live system, not a point to go back to.
        if (number.isEmpty() || number == QLatin1String("0")) {
            continue;
        }
        m_history.append(QVariantMap{
            {QStringLiteral("number"), number},
            {QStringLiteral("date"), date},
            {QStringLiteral("description"), desc},
        });
    }
    std::reverse(m_history.begin(), m_history.end());
    Q_EMIT dataChanged();
}

QVariantMap Backend::schedule() const
{
    QVariantMap out{
        {QStringLiteral("autoApply"), true},
        {QStringLiteral("canary"), true},
        {QStringLiteral("acOnly"), true},
        {QStringLiteral("window"), QStringLiteral("03:00")},
    };

    QFile f(QString::fromLatin1(CONFIG));
    if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
        return out;
    }
    QTextStream in(&f);
    QString section;
    while (!in.atEnd()) {
        const QString line = in.readLine().trimmed();
        if (line.isEmpty() || line.startsWith(QLatin1Char('#'))) {
            continue;
        }
        if (line.startsWith(QLatin1Char('[')) && line.endsWith(QLatin1Char(']'))) {
            section = line.mid(1, line.size() - 2);
        } else if (section == QLatin1String("Updates")) {
            const QString key = line.section(QLatin1Char('='), 0, 0).trimmed();
            const QString val = line.section(QLatin1Char('='), 1).trimmed();
            if (key == QLatin1String("AutoApply")) out[QStringLiteral("autoApply")] = val == QLatin1String("true");
            else if (key == QLatin1String("RequireCanaryEvidence")) out[QStringLiteral("canary")] = val == QLatin1String("true");
            else if (key == QLatin1String("RequireACPower")) out[QStringLiteral("acOnly")] = val == QLatin1String("true");
            else if (key == QLatin1String("Window")) out[QStringLiteral("window")] = val;
        }
    }
    return out;
}

void Backend::setSchedule(const QVariantMap &v)
{
    const QString payload = QStringLiteral(
        "Updates.AutoApply=%1\n"
        "Updates.RequireCanaryEvidence=%2\n"
        "Updates.RequireACPower=%3\n"
        "Updates.Window=%4\n")
        .arg(v[QStringLiteral("autoApply")].toBool() ? QStringLiteral("true") : QStringLiteral("false"),
             v[QStringLiteral("canary")].toBool() ? QStringLiteral("true") : QStringLiteral("false"),
             v[QStringLiteral("acOnly")].toBool() ? QStringLiteral("true") : QStringLiteral("false"),
             v[QStringLiteral("window")].toString());

    // The same validating writer the settings page uses, so there is one place
    // that decides what a legal value is.
    QProcess w;
    w.start(QStringLiteral("pkexec"), {QString::fromLatin1(WRITER)});
    if (!w.waitForStarted(5000)) {
        m_error = tr("Could not save the schedule.");
        Q_EMIT stateChanged();
        return;
    }
    w.write(payload.toUtf8());
    w.closeWriteChannel();
    w.waitForFinished(120000);

    if (w.exitCode() != 0) {
        m_error = (w.exitCode() == 126 || w.exitCode() == 127)
            ? tr("The schedule was not saved: authentication was cancelled.")
            : tr("The schedule could not be saved.");
    } else {
        m_error.clear();
    }
    Q_EMIT stateChanged();
}
