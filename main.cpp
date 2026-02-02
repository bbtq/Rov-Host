#include <QGuiApplication> // 或者 QApplication
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "RobotClient.h"
#include "GamepadBackend.h"

int main(int argc, char *argv[])
{
    QGuiApplication app(argc, argv);

    // 注册C++类型到QML
    qmlRegisterType<RobotClient>("MyRobot", 1, 0, "RobotClient");

    QQmlApplicationEngine engine;
    GamepadBackend backend;
    engine.rootContext()->setContextProperty("Backend", &backend);

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreationFailed,
                     &app, []() { QCoreApplication::exit(-1); },
                     Qt::QueuedConnection);
    // const QUrl url(u"qrc:/json_control/Main.qml"_qs);
    // const QUrl url(QCoreApplication::applicationDirPath() + "/json_control/Main.qml");
    // QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
    //                  &app, [url](QObject *obj, const QUrl &objUrl) {
    //                      if (!obj && url == objUrl)
    //                          QCoreApplication::exit(-1);
    //                  }, Qt::QueuedConnection);
    // engine.load(url);
    engine.loadFromModule("json_control", "Main");

    return app.exec();
}
