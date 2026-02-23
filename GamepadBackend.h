#ifndef GAMEPADBACKEND_H
#define GAMEPADBACKEND_H

#include <QObject>
#include <QTimer>
#include <QStringList>
#include <vector>
#include <QSet>
#include <QVariantMap>

// 引入 SDL
#define SDL_MAIN_HANDLED
#include <SDL.h>

class GamepadBackend : public QObject
{
    Q_OBJECT
    // 暴露给 QML 的属性
    Q_PROPERTY(QStringList deviceList READ deviceList NOTIFY deviceListChanged)
    Q_PROPERTY(int currentDeviceIndex READ currentDeviceIndex WRITE setCurrentDeviceIndex NOTIFY currentDeviceIndexChanged)
    Q_PROPERTY(int pollingInterval READ pollingInterval WRITE setPollingInterval NOTIFY pollingIntervalChanged)
    Q_PROPERTY(bool isConnected READ isConnected NOTIFY connectedChanged)

    // 手柄数据
    Q_PROPERTY(double leftStickX READ leftStickX NOTIFY axisChanged)
    Q_PROPERTY(double leftStickY READ leftStickY NOTIFY axisChanged)
    Q_PROPERTY(double rightStickX READ rightStickX NOTIFY axisChanged)
    Q_PROPERTY(double rightStickY READ rightStickY NOTIFY axisChanged)
    Q_PROPERTY(double leftTrigger READ leftTrigger NOTIFY axisChanged)
    Q_PROPERTY(double rightTrigger READ rightTrigger NOTIFY axisChanged)
    // Q_PROPERTY(int buttons READ buttons NOTIFY buttonsChanged) // 使用位掩码传输所有按键
    Q_PROPERTY(QVariantMap buttons READ buttons NOTIFY buttonsChanged)

    // --- 新增：键盘相关属性 ---
    // 0 = Gamepad, 1 = Keyboard
    Q_PROPERTY(int inputMode READ inputMode WRITE setInputMode NOTIFY inputModeChanged)
    // 返回所有当前按下的键码列表
    Q_PROPERTY(QList<int> pressedKeys READ pressedKeys NOTIFY pressedKeysChanged)
    // 为了方便显示，直接返回按键名称字符串
    Q_PROPERTY(QString pressedKeysString READ pressedKeysString NOTIFY pressedKeysChanged)

public:
    explicit GamepadBackend(QObject *parent = nullptr);
    ~GamepadBackend();

    QStringList deviceList() const { return m_deviceNames; }
    
    int currentDeviceIndex() const { return m_currentIndex; }
    void setCurrentDeviceIndex(int index);

    int pollingInterval() const { return m_timer->interval(); }
    void setPollingInterval(int ms);

    bool isConnected() const { return m_controller != nullptr; }

    // 数据读取器
    double leftStickX() const { return m_lx; }
    double leftStickY() const { return m_ly; }
    double rightStickX() const { return m_rx; }
    double rightStickY() const { return m_ry; }
    double leftTrigger() const { return m_lt; }
    double rightTrigger() const { return m_rt; }
    // int buttons() const { return m_buttons; }
    QVariantMap buttons() const { return m_buttons; }

    // 新增 Getter/Setter
    int inputMode() const { return m_inputMode; }
    void setInputMode(int mode);

    QList<int> pressedKeys() const { return m_activeKeys.values(); }
    QString pressedKeysString() const;

public slots:
    void refreshDevices(); // 刷新设备列表

signals:
    void deviceListChanged();
    void currentDeviceIndexChanged();
    void pollingIntervalChanged();
    void connectedChanged();
    void axisChanged();
    void buttonsChanged();

    // 新增 signals
    void inputModeChanged();
    void pressedKeysChanged();

protected:
    // 核心：重写事件过滤器
    bool eventFilter(QObject *watched, QEvent *event) override;

private slots:
    void poll();

private:
    QTimer *m_timer;
    SDL_GameController *m_controller = nullptr;
    
    // 设备管理
    std::vector<int> m_joystickIndices; // 存储 SDL 的设备索引
    QStringList m_deviceNames;
    int m_currentIndex = -1;

    // 缓存数据
    double m_lx=0, m_ly=0, m_rx=0, m_ry=0, m_lt=0, m_rt=0;
    // int m_buttons = 0;
    QVariantMap m_buttons;

    // --- 新增变量 ---
    int m_inputMode = 0; // 0: Gamepad, 1: Keyboard
    QSet<int> m_activeKeys; // 存储当前按下的 Qt::Key

    double normalizeAxis(Sint16 val);
};

#endif // GAMEPADBACKEND_H
