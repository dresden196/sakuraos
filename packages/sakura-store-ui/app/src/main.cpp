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
    // An application id to open straight onto, as `--app org.mozilla.firefox`.
    // This is how the Windows-program guard hands over: somebody double-clicked
    // a Windows installer, we offered the Linux build instead, and they said
    // yes. Landing them on the store's front page at that point would make them
    // search for the thing they just asked for by name.
    QString openAppId;
    const QStringList args = app.arguments();
    for (int i = 1; i < args.size(); ++i) {
        const QString arg = args.at(i);
        if (arg == QStringLiteral("--app") && i + 1 < args.size()) {
            openAppId = args.at(++i);
            continue;
        }
        if (arg.startsWith(QStringLiteral("--app="))) {
            openAppId = arg.mid(6);
            continue;
        }
        if (arg.startsWith(QStringLiteral("-"))) {
            continue;
        }
        const QFileInfo info(arg);
        if (info.isFile()) {
            openFile = info.absoluteFilePath();
        }
    }
    engine.rootContext()->setContextProperty(QStringLiteral("openFile"), openFile);
    engine.rootContext()->setContextProperty(QStringLiteral("openAppId"), openAppId);
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    return engine.rootObjects().isEmpty() ? 1 : app.exec();
}
