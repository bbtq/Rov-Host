#include "RobotClient.h"
#include <QDebug>
#include <QInputDevice>

RobotClient::RobotClient(QObject *parent) : QObject(parent)
{
    m_socket = new QTcpSocket(this);
    m_timer = new QTimer(this);
    
    // 禁用Nagle算法，降低延迟
    m_socket->setSocketOption(QAbstractSocket::LowDelayOption, 1);

    connect(m_timer, &QTimer::timeout, this, &RobotClient::onTimerTick);
    connect(m_socket, &QTcpSocket::connected, this, [this](){
        emit connectionChanged();
        emit logMessage("Connected to " + m_targetIp);
        // 开始定时发送
        m_timer->start(1000 / m_frequency);
    });
    connect(m_socket, &QTcpSocket::disconnected, this, [this](){
        m_timer->stop();
        emit connectionChanged();
        emit logMessage("Disconnected");
    });
    connect(m_socket, &QTcpSocket::errorOccurred, this, &RobotClient::onSocketError);
}

void RobotClient::connectToServer(const QString &ip, int port)
{
    m_targetIp = ip;
    m_targetPort = port;
    if (m_socket->state() == QAbstractSocket::ConnectedState) m_socket->disconnectFromHost();
    m_socket->connectToHost(ip, port);
}

void RobotClient::disconnectFromServer()
{
    m_socket->disconnectFromHost();
}

void RobotClient::refreshDeviceList()
{
    m_deviceList.clear();

    // 手动添加一个模拟的键盘选项
    m_deviceList << "Keyboard System";

    const auto devices = QInputDevice::devices();
    for (const auto *dev : devices) {
        // 修正部分：不再判断 GameController，而是排除掉一些非交互设备
        // 或者直接全部列出，让用户选择
        QString typeName;
        switch(dev->type()) {
        case QInputDevice::DeviceType::Keyboard: typeName = "Keyboard"; break;
        case QInputDevice::DeviceType::Mouse: typeName = "Mouse"; break;
        case QInputDevice::DeviceType::TouchPad: typeName = "TouchPad"; break;
        default: typeName = "Device"; break;
        }

        // 将设备名称加入列表
        m_deviceList << typeName + ": " + dev->name();
    }

    // 保留调试用的模拟手柄，方便你在没有真实硬件时测试协议
    m_deviceList << "Virtual Gamepad (Demo)";

    emit inputDevicesChanged();
}
void RobotClient::updateInputState(const QString &inputSource, const QString &key, float value)
{
    // 如果需要区分输入源(键盘/手柄)，可以在这里判断 inputSource
    // 这里简单处理，将键名作为唯一索引
    m_currentInputValues[key] = value;
}

void RobotClient::addMapping(const QString &inputKey, const QString &method, const QString &paramKey, float scale)
{
    InputMapping map;
    map.inputKey = inputKey;
    map.method = method;
    map.paramKey = paramKey;
    map.scale = scale;
    m_mappings.append(map);
}

void RobotClient::clearMappings()
{
    m_mappings.clear();
}

bool RobotClient::isConnected() const { return m_socket->state() == QAbstractSocket::ConnectedState; }

int RobotClient::frequency() const { return m_frequency; }

void RobotClient::setFrequency(int hz)
{
    if (hz < 10) hz = 10;
    if (hz > 1000) hz = 1000;
    if (m_frequency == hz) return;
    
    m_frequency = hz;
    if (m_timer->isActive()) {
        m_timer->start(1000 / m_frequency);
    }
    emit frequencyChanged();
}

QStringList RobotClient::inputDevices() const { return m_deviceList; }

void RobotClient::onSocketError(QAbstractSocket::SocketError socketError)
{
    emit logMessage("Socket Error: " + m_socket->errorString());
}

// 组装JSON-RPC并加上HTTP头
// void RobotClient::onTimerTick()
// {
//     if (m_socket->state() != QAbstractSocket::ConnectedState) return;

//     // 1. 根据映射和当前输入状态构建 params
//     QMap<QString, QJsonObject> methodsMap;

//     for (const auto &map : m_mappings) {
//         float val = 0.0f;
//         if (m_currentInputValues.contains(map.inputKey)) {
//             val = m_currentInputValues[map.inputKey] * map.scale;
//         }

//         // 获取或创建 method 对应的 params 对象
//         QJsonObject params = methodsMap.value(map.method);
        
