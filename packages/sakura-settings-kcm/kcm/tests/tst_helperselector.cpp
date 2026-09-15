// Runs the QML tests staged beside the component they exercise. See the
// CMakeLists here for why they are staged rather than run from the source tree.
//
// The engine needs a localized context before it loads anything: the component
// calls i18n() for its labels, and without that function the whole model
// binding throws, leaving a ComboBox with no items. The first run of this test
// failed six ways for that one reason -- count 0, valueAt undefined, and a
// currentIndex of -1 -- none of which had anything to do with the component.
// System Settings supplies the context in production; here it is set up by
// hand.
#include <QtQuickTest>
#include <QQmlEngine>
#include <KLocalizedQmlContext>

class Setup : public QObject
{
    Q_OBJECT
public Q_SLOTS:
    void qmlEngineAvailable(QQmlEngine *engine)
    {
        KLocalization::setupLocalizedContext(engine);
    }
};

QUICK_TEST_MAIN_WITH_SETUP(helperselector, Setup)
#include "tst_helperselector.moc"
