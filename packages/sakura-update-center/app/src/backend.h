#pragma once

#include <QAbstractListModel>
#include <QObject>
#include <QProcess>
#include <QVariantList>

/**
 * Everything the Update Centre shows comes from sakura-update.
 *
 * The engine is the one implementation; this draws it. If the window and the
 * nightly timer disagreed about what was held and why, the window would be
 * the one people believed.
 */
class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool busy READ busy NOTIFY stateChanged)
    Q_PROPERTY(bool applying READ applying NOTIFY stateChanged)
    Q_PROPERTY(QString error READ error NOTIFY stateChanged)
    Q_PROPERTY(QString lastChecked READ lastChecked NOTIFY stateChanged)
    Q_PROPERTY(bool restartRequired READ restartRequired NOTIFY dataChanged)
    Q_PROPERTY(QVariantList updates READ updates NOTIFY dataChanged)
    Q_PROPERTY(QVariantList holds READ holds NOTIFY dataChanged)
    Q_PROPERTY(QVariantList history READ history NOTIFY dataChanged)
    Q_PROPERTY(QString log READ log NOTIFY logChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    bool busy() const { return m_busy; }
    bool applying() const { return m_applying; }
    QString error() const { return m_error; }
    QString lastChecked() const { return m_lastChecked; }
    bool restartRequired() const { return m_restart; }
    QVariantList updates() const { return m_updates; }
    QVariantList holds() const { return m_holds; }
    QVariantList history() const { return m_history; }
    QString log() const { return m_log; }

    Q_INVOKABLE void check();
    Q_INVOKABLE void apply();
    Q_INVOKABLE void loadHistory();
    Q_INVOKABLE void rollback(const QString &number);
    Q_INVOKABLE QVariantMap schedule() const;
    Q_INVOKABLE void setSchedule(const QVariantMap &values);

Q_SIGNALS:
    void stateChanged();
    void dataChanged();
    void logChanged();
    void applyFinished(bool ok);

private:
    void setBusy(bool b);

    QProcess *m_proc = nullptr;
    QVariantList m_updates, m_holds, m_history;
    QString m_error, m_lastChecked, m_log;
    bool m_busy = false, m_applying = false, m_restart = false;
};
