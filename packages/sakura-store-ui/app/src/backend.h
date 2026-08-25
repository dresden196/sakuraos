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
    Q_PROPERTY(QVariantList installed READ installed NOTIFY installedChanged)
    Q_PROPERTY(QVariantMap removalPlan READ removalPlan NOTIFY removalPlanChanged)
    Q_PROPERTY(bool planningRemoval READ planningRemoval NOTIFY removalPlanChanged)
    Q_PROPERTY(QVariantList categories READ categories CONSTANT)
    Q_PROPERTY(QVariantList sources READ sources CONSTANT)
    Q_PROPERTY(QVariantList categoryApps READ categoryApps NOTIFY categoryChanged)
    Q_PROPERTY(QString categoryName READ categoryName NOTIFY categoryChanged)
    Q_PROPERTY(bool loadingCategory READ loadingCategory NOTIFY categoryChanged)
    Q_PROPERTY(bool loadingInstalled READ loadingInstalled NOTIFY installedChanged)
    Q_PROPERTY(QVariantMap app READ app NOTIFY appChanged)
    Q_PROPERTY(QVariantMap unavailable READ unavailable NOTIFY resultsChanged)
    Q_PROPERTY(QString stage READ stage NOTIFY progressChanged)
    Q_PROPERTY(int percent READ percent NOTIFY progressChanged)
    Q_PROPERTY(QString progressDetail READ progressDetail NOTIFY progressChanged)
    Q_PROPERTY(bool busy READ busy NOTIFY progressChanged)
    Q_PROPERTY(QString error READ error NOTIFY progressChanged)
    // The tool's own words, kept so a wrong explanation can still be seen
    // through. Shown only if the user asks for it.
    Q_PROPERTY(QString errorDetail READ errorDetail NOTIFY progressChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    bool searching() const { return m_searching; }
    bool loadingApp() const { return m_loadingApp; }
    QVariantList results() const { return m_results; }
    QVariantList featured() const { return m_featured; }
    QVariantList popular() const { return m_popular; }
    QVariantList installed() const { return m_installed; }
    QVariantMap removalPlan() const { return m_removalPlan; }
    bool planningRemoval() const { return m_planningRemoval; }
    QVariantList categories() const { return m_categories; }
    QVariantList sources() const { return m_sources; }
    QVariantList categoryApps() const { return m_categoryApps; }
    QString categoryName() const { return m_categoryName; }
    bool loadingCategory() const { return m_loadingCategory; }
    bool loadingInstalled() const { return m_loadingInstalled; }
    QVariantMap app() const { return m_app; }
    QVariantMap unavailable() const { return m_unavailable; }
    QString stage() const { return m_stage; }
    int percent() const { return m_percent; }
    QString progressDetail() const { return m_detail; }
    bool busy() const { return m_busy; }
    QString error() const { return m_error; }
    QString errorDetail() const { return m_errorDetail; }

    Q_INVOKABLE void search(const QString &query, const QString &source);
    Q_INVOKABLE void openApp(const QString &id);
    Q_INVOKABLE void loadFeatured();
    Q_INVOKABLE void loadInstalled();
    Q_INVOKABLE void loadCategory(const QString &id, const QString &label);
    Q_INVOKABLE void install(const QString &id, const QString &source);
    Q_INVOKABLE void planRemoval(const QString &id, const QString &source);
    Q_INVOKABLE void clearRemovalPlan();
    Q_INVOKABLE void remove(const QString &id, const QString &source,
                            bool deleteData = false);
    Q_INVOKABLE void openPermissions(const QString &id);
    // Dismiss a failure the user has read.
    Q_INVOKABLE void clearError();
    // Install an AppImage the user already has, rather than one from a
    // catalogue. There is nothing to look it up in.
    Q_INVOKABLE void installLocalAppImage(const QString &path);

Q_SIGNALS:
    void stateChanged();
    void resultsChanged();
    void featuredChanged();
    void installedChanged();
    void removalPlanChanged();
    void removed(const QString &id, const QString &source);
    void categoryChanged();
    void appChanged();
    void progressChanged();

private:
    QProcess *run(const QStringList &args);

    void loadCollection(const QString &name, int limit, QVariantList &into);

    QVariantList m_results, m_featured, m_popular, m_installed;
    bool m_loadingInstalled = false;
    bool m_planningRemoval = false;
    QVariantMap m_removalPlan;
    bool m_loadingCategory = false;
    QVariantList m_categories, m_categoryApps, m_sources;
    QString m_categoryName;
    QVariantMap m_app, m_unavailable;
    QString m_errorDetail;
    QString m_stage, m_detail, m_error;
    int m_percent = 0;
    bool m_searching = false, m_loadingApp = false, m_busy = false;
};
