#include "backend.h"

#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);
    app.setApplicationName(QStringLiteral("sakura-update-center"));
    app.setOrganizationName(QStringLiteral("SakuraOS"));
    app.setDesktopFileName(QStringLiteral("org.sakuraos.updatecenter"));

    QQuickStyle::setStyle(QStringLiteral("org.kde.desktop"));

    Backend backend;
    QQmlApplicationEngine engine;
    engine.rootContext()->setContextProperty(QStringLiteral("backend"), &backend);
    engine.load(QUrl(QStringLiteral("qrc:/qml/Main.qml")));
    return engine.rootObjects().isEmpty() ? 1 : app.exec();
}
