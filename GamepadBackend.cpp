#include "GamepadBackend.h"
#include <QDebug>
#include <QCoreApplication>
#include <QKeyEvent>
#include <QMetaEnum>

GamepadBackend::GamepadBackend(QObject *parent)
    : QObject(parent)
{
    // 初始化 SDL 游戏控制器子系统
    if (SDL_Init(SDL_INIT_GAMECONTROLLER) < 0) {
        qWarning() << "SDL could not initialize! SDL Error:" << SDL_GetError();
    }

    m_timer = new QTimer(this);
    connect(m_timer, &QTimer::timeout, this, &GamepadBackend::poll);
    
    // 默认频率 16ms (约60Hz)
    m_timer->start(16);
    
    // 启动时自动刷新一次
    refreshDevices();

    // --- 关键修改：安装全局事件过滤器 ---
    // 这允许我们在 C++ 层拦截整个应用程序的键盘事件
    QCoreApplication::instance()->installEventFilter(this);
}

GamepadBackend::~GamepadBackend()
{
    if (m_controller) {
        SDL_GameControllerClose(m_controller);
    }
    SDL_Quit();
}

void GamepadBackend::refreshDevices()
{
    // SDL 需要更新事件泵才能检测到新设备
    SDL_PumpEvents();

    // 如果当前有连接，先关闭
    if (m_controller) {
        SDL_GameControllerClose(m_controller);
        m_controller = nullptr;
        emit connectedChanged();
    }

    m_deviceNames.clear();
    m_joystickIndices.clear();

    int numJoysticks = SDL_NumJoysticks();
    for (int i = 0; i < numJoysticks; ++i) {
        if (SDL_IsGameController(i)) {
            // 获取具体的设备名称 (例如 "PS5 Controller")
            const char* name = SDL_GameControllerNameForIndex(i);
            m_deviceNames.append(name ? QString::fromUtf8(name) : "Unknown Gamepad");
            m_joystickIndices.push_back(i);
        }
    }

    emit deviceListChanged();

    // 如果列表不为空，默认选中第一个
    if (!m_deviceNames.isEmpty()) {
        setCurrentDeviceIndex(0);
    } else {
        m_currentIndex = -1;
        emit currentDeviceIndexChanged();
    }
}

void GamepadBackend::setCurrentDeviceIndex(int index)
{
    if (index < 0 || index >= m_joystickIndices.size()) return;
    if (m_currentIndex == index && m_controller) return;

    if (m_controller) {
        SDL_GameControllerClose(m_controller);
        m_controller = nullptr;
    }

    m_currentIndex = index;
    // 打开指定的设备
    m_controller = SDL_GameControllerOpen(m_joystickIndices[index]);

    if (m_controller) {
        qDebug() << "Opened gamepad:" << m_deviceNames[index];
    } else {
        qWarning() << "Could not open gamepad:" << SDL_GetError();
    }

    emit currentDeviceIndexChanged();
    emit connectedChanged();
}

void GamepadBackend::setPollingInterval(int ms)
{
    if (ms < 1) ms = 1;
    if (m_timer->interval() != ms) {
        m_timer->setInterval(ms);
        emit pollingIntervalChanged();
    }
}

void GamepadBackend::setInputMode(int mode)
{
    if (m_inputMode == mode) return;
    m_inputMode = mode;

    // 如果切换到键盘模式，可以选择暂停 SDL 轮询以节省资源
    if (m_inputMode == 1) {
        m_timer->stop();
    } else {
        m_timer->start();
    }

    // 清空状态
    m_activeKeys.clear();
    emit pressedKeysChanged();
    emit inputModeChanged();
}

QString GamepadBackend::pressedKeysString() const
{
    QStringList names;
    // 使用 QMetaEnum 获取按键名称
    QMetaEnum metaEnum = QMetaEnum::fromType<Qt::Key>();

    for (int key : m_activeKeys) {
        const char* keyName = metaEnum.valueToKey(key);
        if (keyName) {
            names.append(QString(keyName).replace("Key_", "")); // 去掉 "Key_" 前缀
        } else {
            names.append(QString::number(key));
        }
    }
    return names.join(" + ");
}

