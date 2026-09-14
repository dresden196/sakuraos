// What the queue promises, checked rather than asserted in a commit message.
//
// Three claims are worth testing and none of them can be seen by installing a
// package by hand: that work in different lanes overlaps, that work in the same
// lane does not, and that a failure stops its own lane without taking the
// others down or vanishing from the panel.
#include "../src/backend.h"

#include <QCoreApplication>
#include <QElapsedTimer>
#include <QFile>
#include <QSignalSpy>
#include <QTest>

class QueueTest : public QObject
{
    Q_OBJECT

private:
    QString logPath;

    QStringList logLines() const
    {
        QFile f(logPath);
        if (!f.open(QIODevice::ReadOnly | QIODevice::Text)) {
            return {};
        }
        return QString::fromUtf8(f.readAll()).split(QLatin1Char('\n'),
                                                    Qt::SkipEmptyParts);
    }

    // True when a started before b finished: the definition of "these two ran
    // at the same time" that does not depend on how fast the machine is.
    bool overlapped(const QString &aId, const QString &bId) const
    {
        qint64 aStart = -1, aEnd = -1, bStart = -1, bEnd = -1;
        for (const QString &line : logLines()) {
            const QStringList f = line.split(QLatin1Char(' '));
            if (f.size() < 4) {
                continue;
            }
            const qint64 t = f.at(3).toLongLong();
            if (f.at(2) == aId) {
                (f.at(0) == QLatin1String("START") ? aStart : aEnd) = t;
            }
            if (f.at(2) == bId) {
                (f.at(0) == QLatin1String("START") ? bStart : bEnd) = t;
            }
        }
        if (aStart < 0 || bStart < 0) {
            return false;
        }
        return (bStart < aEnd || aEnd < 0) && (aStart < bEnd || bEnd < 0);
    }

    bool waitForIdle(Backend &b, int ms = 15000)
    {
        QElapsedTimer t;
        t.start();
        while (b.activeJobs() > 0 && t.elapsed() < ms) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        }
        // Let the deleteLater on each finished QProcess actually run. Without
        // this the Backend is destroyed with deletions still pending and Qt
        // prints "Destroyed while process is still running" for work that had
        // in fact finished -- noise that looks exactly like a leak.
        for (int i = 0; i < 5; ++i) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 20);
            QCoreApplication::sendPostedEvents(nullptr, QEvent::DeferredDelete);
        }
        return b.activeJobs() == 0;
    }

