#include <QGuiApplication>
#include <QQmlApplicationEngine>
#include <QQmlContext>
#include <QDir>
#include "VideoBackend.h"

int main(int argc, char *argv[])
{
    // 设置 OpenGL 后端，这对 GStreamer 兼容性有帮助
    qputenv("QSG_RHI_BACKEND", "opengl");

    QGuiApplication app(argc, argv);

    // [核心修复]：在程序启动最开始，告诉 GStreamer 插件在哪里
    // 假设你把插件 DLL 都放在了 exe 同级目录下的 "gst-plugins" 文件夹里
    QString appDir = QCoreApplication::applicationDirPath();

    // 设置 GST_PLUGIN_PATH 环境变量
    QString pluginPath = QDir::toNativeSeparators(appDir + "/gst-plugins");
    qputenv("GST_PLUGIN_PATH", pluginPath.toUtf8());

    // 设置 PATH 环境变量 (为了加载依赖的 DLL，如 libglib-2.0-0.dll)
    // 把 exe 所在目录加到 PATH 最前面
    QString currentPath = qgetenv("PATH");
    QString newPath = appDir + ";" + currentPath;
    qputenv("PATH", newPath.toUtf8());

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
