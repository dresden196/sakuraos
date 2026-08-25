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
    Q_INVOKABLE QStringList timezones() const;
    Q_INVOKABLE QVariantList keyboardLayouts() const;
    Q_INVOKABLE QVariantList languages() const;
    // The characters a layout actually produces, so the keyboard screen can
    // show the layout being chosen rather than describe it.
    Q_INVOKABLE QVariantList keyboardPreview(const QString &layout) const;
    Q_INVOKABLE QStringList avatars() const;
    Q_INVOKABLE QString guessTimezone() const;
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