private Q_SLOTS:
    void init()
    {
        logPath = QDir::tempPath() + QStringLiteral("/sakura-queue-test.log");
        QFile::remove(logPath);
        qputenv("SAKURA_STUB_LOG", logPath.toUtf8());
        qputenv("SAKURA_STUB_MS", "600");
    }

    // The complaint that started this: a second install did nothing at all.
    void secondInstallIsAccepted()
    {
        Backend b;
        b.install(QStringLiteral("alpha"), QStringLiteral("flatpak"));
        b.install(QStringLiteral("beta"), QStringLiteral("snap"));
        QCOMPARE(b.activeJobs(), 2);
        QVERIFY(waitForIdle(b));
        QCOMPARE(logLines().size(), 4);   // two starts, two ends
    }

    // Different package managers have nothing to do with each other, so they
    // run together. This is the actual feature.
    void differentLanesRunAtOnce()
    {
        Backend b;
        b.install(QStringLiteral("alpha"), QStringLiteral("flatpak"));
        b.install(QStringLiteral("beta"), QStringLiteral("snap"));
        b.install(QStringLiteral("gamma"), QStringLiteral("pacman"));
        QVERIFY(waitForIdle(b));
        QVERIFY2(overlapped(QStringLiteral("alpha"), QStringLiteral("beta")),
                 "flatpak and snap should run at the same time");
        QVERIFY2(overlapped(QStringLiteral("alpha"), QStringLiteral("gamma")),
                 "flatpak and pacman should run at the same time");
    }

    // pacman takes an exclusive lock on its database. Two at once is not a
    // performance win, it is a failed transaction.
    void sameLaneSerialises()
    {
        Backend b;
        b.install(QStringLiteral("one"), QStringLiteral("pacman"));
        b.install(QStringLiteral("two"), QStringLiteral("pacman"));
        QVERIFY(waitForIdle(b));
        QVERIFY2(!overlapped(QStringLiteral("one"), QStringLiteral("two")),
                 "two pacman transactions must never overlap");
    }

    // The AUR ends in pacman -U, so it shares pacman's lock and its lane.
    void aurSharesThePacmanLane()
    {
        Backend b;
        b.install(QStringLiteral("one"), QStringLiteral("pacman"));
        b.install(QStringLiteral("two"), QStringLiteral("aur"));
        QVERIFY(waitForIdle(b));
        QVERIFY2(!overlapped(QStringLiteral("one"), QStringLiteral("two")),
                 "an AUR build must not run beside a pacman transaction");
    }

    // A double click is one install, not two.
    void duplicatesAreIgnored()
    {
        Backend b;
        b.install(QStringLiteral("alpha"), QStringLiteral("flatpak"));
        b.install(QStringLiteral("alpha"), QStringLiteral("flatpak"));
        QCOMPARE(b.activeJobs(), 1);
        QVERIFY(waitForIdle(b));
    }

    // The same application from two different sources is two different things.
    void sameIdDifferentSourceIsTwoJobs()
    {
        Backend b;
        b.install(QStringLiteral("alpha"), QStringLiteral("flatpak"));
        b.install(QStringLiteral("alpha"), QStringLiteral("snap"));
        QCOMPARE(b.activeJobs(), 2);
        QVERIFY(waitForIdle(b));
    }

    // A failure must stay on screen -- one nobody sees is one that did not
    // happen -- and must not stop the lane beside it.
    void failureStaysAndDoesNotBlockOthers()
    {
        qputenv("SAKURA_STUB_FAIL_bad", "1");
        Backend b;
        b.install(QStringLiteral("bad"), QStringLiteral("flatpak"));
        b.install(QStringLiteral("good"), QStringLiteral("snap"));
        QElapsedTimer t;
        t.start();
        while (b.activeJobs() > 1 && t.elapsed() < 15000) {
            QCoreApplication::processEvents(QEventLoop::AllEvents, 50);
        }
        QCOMPARE(b.activeJobs(), 1);
        const QVariantMap bad = b.jobFor(QStringLiteral("bad"),
                                         QStringLiteral("flatpak"));
        QVERIFY2(bad.value(QStringLiteral("failed")).toBool(),
                 "the failed job should still be in the queue");
        QVERIFY(!bad.value(QStringLiteral("error")).toString().isEmpty());
        b.dismissJob(QStringLiteral("bad"), QStringLiteral("flatpak"));
        QCOMPARE(b.activeJobs(), 0);
        qunsetenv("SAKURA_STUB_FAIL_bad");
    }

    // A queued job can be dropped before it starts; a running one cannot,
    // because killing a package manager mid-transaction is worse than waiting.
    void queuedCancels_runningDoesNot()
    {
        Backend b;
        b.install(QStringLiteral("one"), QStringLiteral("pacman"));
        b.install(QStringLiteral("two"), QStringLiteral("pacman"));
        QCoreApplication::processEvents(QEventLoop::AllEvents, 100);
        b.cancelJob(QStringLiteral("two"), QStringLiteral("pacman"));
        QCOMPARE(b.activeJobs(), 1);
        b.cancelJob(QStringLiteral("one"), QStringLiteral("pacman"));
        QCOMPARE(b.activeJobs(), 1);   // running: refused, still there
        QVERIFY(waitForIdle(b));
    }

    // Three in one lane come out in the order they were asked for.
    void queueKeepsItsOrder()
    {
        qputenv("SAKURA_STUB_MS", "300");
        Backend b;
        b.install(QStringLiteral("first"), QStringLiteral("pacman"));
        b.install(QStringLiteral("second"), QStringLiteral("pacman"));
        b.install(QStringLiteral("third"), QStringLiteral("pacman"));
        QVERIFY(waitForIdle(b, 20000));
        QStringList starts;
        for (const QString &line : logLines()) {
            const QStringList f = line.split(QLatin1Char(' '));
            if (f.size() > 2 && f.at(0) == QLatin1String("START")) {
                starts << f.at(2);
            }
        }
        QCOMPARE(starts, (QStringList{QStringLiteral("first"),
                                      QStringLiteral("second"),
                                      QStringLiteral("third")}));
    }
};

QTEST_GUILESS_MAIN(QueueTest)
#include "test_queue.moc"
