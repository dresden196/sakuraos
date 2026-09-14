#pragma once

#include <QObject>
#include <QProcess>
#include <QJsonObject>
#include <QStringList>
#include <QVariantList>
#include <QVector>
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
    Q_PROPERTY(QVariantList updates READ updates NOTIFY updatesChanged)
    Q_PROPERTY(bool checkingUpdates READ checkingUpdates NOTIFY updatesChanged)
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
    // "48.0 MB of 96.0 MB", or empty when the engine has not told us a size.
    // A percentage answers "how far", an amount answers "how much longer",
    // and only the second is the question somebody staring at a download is
    // actually asking.
    Q_PROPERTY(QString downloadProgress READ downloadProgress NOTIFY progressChanged)
    // One transaction at a time was a property of this class, not of the
    // package managers underneath it. pacman genuinely cannot run twice at
    // once -- it takes an exclusive lock on its database -- but flatpak, snap
    // and pacman have nothing to do with each other, and two flatpaks queue
    // behind each other perfectly happily. So the store now keeps a queue and
    // runs one job per lane, where a lane is the thing that actually
    // serialises. Installing four applications no longer means waiting for
    // each to finish before asking for the next.
    Q_PROPERTY(QVariantList jobs READ jobs NOTIFY jobsChanged)
    // True while anything at all is running, for the few things that really
    // are global -- closing the window with work outstanding, mainly.
    Q_PROPERTY(bool anyBusy READ anyBusy NOTIFY jobsChanged)
    Q_PROPERTY(int activeJobs READ activeJobs NOTIFY jobsChanged)
    // busy now means "the application currently on screen is busy", which is
    // what every button asking the question actually wanted. A transaction
    // somewhere else no longer greys out a button here.
    Q_PROPERTY(bool busy READ busy NOTIFY progressChanged)
    // Which application the running transaction is for, so a button can tell
    // "I started this" apart from "something is running somewhere".
    Q_PROPERTY(QString busyId READ busyId NOTIFY progressChanged)
    Q_PROPERTY(QString error READ error NOTIFY progressChanged)
    // The tool's own words, kept so a wrong explanation can still be seen
    // through. Shown only if the user asks for it.
    Q_PROPERTY(QString errorDetail READ errorDetail NOTIFY progressChanged)

    // Who is signed in. Read once from the password database and the usual
    // avatar locations; the store has no account of its own and does not want
    // one, so this is the system user or nothing.
    Q_PROPERTY(QString userName READ userName CONSTANT)
    Q_PROPERTY(QString userDisplayName READ userDisplayName CONSTANT)
    Q_PROPERTY(QString userAvatar READ userAvatar CONSTANT)

    // The AUR build script, its metadata, and what changed since this user
    // last accepted one. Its own state rather than the app page's, because a
    // person can be halfway through reading a script while something else
    // installs.
    Q_PROPERTY(QVariantMap aurReview READ aurReview NOTIFY aurReviewChanged)
    Q_PROPERTY(bool aurReviewLoading READ aurReviewLoading NOTIFY aurReviewChanged)

    // Publishing a review. Kept apart from the transaction properties: an
    // install and a review can be in flight at once, and a failed review must
    // not read as a failed install.
    Q_PROPERTY(bool reviewBusy READ reviewBusy NOTIFY reviewChanged)
    Q_PROPERTY(bool reviewDone READ reviewDone NOTIFY reviewChanged)
    Q_PROPERTY(QString reviewError READ reviewError NOTIFY reviewChanged)

    // What an app list would do here. Populated by readAppList(); reading a
    // file never installs anything on its own.
    Q_PROPERTY(QVariantMap importPlan READ importPlan NOTIFY importPlanChanged)

