#include "backend.h"

#include <QGuiApplication>
#include <QIcon>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sakura-installer"));
    app.setOrganizationName(QStringLiteral("SakuraOS"));
    app.setDesktopFileName(QStringLiteral("org.sakuraos.installer"));

    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    Backend backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));

    if (engine.rootObjects().isEmpty()) {
        return 1;
    }
    return app.exec();
}