//         // 处理特殊逻辑：比如 set_depth_locked 需要布尔值
//         if (map.method == "set_depth_locked") {
//              // 示例中的特殊处理：如果是一维数组形式 [false]
//              // 这里为了通用性，我们暂且按 Key-Value 存，最后特殊处理
//              // 或者根据 paramKey 是否为空来判断
//         }
        
//         // 写入值
//         // 注意：示例中 set_depth_locked 是数组，move 是对象。
//         // 为了简化，这里演示 "move" 类型的对象参数构建
//         params.insert(map.paramKey, val);
        
//         methodsMap.insert(map.method, params);
//     }

//     // 2. 构建 JSON-RPC Batch 数组
//     QJsonArray batchArray;
//     int idCounter = 1;

//     // 按照示例硬编码构建结构，或者遍历 methodsMap 动态构建
//     // 这里为了匹配你的示例报文结构，我们做混合处理
    
//     // Method: move
//     if (methodsMap.contains("move")) {
//         QJsonObject req;
//         req["jsonrpc"] = "2.0";
//         req["id"] = idCounter++;
//         req["method"] = "move";
//         req["params"] = methodsMap["move"];
//         batchArray.append(req);
//     }

//     // Method: set_depth_locked (示例中是数组参数，特殊处理演示)
//     // 假设我们有一个映射是 "Btn_X" -> "set_depth_locked"
//     float depthVal = m_currentInputValues.value("Btn_X", 0.0);
//     QJsonObject reqLock;
//     reqLock["jsonrpc"] = "2.0";
//     reqLock["id"] = idCounter++;
//     reqLock["method"] = "set_depth_locked";
//     QJsonArray paramsArr;
//     paramsArr.append(depthVal > 0.5); // 大于0.5视为true
//     reqLock["params"] = paramsArr;
//     batchArray.append(reqLock);

//     QJsonDocument doc(batchArray);
//     QByteArray jsonBody = doc.toJson(QJsonDocument::Compact);

void RobotClient::onTimerTick()
{
    if (m_socket->state() != QAbstractSocket::ConnectedState) return;

    // 1. 遍历映射表，根据最新的输入值构建各方法的参数对象
    QMap<QString, QJsonObject> methodsMap;
    for (const auto &map : m_mappings) {
        float val = 0.0f;
        if (m_currentInputValues.contains(map.inputKey)) {
            val = m_currentInputValues[map.inputKey] * map.scale;
        }

        // 获取该方法对应的 Json 对象（如果不存在则新建）
        QJsonObject params = methodsMap.value(map.method);
        params.insert(map.paramKey, val); // 插入参数，如 "x": 0.5
        methodsMap.insert(map.method, params);
    }

    // 2. 构建 JSON-RPC Batch 数组
    QJsonArray batchArray;
    int idCounter = 1;

    // 遍历所有待发送的方法（包含 move, set_depth_locked 等）
    auto it = methodsMap.constBegin();
    while (it != methodsMap.constEnd()) {
        QJsonObject req;
        req["jsonrpc"] = "2.0";
        req["id"] = idCounter++;
        req["method"] = it.key();   // 这里的 key 就是 "move"
        req["params"] = it.value(); // 这里的 value 就是包含 x,y,rot,z 的对象
        batchArray.append(req);
        ++it;
    }

    // 3. 序列化并发送报文 (保持原有 HTTP 封装逻辑不变)
    QJsonDocument doc(batchArray);
    QByteArray jsonBody = doc.toJson(QJsonDocument::Compact);

    // 3. 构建 HTTP 报文
    // 注意：Content-Length 必须精确
    QByteArray httpPacket;
    httpPacket.append("POST / HTTP/1.1\r\n");
    httpPacket.append("Content-Type: application/json\r\n");
    httpPacket.append("Accept: application/json\r\n");
    httpPacket.append("Host: " + m_targetIp.toUtf8() + ":" + QByteArray::number(m_targetPort) + "\r\n");
    httpPacket.append("Content-Length: " + QByteArray::number(jsonBody.size()) + "\r\n");
    httpPacket.append("\r\n"); // HTTP头结束
    httpPacket.append(jsonBody);

    // 4. 发送
    m_socket->write(httpPacket);
    // m_socket->flush(); // LowDelayOption 下通常不需要频繁flush，但在高频下可确保写入
}
