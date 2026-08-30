#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>

/**
 * Everything the installer UI needs from the system.
 *
 * Deliberately thin: it enumerates hardware and hands a finished answer to
 * sakura-install, which owns all the partitioning and boot setup. The UI does
 * not get its own copy of that logic, because then there would be two and
 * only one of them would be tested.
 */
class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(QString currentStep READ currentStep NOTIFY progressChanged)
    Q_PROPERTY(int percent READ percent NOTIFY progressChanged)
    Q_PROPERTY(bool running READ running NOTIFY runningChanged)
    Q_PROPERTY(QString log READ log NOTIFY logChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    Q_INVOKABLE QVariantList disks() const;
    // What is already on a disk, and whether there is room beside it. The
    // difference between erasing somebody's machine and installing next to
    // what they have.
    Q_INVOKABLE QVariantMap diskLayout(const QString &device) const;
    Q_INVOKABLE QStringList timezones() const;
    Q_INVOKABLE QVariantList timezoneChoices() const;
    Q_INVOKABLE QVariantList keyboardLayouts() const;
    Q_INVOKABLE QVariantList languages() const;
    // The characters a layout actually produces, so the keyboard screen can
    // show the layout being chosen rather than describe it.
    Q_INVOKABLE QVariantList keyboardPreview(const QString &layout) const;
    Q_INVOKABLE QStringList avatars() const;

    // ---- network -------------------------------------------------------
    // An install fetches most of its packages from Arch's mirrors, so a
    // machine with no connection cannot complete one. Everything here goes
    // through nmcli: NetworkManager is running on the live image already,
    // and a second way of configuring an interface is a second thing to
    // disagree with the first.
    Q_INVOKABLE QVariantMap networkState() const;
    Q_INVOKABLE bool hasWifiHardware() const;
    Q_INVOKABLE QVariantList wifiNetworks() const;
    Q_INVOKABLE void rescanWifi();
    Q_INVOKABLE QString connectWifi(const QString &ssid, const QString &password);
    Q_INVOKABLE QString applyStaticAddress(const QString &device,
                                           const QString &address,
                                           const QString &gateway,
                                           const QString &dns);
    Q_INVOKABLE QString useAutomaticAddress(const QString &device);
    Q_INVOKABLE QString guessTimezone() const;
    // Seconds from UTC for a zone, right now -- so the clock on the time
    // screen shows the time in the zone being chosen rather than the time
    // where the installer happens to be running.
    Q_INVOKABLE int utcOffset(const QString &timezone) const;
    Q_INVOKABLE void install(const QVariantMap &answers);

    QString currentStep() const { return m_step; }
    int percent() const { return m_percent; }
    bool running() const { return m_running; }
    QString log() const { return m_log; }

Q_SIGNALS:
    void progressChanged();
    void runningChanged();
    void logChanged();
    void finished(bool ok);

private:
    void appendLog(const QString &text);

    QProcess *m_proc = nullptr;
    QString m_step;
    QString m_log;
    int m_percent = 0;
    bool m_running = false;
};
