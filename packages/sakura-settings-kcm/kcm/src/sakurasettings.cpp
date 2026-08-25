#include "sakurasettings.h"
#include <QJsonObject>
#include <QJsonDocument>

#include <KConfig>
#include <KConfigGroup>
#include <KLocalizedString>
#include <KPluginFactory>

#include <QProcess>

namespace
{
constexpr auto ConfigPath = "/etc/sakura/sakura.conf";
constexpr auto WriterPath = "/usr/lib/sakura/settings/sakura-settings-write";
}

K_PLUGIN_CLASS_WITH_JSON(SakuraSettings, "kcm_sakura.json")

SakuraSettings::SakuraSettings(QObject *parent, const KPluginMetaData &data)
    : KQuickConfigModule(parent, data)
{
    load();
}

void SakuraSettings::markChanged()
{
    Q_EMIT changed();
    setNeedsSave(true);
}

void SakuraSettings::applyDefaults()
{
    m_terminalAssistMode = QStringLiteral("block");
    m_aurEnabled = false;
    m_aurReview = true;
    m_aurCampaignScanning = true;
    m_aurHelper = QStringLiteral("yay");
    m_updatesAutoApply = true;
    m_updatesRequireCanary = true;
    m_updatesRequireAC = true;
    m_updatesWindow = QStringLiteral("03:00");
}

void SakuraSettings::load()
{
    applyDefaults();

    KConfig config(QString::fromLatin1(ConfigPath), KConfig::SimpleConfig);

    const KConfigGroup assist = config.group(QStringLiteral("TerminalAssist"));
    m_terminalAssistMode = assist.readEntry("Mode", m_terminalAssistMode);

    const KConfigGroup aur = config.group(QStringLiteral("AUR"));
    m_aurEnabled = aur.readEntry("Enabled", m_aurEnabled);
    m_aurReview = aur.readEntry("ReviewBeforeInstall", m_aurReview);
    m_aurCampaignScanning = aur.readEntry("KnownCampaignScanning", m_aurCampaignScanning);
    m_aurHelper = aur.readEntry("Helper", m_aurHelper);

    const KConfigGroup updates = config.group(QStringLiteral("Updates"));
    m_updatesAutoApply = updates.readEntry("AutoApply", m_updatesAutoApply);

    const KConfigGroup store(&config, QStringLiteral("Store"));
    m_storeAutoUpdate = store.readEntry(QStringLiteral("AutoUpdate"), m_storeAutoUpdate);
    m_updatesRequireCanary = updates.readEntry("RequireCanaryEvidence", m_updatesRequireCanary);
    m_updatesRequireAC = updates.readEntry("RequireACPower", m_updatesRequireAC);
    m_updatesWindow = updates.readEntry("Window", m_updatesWindow);

    Q_EMIT changed();
    setNeedsSave(false);
}

void SakuraSettings::save()
{
    // The config file is root-owned, so hand the values to a small privileged
    // writer instead of writing from this process. The writer re-validates
    // every key and value: it runs as root on input from an unprivileged
    // caller, so it cannot trust anything sent to it, including from us.
    const QString payload = QStringLiteral(
        "TerminalAssist.Mode=%1\n"
        "AUR.Enabled=%2\n"
        "AUR.ReviewBeforeInstall=%3\n"
        "AUR.KnownCampaignScanning=%4\n"
        "AUR.Helper=%5\n"
        "Updates.AutoApply=%6\n"
        "Updates.RequireCanaryEvidence=%7\n"
        "Updates.RequireACPower=%8\n"
        "Updates.Window=%9\n"
        // %10 last, and its argument last: arg() fills by number, so an
        // argument inserted in the middle of the list silently lands in
        // somebody else's placeholder.
        "Store.AutoUpdate=%10\n")
        .arg(m_terminalAssistMode,
             m_aurEnabled ? QStringLiteral("true") : QStringLiteral("false"),
             m_aurReview ? QStringLiteral("true") : QStringLiteral("false"),
             m_aurCampaignScanning ? QStringLiteral("true") : QStringLiteral("false"),
             m_aurHelper,
             m_updatesAutoApply ? QStringLiteral("true") : QStringLiteral("false"),
             m_updatesRequireCanary ? QStringLiteral("true") : QStringLiteral("false"),
             m_updatesRequireAC ? QStringLiteral("true") : QStringLiteral("false"),
             m_updatesWindow)
        .arg(m_storeAutoUpdate ? QStringLiteral("true") : QStringLiteral("false"));

    QProcess writer;
    writer.start(QStringLiteral("pkexec"), {QString::fromLatin1(WriterPath)});
    if (!writer.waitForStarted(5000)) {
        m_saveError = i18n("Could not start the settings helper.");
        Q_EMIT saveErrorChanged();
        return;
    }

    writer.write(payload.toUtf8());
    writer.closeWriteChannel();
    // Generous: the user may be looking at an authentication prompt.
    writer.waitForFinished(120000);

    if (writer.exitStatus() != QProcess::NormalExit || writer.exitCode() != 0) {
        const QString detail = QString::fromUtf8(writer.readAllStandardError()).trimmed();
        // Exit 126/127 is pkexec's "authentication failed or was dismissed".
        if (writer.exitCode() == 126 || writer.exitCode() == 127) {
            m_saveError = i18n("Settings were not saved: authentication was cancelled.");
        } else {
            m_saveError = detail.isEmpty()
                ? i18n("Settings could not be saved.")
                : i18n("Settings could not be saved: %1", detail);
        }
        Q_EMIT saveErrorChanged();
        // Reload so the UI shows what is actually on disk rather than what
        // the user hoped they had just applied.
        load();
        return;
    }

    m_saveError.clear();
    Q_EMIT saveErrorChanged();
    setNeedsSave(false);
}

