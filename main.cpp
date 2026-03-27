#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QQuickStyle>
#include "VideoBackend.h"
#include "RobotClient.h"
#include "GamepadBackend.h"

int main(int argc, char *argv[])
{
    // 启用 Material 风格
    QQuickStyle::setStyle("Material");

    QGuiApplication app(argc, argv);

    // 1. 注册 C++ 类型到 QML
    qmlRegisterType<VideoBackend>("com.mycompany.stream", 1, 0, "VideoBackend");
    qmlRegisterType<RobotClient>("MyRobot", 1, 0, "RobotClient");

    QQmlApplicationEngine engine;

    // 2. 创建全局手柄后端实例并导出
    GamepadBackend gamepadBackend;
    engine.rootContext()->setContextProperty("Backend", &gamepadBackend);

    const QUrl url(u"qrc:/qt/qml/Main/Main.qml"_qs);
    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
                         if (!obj && url == objUrl)
                             QCoreApplication::exit(-1);
                     }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}
