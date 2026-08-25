#pragma once

#include <KQuickConfigModule>
#include <QString>

/**
 * System Settings page for SakuraOS.
 *
 * Reads and writes /etc/sakura/sakura.conf -- the same file the pacman hooks,
 * the shell integration and the update timer read. Binding the UI to the file
 * that actually enforces policy is deliberate: a settings page with its own
 * private copy of the state is a settings page that eventually lies.
 *
 * The file is system-wide and root-owned, so saving goes through a small
 * privileged writer rather than being written from this process. The GUI never
 * runs as root.
 */
class SakuraSettings : public KQuickConfigModule
{
    Q_OBJECT

    Q_PROPERTY(QString terminalAssistMode READ terminalAssistMode
               WRITE setTerminalAssistMode NOTIFY changed)
    Q_PROPERTY(bool aurEnabled READ aurEnabled
               WRITE setAurEnabled NOTIFY changed)
    Q_PROPERTY(bool aurReview READ aurReview
               WRITE setAurReview NOTIFY changed)
    Q_PROPERTY(bool aurCampaignScanning READ aurCampaignScanning
               WRITE setAurCampaignScanning NOTIFY changed)
    Q_PROPERTY(QString aurHelper READ aurHelper
               WRITE setAurHelper NOTIFY changed)
    Q_PROPERTY(bool updatesAutoApply READ updatesAutoApply
               WRITE setUpdatesAutoApply NOTIFY changed)
    // Not a stored setting like the others: this reports whether Wine is
    // actually installed, because that is the only honest answer to "is this
    // on". A config key could disagree with the machine.
    Q_PROPERTY(bool wineEnabled READ wineEnabled NOTIFY wineChanged)
    Q_PROPERTY(bool wineBusy READ wineBusy NOTIFY wineChanged)
    Q_PROPERTY(QString wineStatus READ wineStatus NOTIFY wineChanged)
    // The Windows programs that have actually been run, each in its own
    // prefix. Read from the same place the guard writes it.
    Q_PROPERTY(QVariantList windowsApps READ windowsApps NOTIFY windowsAppsChanged)

    Q_PROPERTY(bool storeAutoUpdate READ storeAutoUpdate
               WRITE setStoreAutoUpdate NOTIFY changed)
    Q_PROPERTY(bool updatesRequireCanary READ updatesRequireCanary
               WRITE setUpdatesRequireCanary NOTIFY changed)
    Q_PROPERTY(bool updatesRequireAC READ updatesRequireAC
               WRITE setUpdatesRequireAC NOTIFY changed)
    Q_PROPERTY(QString updatesWindow READ updatesWindow
               WRITE setUpdatesWindow NOTIFY changed)
    Q_PROPERTY(QString saveError READ saveError NOTIFY saveErrorChanged)

public:
    SakuraSettings(QObject *parent, const KPluginMetaData &data);

    QString terminalAssistMode() const { return m_terminalAssistMode; }
    void setTerminalAssistMode(const QString &value);

    bool aurEnabled() const { return m_aurEnabled; }
    void setAurEnabled(bool value);

    bool aurReview() const { return m_aurReview; }
    void setAurReview(bool value);

    bool aurCampaignScanning() const { return m_aurCampaignScanning; }
    void setAurCampaignScanning(bool value);

    QString aurHelper() const { return m_aurHelper; }
    void setAurHelper(const QString &value);

    bool updatesAutoApply() const { return m_updatesAutoApply; }
    bool storeAutoUpdate() const { return m_storeAutoUpdate; }
    bool wineEnabled() const { return m_wineEnabled; }
    bool wineBusy() const { return m_wineBusy; }
    QString wineStatus() const { return m_wineStatus; }
    Q_INVOKABLE void setWineEnabled(bool value);
    Q_INVOKABLE void refreshWine();
    QVariantList windowsApps() const { return m_windowsApps; }
    Q_INVOKABLE void refreshWindowsApps();
    Q_INVOKABLE void removeWindowsApp(const QString &slug);
    void setUpdatesAutoApply(bool value);
    void setStoreAutoUpdate(bool value);

    bool updatesRequireCanary() const { return m_updatesRequireCanary; }
    void setUpdatesRequireCanary(bool value);

    bool updatesRequireAC() const { return m_updatesRequireAC; }
    void setUpdatesRequireAC(bool value);

    QString updatesWindow() const { return m_updatesWindow; }
    void setUpdatesWindow(const QString &value);

    QString saveError() const { return m_saveError; }

    void load() override;
    void save() override;
    void defaults() override;

Q_SIGNALS:
    void changed();
    void wineChanged();
    void windowsAppsChanged();
    void saveErrorChanged();

private:
    void applyDefaults();
    void markChanged();

    QString m_terminalAssistMode;
    bool m_aurEnabled = false;
    bool m_aurReview = true;
    bool m_aurCampaignScanning = true;
    QString m_aurHelper;
    bool m_updatesAutoApply = true;
    bool m_storeAutoUpdate = true;
    bool m_wineEnabled = false;
    bool m_wineBusy = false;
    QString m_wineStatus;
    QVariantList m_windowsApps;
    bool m_updatesRequireCanary = true;
    bool m_updatesRequireAC = true;
    QString m_updatesWindow;
    QString m_saveError;
};
