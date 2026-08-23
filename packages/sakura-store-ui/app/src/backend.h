#pragma once

#include <QObject>
#include <QProcess>
#include <QVariantList>
#include <QVariantMap>

/**
 * Everything the store window shows comes from sakura-store.
 *
 * The engine already decides what a source is, what is installed and what a
 * rating means. Duplicating any of that here would give the window its own
 * opinion, and the window is the one people would believe.
 */
class Backend : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool searching READ searching NOTIFY stateChanged)
    Q_PROPERTY(bool loadingApp READ loadingApp NOTIFY stateChanged)
    Q_PROPERTY(QVariantList results READ results NOTIFY resultsChanged)
    Q_PROPERTY(QVariantList featured READ featured NOTIFY featuredChanged)
    Q_PROPERTY(QVariantList popular READ popular NOTIFY featuredChanged)
    Q_PROPERTY(QVariantMap app READ app NOTIFY appChanged)
    Q_PROPERTY(QVariantMap unavailable READ unavailable NOTIFY resultsChanged)
    Q_PROPERTY(QString stage READ stage NOTIFY progressChanged)
    Q_PROPERTY(int percent READ percent NOTIFY progressChanged)
    Q_PROPERTY(QString progressDetail READ progressDetail NOTIFY progressChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY progressChanged)
    Q_PROPERTY(QString error READ error NOTIFY progressChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    bool searching() const { return m_searching; }
    bool loadingApp() const { return m_loadingApp; }
    QVariantList results() const { return m_results; }
    QVariantList featured() const { return m_featured; }
    QVariantList popular() const { return m_popular; }
    QVariantMap app() const { return m_app; }
    QVariantMap unavailable() const { return m_unavailable; }
    QString stage() const { return m_stage; }
    int percent() const { return m_percent; }
    QString progressDetail() const { return m_detail; }
    bool busy() const { return m_busy; }
    QString error() const { return m_error; }

    Q_INVOKABLE void search(const QString &query, const QString &source);
    Q_INVOKABLE void openApp(const QString &id);
    Q_INVOKABLE void loadFeatured();
    Q_INVOKABLE void install(const QString &id, const QString &source);
    Q_INVOKABLE void remove(const QString &id, const QString &source);
    Q_INVOKABLE void openPermissions(const QString &id);

Q_SIGNALS:
    void stateChanged();
    void resultsChanged();
    void featuredChanged();
    void appChanged();
    void progressChanged();

private:
    QProcess *run(const QStringList &args);

    void loadCollection(const QString &name, int limit, QVariantList &into);

    QVariantList m_results, m_featured, m_popular;
    QVariantMap m_app, m_unavailable;
    QString m_stage, m_detail, m_error;
    int m_percent = 0;
    bool m_searching = false, m_loadingApp = false, m_busy = false;
};
