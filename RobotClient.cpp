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
    m_lastMethodsMap.clear(); // 新增
}

// 获取默认路径：建议放在可执行文件同级目录
QString RobotClient::getDefaultConfigPath() {
    return QCoreApplication::applicationDirPath() + "/robot_config.json";
}

void RobotClient::exportConfig(const QString &filePath) {
    QString path = filePath;
    if (path.startsWith("file:///")) path = QUrl(filePath).toLocalFile(); // 处理QML传来的URL

    QJsonArray rootArray;
    for (const auto &map : m_mappings) {
        QJsonObject obj;
        obj["inputKey"] = map.inputKey;
        obj["method"] = map.method;
        obj["paramKey"] = map.paramKey;
        obj["scale"] = map.scale;
        rootArray.append(obj);
    }

    QJsonDocument doc(rootArray);
    QFile file(path);
    if (file.open(QIODevice::WriteOnly)) {
        file.write(doc.toJson());
        file.close();
        emit logMessage("配置已导出至: " + path);
    }
}

bool RobotClient::importConfig(const QString &filePath) {
    QString path = filePath;
    if (path.startsWith("file:///")) path = QUrl(filePath).toLocalFile();

    QFile file(path);
    if (!file.open(QIODevice::ReadOnly)) return false;

    QByteArray data = file.readAll();
    QJsonDocument doc = QJsonDocument::fromJson(data);
    if (!doc.isArray()) return false;

    clearMappings(); // 导入前清空旧映射
    QJsonArray array = doc.array();
    for (int i = 0; i < array.size(); ++i) {
        QJsonObject obj = array[i].toObject();
        addMapping(
            obj["inputKey"].toString(),
            obj["method"].toString(),
            obj["paramKey"].toString(),
            obj["scale"].toDouble()
            );
    }
    emit logMessage("成功导入配置: " + path);
    return true;
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

// 辅助函数：判断参数是否处于“活跃”状态（非零）
bool RobotClient::isParamsActive(const QJsonValue &val)
{
    if (val.isObject()) {
        QJsonObject obj = val.toObject();
        for (auto v : obj) {
            if (std::abs(v.toDouble()) > 0.00001) return true; // 只要有一个分量不是0，就视为活跃
        }
    } else if (val.isArray()) {
        QJsonArray arr = val.toArray();
        if (!arr.isEmpty()) {
            // 对于 btn_value，判断数值是否非0；对于 btn_status(bool)，始终视为活跃以确保状态同步
            if (arr[0].isBool()) return false; // status类型仍走“仅变化发送”逻辑
            if (std::abs(arr[0].toDouble()) > 0.00001) return true;
        }
    }
    return false;
}

void RobotClient::onTimerTick()
{
    if (m_socket->state() != QAbstractSocket::ConnectedState) return;

    // --- 第一步：聚合所有映射的数值 ---
    // 使用嵌套 Map 存储聚合结果：Method -> (ParamKey -> 累加后的数值)
    QMap<QString, QMap<QString, double>> aggregatedParams;
    // 记录哪些方法属于“直接数据”模式 (btn_status / btn_value)
    QSet<QString> directMethods;

    for (const auto &map : m_mappings) {
        float currentVal = m_currentInputValues.value(map.inputKey, 0.0f);
        float lastVal = m_lastInputValues.value(map.inputKey, 0.0f);

        if (map.paramKey == "btn_status") {
            // 处理切换逻辑：检测上升沿（刚刚按下）
            if (currentVal > 0.5f && lastVal <= 0.5f) {
                m_toggleStates[map.inputKey] = !m_toggleStates.value(map.inputKey, false);
            }
            // 状态同步：只要该 inputKey 的切换状态为真，就记录为 1.0
            aggregatedParams[map.method][map.paramKey] = m_toggleStates.value(map.inputKey, false) ? 1.0 : 0.0;
            directMethods.insert(map.method);
        } else {
            // 标准数值或 btn_value：执行累加
            // 例如：W 贡献 +1.0，S 贡献 -1.0，两者都按结果为 0
            aggregatedParams[map.method][map.paramKey] += (currentVal * map.scale);
            if (map.paramKey == "btn_value") directMethods.insert(map.method);
        }
    }

    // 更新“上一时刻”值，供下次 Tick 检测上升沿
    m_lastInputValues = m_currentInputValues;

    // --- 第二步：将聚合后的数据转换为 JSON 结构 ---
    QMap<QString, QJsonValue> methodsMap;
    for (auto methodIt = aggregatedParams.begin(); methodIt != aggregatedParams.end(); ++methodIt) {
        QString methodName = methodIt.key();
        const auto &paramsGroup = methodIt.value();

        if (directMethods.contains(methodName)) {
            // 直接数据模式：取第一个分量的值生成数组
            QJsonArray arr;
            double finalVal = paramsGroup.begin().value();
            if (paramsGroup.begin().key() == "btn_status") arr.append(finalVal > 0.5);
            else arr.append(finalVal);
            methodsMap[methodName] = arr;
        } else {
            // 对象模式：构建包含 x, y, rot, z 等键值的对象
            QJsonObject obj;
            for (auto pIt = paramsGroup.begin(); pIt != paramsGroup.end(); ++pIt) {
                obj.insert(pIt.key(), pIt.value());
            }
            methodsMap[methodName] = obj;
        }
    }

    // --- 第三步：构建 Batch 数组并发送 ---
    QJsonArray batchArray;
    int idCounter = 1;

    // 1. 固定发送 get_info
    QJsonObject getInfoReq;
    getInfoReq["jsonrpc"] = "2.0";
    getInfoReq["id"] = idCounter++;
    getInfoReq["method"] = "get_info";
    batchArray.append(getInfoReq);

    // 2. 根据变化或活跃状态添加方法
    for (auto it = methodsMap.constBegin(); it != methodsMap.constEnd(); ++it) {
        QString method = it.key();
        QJsonValue currentParams = it.value();

        bool changed = (!m_lastMethodsMap.contains(method) || m_lastMethodsMap[method] != currentParams);
        bool active = isParamsActive(currentParams);

        if (changed || active) {
            QJsonObject req;
            req["jsonrpc"] = "2.0";
            req["id"] = idCounter++;
            req["method"] = method;
            req["params"] = currentParams;
            batchArray.append(req);
        }
    }

    // --- 第三步：状态更新与发送 ---

    // 更新缓存，用于下一次 Tick 时的对比
    m_lastMethodsMap = methodsMap;
    m_lastInputValues = m_currentInputValues;

    QJsonDocument doc(batchArray);
    QByteArray jsonBody = doc.toJson(QJsonDocument::Compact);

    // 构建 HTTP 报文 (与你源代码一致)
    QByteArray httpPacket;
    httpPacket.append("POST / HTTP/1.1\r\n");
    httpPacket.append("Content-Type: application/json\r\n");
    httpPacket.append("Accept: application/json\r\n");
    httpPacket.append("Host: " + m_targetIp.toUtf8() + ":" + QByteArray::number(m_targetPort) + "\r\n");
    httpPacket.append("Content-Length: " + QByteArray::number(jsonBody.size()) + "\r\n");
    httpPacket.append("\r\n");
    httpPacket.append(jsonBody);

    m_socket->write(httpPacket);
}