// 2. 在 eventFilter() 中处理键盘触发：
bool GamepadBackend::eventFilter(QObject *watched, QEvent *event) {
    if (m_inputMode == 1) { // 键盘模式
        if (event->type() == QEvent::KeyPress || event->type() == QEvent::KeyRelease) {
            QKeyEvent *keyEvent = static_cast<QKeyEvent*>(event);
            if (!keyEvent->isAutoRepeat()) {
                bool isPressed = (event->type() == QEvent::KeyPress);
                QMetaEnum metaEnum = QMetaEnum::fromType<Qt::Key>();
                const char* keyName = metaEnum.valueToKey(keyEvent->key());

                if (keyName) {
                    QString inputKey = "key_" + QString(keyName).replace("Key_", "");
                    if (isPressed) m_activeKeys.insert(keyEvent->key());
                    else m_activeKeys.remove(keyEvent->key());

                    emit pressedKeysChanged();
                    // 发送给 RobotClient
                    emit inputTriggered("keyboard", inputKey, isPressed ? 1.0 : 0.0);
                }
            }
            return true;
        }
    }
    return QObject::eventFilter(watched, event);
}

double GamepadBackend::normalizeAxis(Sint16 val) {
    // SDL 轴范围 -32768 到 32767
    const int deadzone = 2000; // 简单死区
    if (std::abs(val) < deadzone) return 0.0;
    return val / 32768.0; 
}

void GamepadBackend::poll()
{
    // 必须调用此函数更新 SDL 内部状态
    SDL_GameControllerUpdate();

    if (!m_controller || !SDL_GameControllerGetAttached(m_controller)) {
        // 如果物理断开连接
        if (m_controller) {
             SDL_GameControllerClose(m_controller);
             m_controller = nullptr;
             emit connectedChanged();
             // 自动尝试刷新列表
             refreshDevices();
        }
        return;
    }

    // 读取轴
    double lx = normalizeAxis(SDL_GameControllerGetAxis(m_controller, SDL_CONTROLLER_AXIS_LEFTX));
    double ly = normalizeAxis(SDL_GameControllerGetAxis(m_controller, SDL_CONTROLLER_AXIS_LEFTY));
    double rx = normalizeAxis(SDL_GameControllerGetAxis(m_controller, SDL_CONTROLLER_AXIS_RIGHTX));
    double ry = normalizeAxis(SDL_GameControllerGetAxis(m_controller, SDL_CONTROLLER_AXIS_RIGHTY));
    // 扳机 0-32767 -> 0-1
    double lt = SDL_GameControllerGetAxis(m_controller, SDL_CONTROLLER_AXIS_TRIGGERLEFT) / 32767.0;
    double rt = SDL_GameControllerGetAxis(m_controller, SDL_CONTROLLER_AXIS_TRIGGERRIGHT) / 32767.0;

    if (lx != m_lx) { m_lx = lx; emit inputTriggered("gamepad", "joy_lx", lx); }
    if (ly != m_ly) { m_ly = ly; emit inputTriggered("gamepad", "joy_ly", ly); }
    if (rx != m_rx) { m_rx = rx; emit inputTriggered("gamepad", "joy_rx", rx); }
    if (ry != m_ry) { m_ry = ry; emit inputTriggered("gamepad", "joy_ry", ry); }
    if (lt != m_lt) { m_lt = lt; emit inputTriggered("gamepad", "joy_lt", lt); }
    if (rt != m_rt) { m_rt = rt; emit inputTriggered("gamepad", "joy_rt", rt); }



    // 读取按键 (这里为了演示简单，合成一个 int，实际项目可以用 QMap 或多个 bool)
//     int currentButtons = 0;
//     for (int i = 0; i < SDL_CONTROLLER_BUTTON_MAX; ++i) {
//         if (SDL_GameControllerGetButton(m_controller, (SDL_GameControllerButton)i)) {
//             currentButtons |= (1 << i);
//         }
//     }

//     if (currentButtons != m_buttons) {
//         m_buttons = currentButtons;
//         emit buttonsChanged();
//     }
    QVariantMap currentButtons;
    for (int i = 0; i < SDL_CONTROLLER_BUTTON_MAX; ++i) {
        auto btn = static_cast<SDL_GameControllerButton>(i);
        bool isPressed = SDL_GameControllerGetButton(m_controller, btn);
        const char* name = SDL_GameControllerGetStringForButton(btn);
        if (name) {
            QString keyName = "btn_" + QString::fromUtf8(name);
            currentButtons.insert(keyName, isPressed);
            // 如果状态变了，触发信号
            if (m_buttons.value(keyName).toBool() != isPressed) {
                emit inputTriggered("gamepad", keyName, isPressed ? 1.0 : 0.0);
            }
        }
    }

    // 只有当按键状态发生变化时才发出信号
    if (currentButtons != m_buttons) {
        m_buttons = currentButtons;
        emit buttonsChanged();

        // 调试打印：查看当前按下的按键
        qDebug() << "Buttons State Changed:" << m_buttons;
    }
}