public:
    explicit Backend(QObject *parent = nullptr);

    bool searching() const { return m_searching; }
    bool loadingApp() const { return m_loadingApp; }
    QVariantList results() const { return m_results; }
    QVariantList featured() const { return m_featured; }
    QVariantList popular() const { return m_popular; }
    QVariantList installed() const { return m_installed; }
    QVariantList updates() const { return m_updates; }
    bool checkingUpdates() const { return m_checkingUpdates; }
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
    QString downloadProgress() const;
    QString formatProgress(qint64 bytes, qint64 total, int count,
                           int countTotal, const QString &stage) const;
    bool busy() const { return m_busy; }
    QVariantList jobs() const;
    bool anyBusy() const { return !m_jobs.isEmpty(); }
    int activeJobs() const { return static_cast<int>(m_jobs.size()); }
    QString busyId() const { return m_busyId; }
    bool reviewBusy() const { return m_reviewBusy; }
    bool reviewDone() const { return m_reviewDone; }
    QString reviewError() const { return m_reviewError; }
    QVariantMap aurReview() const { return m_aurReview; }
    bool aurReviewLoading() const { return m_aurReviewLoading; }
    void notify(const QString &text) const;
    QString error() const { return m_error; }
    QString errorDetail() const { return m_errorDetail; }

    Q_INVOKABLE void search(const QString &query, const QString &source);
    Q_INVOKABLE void openApp(const QString &id);
    // Publishes to ODRS, which is public and shared with GNOME Software and
    // Discover. The dialog says so before this is reachable.
    Q_INVOKABLE void submitReview(const QString &id, int rating,
                                  const QString &summary,
                                  const QString &description,
                                  const QString &name,
                                  const QString &version);
    // Clears the outcome so the dialog opens blank rather than showing what
    // happened the last time it was used.
    Q_INVOKABLE void resetReview();

    // Fetches the build script and the diff. Reading is not accepting: this
    // records nothing.
    Q_INVOKABLE void reviewAur(const QString &name);
    // Records that this exact script was read, then installs. One step,
    // because accepting a script and then not installing it is not a thing
    // anybody wants, and two buttons would only invite clicking through.
    Q_INVOKABLE void acceptAurAndInstall(const QString &name);
    Q_INVOKABLE void clearAurReview();
    // Re-reads the page that is already open, in place.
    void refreshApp(const QString &id);
    Q_INVOKABLE void loadFeatured();
    Q_INVOKABLE void loadInstalled();
    Q_INVOKABLE void checkUpdates();
    // Empty id updates everything that has one waiting.
    Q_INVOKABLE void applyUpdates(const QString &id, const QString &source);
    Q_INVOKABLE void loadCategory(const QString &id, const QString &label);
    Q_INVOKABLE void install(const QString &id, const QString &source);
    // What the queue panel and each app page ask about one application.
    Q_INVOKABLE QVariantMap jobFor(const QString &id, const QString &source) const;
    // Only a job that has not started can be dropped. Killing pacman half way
    // through a transaction is how a system ends up with a half-installed
    // package and a stale lock, so a running job is left to finish.
    Q_INVOKABLE void cancelJob(const QString &id, const QString &source);
    Q_INVOKABLE void dismissJob(const QString &id, const QString &source);
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

    QString userName() const;
    QString userDisplayName() const;
    QString userAvatar() const;
    QVariantMap importPlan() const { return m_importPlan; }
    Q_INVOKABLE void exportAppList(const QString &path);
    Q_INVOKABLE void readAppList(const QString &path);
    Q_INVOKABLE void clearImportPlan();

Q_SIGNALS:
    void stateChanged();
    void resultsChanged();
    void featuredChanged();
    void installedChanged();
    void updatesChanged();
    void removalPlanChanged();
    void importPlanChanged();
    void removed(const QString &id, const QString &source);
    void categoryChanged();
    void appChanged();
    void progressChanged();
    void jobsChanged();

    void reviewChanged();
    void aurReviewChanged();
private:
    QProcess *run(const QStringList &args);

    // One queued or running piece of work. Everything the queue panel shows
    // and everything an app page needs to describe its own state lives here,
    // per job, rather than in one set of fields shared by whatever ran last.
    struct Job {
        QString id;
        QString source;
        QString name;
        QString kind;        // install | remove | update
        QString stage;       // queued | resolving | downloading | ... | failed
        QString detail;
        QString error;
        QString errorDetail;
        int percent = 0;
        qint64 bytes = 0;
        qint64 total = 0;
        int count = 0;
        int countTotal = 0;
        bool deleteData = false;
        QStringList args;
        QProcess *proc = nullptr;
    };

    // pacman and the AUR share one lock, so they share one lane. Everything
    // else is independent and gets a lane of its own.
    static QString laneOf(const QString &source);
    void enqueue(const Job &job);
    void pump();
    void onJobLine(int index, const QJsonObject &o);
    void finishJob(int index, int code, bool crashed, const QString &trailing);
    int indexOfJob(const QString &id, const QString &source) const;
    QVariantMap jobToMap(const Job &j) const;
    void syncCurrentFromJobs();
    void markInstalled(const QString &id, const QString &source, bool state);
    QVector<Job> m_jobs;

    void loadCollection(const QString &name, int limit, QVariantList &into);

    QVariantList m_results, m_featured, m_popular, m_installed;
    bool m_loadingInstalled = false;
    bool m_planningRemoval = false;
    QVariantMap m_removalPlan;
    QVariantMap m_importPlan;
    bool m_loadingCategory = false;
    QVariantList m_categories, m_categoryApps, m_sources, m_updates;
    bool m_checkingUpdates = false;
    QString m_categoryName;
    QVariantMap m_app, m_unavailable;
    QString m_errorDetail;
    QString m_stage, m_detail, m_error;
    int m_percent = 0;
    qint64 m_bytes = 0;
    qint64 m_total = 0;
    int m_count = 0;
    int m_countTotal = 0;
    bool m_searching = false, m_loadingApp = false, m_busy = false;
    bool m_exporting = false;
    QString m_busyId;
    bool m_reviewBusy = false;
    bool m_reviewDone = false;
    QString m_reviewError;
    QVariantMap m_aurReview;
    bool m_aurReviewLoading = false;
    QString m_busyName;
};
