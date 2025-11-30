#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include "VideoBackend.h"

int main(int argc, char *argv[])
{
    // 设置 OpenGL 后端，这对 GStreamer 兼容性有帮助
    qputenv("QSG_RHI_BACKEND", "opengl");

    QGuiApplication app(argc, argv);

    // 注册类型
    qmlRegisterType<VideoBackend>("com.mycompany.stream", 1, 0, "VideoBackend");

    QQmlApplicationEngine engine;

    // 推荐：使用资源系统加载 (如果你 CMakeLists 配置正确)
    const QUrl url(u"qrc:/Main/Main.qml"_qs);

    // 如果你坚持要用本地文件加载，请解开下面这行，注释上面那行
    // const QUrl url = QUrl::fromLocalFile(QCoreApplication::applicationDirPath() + "/Main.qml");

    QObject::connect(&engine, &QQmlApplicationEngine::objectCreated,
                     &app, [url](QObject *obj, const QUrl &objUrl) {
                         if (!obj && url == objUrl)
                             QCoreApplication::exit(-1);
                     }, Qt::QueuedConnection);

    engine.load(url);

    return app.exec();
}
