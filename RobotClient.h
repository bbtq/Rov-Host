#ifndef ROBOTCLIENT_H
#define ROBOTCLIENT_H

#include <QObject>
#include <QTcpSocket>
#include <QTimer>
#include <QJsonObject>
#include <QJsonArray>
#include <QJsonDocument>
#include <QInputDevice> // Qt6 输入设备管理

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

    bool isConnected() const;
    int frequency() const;
    void setFrequency(int hz);
    QStringList inputDevices() const;

signals:
    void connectionChanged();
    void frequencyChanged();
    void inputDevicesChanged();
    void logMessage(const QString &msg); // 用于UI显示日志

private slots:
    void onTimerTick();
    void onSocketError(QAbstractSocket::SocketError socketError);

private:
    QTcpSocket *m_socket;
    QTimer *m_timer;
    int m_frequency = 50; // 默认50Hz
    QString m_targetIp;
    int m_targetPort;

    // 存储当前所有输入的最新的值 "Key_W" -> 1.0
    QMap<QString, float> m_currentInputValues;
    
    // 存储映射规则
    QList<InputMapping> m_mappings;

    // 模拟的设备列表
    QStringList m_deviceList;

    QByteArray buildPacket();
};

#endif // ROBOTCLIENT_H