#ifndef ROBOTCLIENT_H
#define ROBOTCLIENT_H

#include <QObject>
#include <QTcpSocket>
#include <QTimer>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>
#include <QInputDevice> // Qt6 输入设备管理
#include <QFile>
#include <QStandardPaths>
#include <QVariantMap>
#include <QSettings> // 新增：用于保存上次路径

// 定义映射规则结构体
struct InputMapping {
    QString inputKey;   // 例如 "Key_W", "Axis_Left_X"
    QString method;     // JSON-RPC method, 例如 "move"
    QString paramKey;   // 参数名, 例如 "x"
    float scale;        // 缩放比例
    bool isTrigger;     // 是否是开关量
};

class RobotClient : public QObject
{
    Q_OBJECT
    Q_PROPERTY(bool isConnected READ isConnected NOTIFY connectionChanged)
    Q_PROPERTY(int frequency READ frequency WRITE setFrequency NOTIFY frequencyChanged)
    Q_PROPERTY(QStringList inputDevices READ inputDevices NOTIFY inputDevicesChanged)
    Q_PROPERTY(QVariantMap sensorData READ sensorData NOTIFY sensorDataChanged)
    // 新增：是否显示按键监控
    Q_PROPERTY(bool showInputMonitor READ showInputMonitor WRITE setShowInputMonitor NOTIFY showInputMonitorChanged)
    // 新增：用于映射编辑器的模型属性
    Q_PROPERTY(QVariantList qmlMappings READ qmlMappings WRITE setQmlMappings NOTIFY mappingsChanged)

public:
    explicit RobotClient(QObject *parent = nullptr);

    Q_INVOKABLE void connectToServer(const QString &ip, int port);
    Q_INVOKABLE void disconnectFromServer();
    Q_INVOKABLE void refreshDeviceList();
    
    // 更新输入状态 (供QML调用)
    Q_INVOKABLE void updateInputState(const QString &inputSource, const QString &key, float value);
    
    // 添加映射规则 (供QML配置使用)
    Q_INVOKABLE void addMapping(const QString &inputKey, const QString &method, const QString &paramKey, float scale);
    Q_INVOKABLE void clearMappings();

    // 新增：导出当前映射到 JSON 文件
    Q_INVOKABLE void exportConfig(const QString &filePath);
    // 新增：从 JSON 文件导入映射（返回是否成功）
    Q_INVOKABLE bool importConfig(const QString &filePath);
    // 新增：获取默认配置文件路径（如程序目录下 config.json）
    Q_INVOKABLE QString getDefaultConfigPath();

    QVariantMap sensorData() const { return m_sensorData; }

    bool showInputMonitor() const { return m_showInputMonitor; }
    void setShowInputMonitor(bool show) {
        if (m_showInputMonitor != show) {
            m_showInputMonitor = show;
            emit showInputMonitorChanged();
        }
    }

    bool isConnected() const;
    int frequency() const;
    void setFrequency(int hz);
    QStringList inputDevices() const;

    // 新增：属性访问器
    QVariantList qmlMappings() const;
    void setQmlMappings(const QVariantList &list);

    // 修改/新增：配置持久化辅助函数
    Q_INVOKABLE void saveLastConfigPath(const QString &path);
    Q_INVOKABLE QString getLastConfigPath();
    Q_INVOKABLE void saveCurrentConfig(); // 快捷保存到当前加载的路径

signals:
    void connectionChanged();
    void frequencyChanged();
    void inputDevicesChanged();
    void logMessage(const QString &msg); // 用于UI显示日志
    void sensorDataChanged();
    void showInputMonitorChanged();
    void mappingsChanged();

private slots:
    void onTimerTick();
    void onSocketError(QAbstractSocket::SocketError socketError);
    void onReadyRead(); // 新增：处理下位机回传

private:
    QTcpSocket *m_socket;
    QTimer *m_timer;
    int m_frequency = 10; // 默认10Hz
    QElapsedTimer m_getInfoTimer;
    QString m_targetIp;
    int m_targetPort;
    bool isParamsActive(const QJsonValue &val);

    // 存储当前所有输入的最新的值 "Key_W" -> 1.0
    QMap<QString, float> m_currentInputValues;
    QMap<QString, float> m_lastInputValues; // 新增：用于检测边沿
    QMap<QString, bool> m_toggleStates;     // 新增：用于存储 btn_status 的开关状态
    // 新增：记录上一次发送给服务器的各个方法的参数快照
    QMap<QString, QJsonValue> m_lastMethodsMap;
    QMap<QString, bool> m_functionStates;
    QVariantMap m_sensorData; //存储解析后的数据
    bool m_showInputMonitor = true; // 默认开启
    
    // 存储映射规则
    QList<InputMapping> m_mappings;

    // 模拟的设备列表
    QStringList m_deviceList;

    QByteArray buildPacket();

    QString m_currentConfigPath; // 记录当前加载的文件路径
};

#endif // ROBOTCLIENT_H