void SakuraSettings::defaults()
{
    applyDefaults();
    markChanged();
}

void SakuraSettings::setTerminalAssistMode(const QString &value)
{
    if (m_terminalAssistMode == value) return;
    m_terminalAssistMode = value;
    markChanged();
}

void SakuraSettings::setAurEnabled(bool value)
{
    if (m_aurEnabled == value) return;
    m_aurEnabled = value;
    markChanged();
}

void SakuraSettings::setAurReview(bool value)
{
    if (m_aurReview == value) return;
    m_aurReview = value;
    markChanged();
}

void SakuraSettings::setAurCampaignScanning(bool value)
{
    if (m_aurCampaignScanning == value) return;
    m_aurCampaignScanning = value;
    markChanged();
}

void SakuraSettings::setAurHelper(const QString &value)
{
    if (m_aurHelper == value) return;
    m_aurHelper = value;
    markChanged();
}

void SakuraSettings::setUpdatesAutoApply(bool value)
{
    if (m_updatesAutoApply == value) return;
    m_updatesAutoApply = value;
    markChanged();
}
void SakuraSettings::setStoreAutoUpdate(bool value)
{
    if (m_storeAutoUpdate == value) return;
    m_storeAutoUpdate = value;
    markChanged();
}

void SakuraSettings::setUpdatesRequireCanary(bool value)
{
    if (m_updatesRequireCanary == value) return;
    m_updatesRequireCanary = value;
    markChanged();
}

void SakuraSettings::setUpdatesRequireAC(bool value)
{
    if (m_updatesRequireAC == value) return;
    m_updatesRequireAC = value;
    markChanged();
}

void SakuraSettings::setUpdatesWindow(const QString &value)
{
    if (m_updatesWindow == value) return;
    m_updatesWindow = value;
    markChanged();
}

#include "sakurasettings.moc"

namespace {
const char WINE_HELPER[] = "/usr/lib/sakura/wine/sakura-wine";
}

void SakuraSettings::refreshWine()
{
    // Asked of the machine, not of a config file. A stored "wine: true" that
    // disagrees with what is installed is worse than no setting at all --
    // the switch would be on and nothing would work.
    QProcess p;
    p.start(QString::fromLatin1(WINE_HELPER), {QStringLiteral("status")});
    if (!p.waitForFinished(5000)) {
        return;
    }
    const QJsonObject o =
        QJsonDocument::fromJson(p.readAllStandardOutput()).object();
    m_wineEnabled = o[QStringLiteral("enabled")].toBool();
    const QString version = o[QStringLiteral("version")].toString();
    m_wineStatus = m_wineEnabled && !version.isEmpty() ? version : QString();
    Q_EMIT wineChanged();
}

void SakuraSettings::setWineEnabled(bool value)
{
    if (m_wineBusy || value == m_wineEnabled) {
        return;
    }
    m_wineBusy = true;
    m_wineStatus = value ? i18n("Downloading Wine and its runtimes. This is "
                                "about a gigabyte and will take a few minutes.")
                         : i18n("Removing Wine.");
    Q_EMIT wineChanged();

    auto *proc = new QProcess(this);
    proc->setProcessChannelMode(QProcess::MergedChannels);
    connect(proc, &QProcess::finished, this,
            [this, proc, value](int code, QProcess::ExitStatus status) {
        const QString out = QString::fromUtf8(proc->readAll()).trimmed();
        proc->deleteLater();
        m_wineBusy = false;
        if (code != 0 || status != QProcess::NormalExit) {
            m_wineStatus = (code == 126 || code == 127)
                ? i18n("Authentication was cancelled; nothing has changed.")
                : i18n("That did not work.");
            Q_EMIT wineChanged();
        }
        // Either way, ask the machine what is actually true now rather than
        // assuming the operation did what it was asked.
        refreshWine();
    });
    proc->start(QStringLiteral("pkexec"),
                {QString::fromLatin1(WINE_HELPER),
                 value ? QStringLiteral("enable") : QStringLiteral("disable")});
}
