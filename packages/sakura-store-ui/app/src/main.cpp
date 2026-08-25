#include "backend.h"

#include <QFileInfo>
#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sakura-store"));
    app.setOrganizationName(QStringLiteral("SakuraOS"));
    app.setDesktopFileName(QStringLiteral("org.sakuraos.store"));
    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    Backend backend;
    QQmlApplicationEngine engine;
    // A file passed on the command line -- an AppImage somebody opened with
    // the store rather than a name they searched for. Handing it to the UI as
    // a property keeps the decision to install in front of the user, where it
    // belongs: opening a file must not silently install it.
    QString openFile;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        const QFileInfo info(args.at(i));
        if (info.isFile()) {
            openFile = info.absoluteFilePath();
            break;
        }
    }
    engine.rootContext()->setContextProperty(QStringLiteral("openFile"), openFile);
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    return engine.rootObjects().isEmpty() ? 1 : app.exec();
}
