import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
// 引入我们的C++类（需要在main.cpp中注册）
import MyRobot 1.0

ApplicationWindow {
    width: 800
    height: 600
    visible: true
    title: "机器人多功能控制台"

    RobotClient {
        id: client
        onLogMessage: (msg) => logArea.append(msg)
        Component.onCompleted: {
                    // 1. 配置映射关系：手柄 Key -> RPC方法 -> 参数名 -> 缩放比例
                    // 注意：手柄的 Y 轴在 SDL 中通常向上为负，所以这里 scale 设为 -1.0 来翻转
                    client.addMapping("joy_lx", "move", "x", 1.0)
                    client.addMapping("joy_ly", "move", "y", -1.0)   // 对应 ly -> y
                    client.addMapping("joy_rx", "move", "rot", 1.0) // 对应 rx -> rot
                    client.addMapping("joy_ry", "move", "z", -1.0)   // 对应 ry -> z
        }
    }

    // 2. 监听手柄数据变化并同步给客户端
    Connections {
        target: Backend
        function onAxisChanged() {
            client.updateInputState("gamepad", "joy_lx", Backend.leftStickX)
            client.updateInputState("gamepad", "joy_ly", Backend.leftStickY)
            client.updateInputState("gamepad", "joy_rx", Backend.rightStickX)
            client.updateInputState("gamepad", "joy_ry", Backend.rightStickY)
        }
    }

    // // 捕获键盘输入 (作为全局输入源之一)
    // Item {
    //     id: keyboardListener
    //     focus: true
    //     Keys.onPressed: (event) => {
    //         if (inputSourceGroup.checkedButton.text === "Keyboard") {
    //             handleKey(event, 1.0)
    //             event.accepted = true
    //         }
    //     }
    //     Keys.onReleased: (event) => {
    //         if (inputSourceGroup.checkedButton.text === "Keyboard") {
    //             handleKey(event, 0.0)
    //             event.accepted = true
    //         }
    //     }

    //     function handleKey(event, value) {
    //         let keyName = ""
    //         if (event.key === Qt.Key_W) keyName = "W"
    //         else if (event.key === Qt.Key_S) keyName = "S"
    //         else if (event.key === Qt.Key_A) keyName = "A"
    //         else if (event.key === Qt.Key_D) keyName = "D"
    //         else if (event.key === Qt.Key_Space) keyName = "Space"

    //         if (keyName !== "") {
    //             // 发送给C++后端
    //             client.updateInputState("Keyboard", keyName, value)
    //         }
    //     }
    // }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 10
        spacing: 10

        // --- 1. 连接配置区域 ---
        GroupBox {
            title: "网络连接 (JSON-RPC over TCP)"
            Layout.fillWidth: true
            RowLayout {
                TextField { id: ipField; text: "192.168.137.219"; placeholderText: "IP Address" }
                TextField { id: portField; text: "8888"; placeholderText: "Port"; inputMethodHints: Qt.ImhDigitsOnly; Layout.preferredWidth: 80 }
                Button {
                    text: client.isConnected ? "Disconnect" : "Connect"
                    highlighted: !client.isConnected
                    onClicked: {
                        if (client.isConnected) client.disconnectFromServer()
                        else client.connectToServer(ipField.text, parseInt(portField.text))
                    }
                }
                Label { text: client.isConnected ? "🟢 Online" : "🔴 Offline"; color: client.isConnected ? "green" : "red" }
            }
        }

        // --- 2. 频率控制 ---
        RowLayout {
            Label { text: "发送频率: " + freqSlider.value + " Hz" }
            Slider {
                id: freqSlider
                from: 1; to: 100; stepSize: 1
                value: 15
                Layout.fillWidth: true
                onValueChanged: client.frequency = value
            }
        }

        // // --- 3. 输入源选择与设备列表 (热插拔) ---
        // GroupBox {
        //     title: "输入源配置"
        //     Layout.fillWidth: true

        //     ColumnLayout {
        //         RowLayout {
        //             ButtonGroup { id: inputSourceGroup }
        //             RadioButton { text: "Keyboard"; checked: true; ButtonGroup.group: inputSourceGroup }
        //             RadioButton { text: "Gamepad"; ButtonGroup.group: inputSourceGroup }

        //             Item { Layout.fillWidth: true } // Spacer

        //             Button {
        //                 text: "展开/刷新设备列表"
        //                 onClicked: {
        //                     client.refreshDeviceList()
        //                     devicePopup.open()
        //                 }
        //             }
        //         }

        //         Text {
        //             text: "当前选中: " + inputSourceGroup.checkedButton.text
        //             font.italic: true
        //             color: "gray"
        //         }
        //     }
        // }

        Rectangle {
            id: topBar
            width: parent.width
            height: 60
            color: "#333"
            z: 10

            RowLayout {
                anchors.fill: parent
                anchors.margins: 10
                spacing: 15

                // --- 模式切换按钮 ---
                TabBar {
                    id: modeBar
                    Layout.preferredWidth: 200
                    currentIndex: Backend.inputMode
                    onCurrentIndexChanged: Backend.inputMode = currentIndex

                    TabButton { text: "🎮 Gamepad" }
                    TabButton { text: "⌨️ Keyboard" }
                }

                // 垂直分割线
                Rectangle { width: 1; height: 30; color: "#555" }

                // --- 手柄模式下才显示的控件 ---
                RowLayout {
                    visible: Backend.inputMode === 0 // 仅在手柄模式显示
                    spacing: 10

                    ComboBox {
                        id: deviceCombo
                        model: Backend.deviceList
                        currentIndex: Backend.currentDeviceIndex
                        onActivated: (index) => Backend.currentDeviceIndex = index
                        Layout.preferredWidth: 200
                    }

                    Button {
                        text: "🔄"
                        onClicked: Backend.refreshDevices()
                        ToolTip.visible: hovered
                        ToolTip.text: "Refresh Devices"
                    }

                    Button {
                        text: "⚙️"
                        onClicked: settingsPopup.open()
                    }
                }

                // 占位符
                Item { Layout.fillWidth: true }
            }
        }

        // --- 设置弹窗 ---
        Popup {
            id: settingsPopup
            parent: Overlay.overlay
            x: Math.round((parent.width - width) / 2)
            y: Math.round((parent.height - height) / 2)
            width: 300
            height: 200
            modal: true
            focus: true
            padding: 20

            background: Rectangle {
                color: "#444"
                border.color: "#666"
                radius: 10
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 20

                Text {
                    text: "Settings"
                    color: "white"
                    font.pointSize: 14
                    font.bold: true
                    Layout.alignment: Qt.AlignHCenter
                }

                // 4. 频率设置
                RowLayout {
                    Layout.fillWidth: true
                    Text { text: "Poll Rate (ms):"; color: "#ddd" }

                    Slider {
                        id: rateSlider
                        from: 1
                        to: 100
                        value: Backend.pollingInterval
                        stepSize: 1
                        Layout.fillWidth: true
                        onMoved: Backend.pollingInterval = value
                    }
                    Text { text: rateSlider.value + " ms"; color: "white"; width: 40 }
                }

                Text {
                    text: "Lower ms = Higher CPU usage\nHigher ms = More lag"
                    color: "#888"
                    font.pixelSize: 10
                }

                Button {
                    text: "Close"
                    Layout.alignment: Qt.AlignHCenter
                    onClicked: settingsPopup.close()
                }
            }
        }

        // --- 4. 映射配置 (示例：W -> move.x) ---
        // GroupBox {
        //     title: "输入映射 (Method & Params)"
        //     Layout.fillWidth: true
        //     Layout.fillHeight: true

        //     ColumnLayout {
        //         RowLayout {
        //             Button {
        //                 text: "应用默认映射 (W/S/A/D)"
        //                 onClicked: {
        //                     client.clearMappings()
        //                     // 实际需要更复杂的逻辑处理按键对轴的模拟，这里做简化演示
        //                     client.addMapping("lx", "move", "x", 1.0)
        //                     client.addMapping("ly", "move", "y", 1.0)
        //                     client.addMapping("rx", "move", "rot", 1.0)
        //                     client.addMapping("ry", "move", "z", 1.0)
        //                     // client.addMapping("Space", "set_depth_locked", "", 1.0)
        //                     logArea.append("默认映射已应用")
        //                 }
        //             }
        //         }

        //         TextArea {
        //             text: "Mapping logic is handled in C++. \nW/S -> move.x\nA/D -> move.y\nSpace -> depth_lock"
        //             readOnly: true
        //             background: Rectangle { color: "#eee" }
        //         }
        //     }
        // }

        // --- 日志区域 ---
        ScrollView {
            Layout.fillWidth: true
            Layout.preferredHeight: 150
            TextArea {
                id: logArea
                readOnly: true
                text: "System Ready...\n"
                color: "#333"
            }
        }
    }

    // // 设备列表弹窗
    // Popup {
    //     id: devicePopup
    //     width: 300
    //     height: 200
    //     modal: true
    //     anchors.centerIn: parent

    //     ColumnLayout {
    //         anchors.fill: parent
    //         anchors.margins: 10
    //         Label { text: "可用设备列表"; font.bold: true }

    //         ListView {
    //             Layout.fillWidth: true
    //             Layout.fillHeight: true
    //             model: client.inputDevices
    //             delegate: ItemDelegate {
    //                 text: modelData
    //                 width: parent.width
    //                 onClicked: {
    //                     logArea.append("Selected Device: " + modelData)
    //                     devicePopup.close()
    //                 }
    //             }
    //         }

    //         Button {
    //             text: "刷新"
    //             Layout.alignment: Qt.AlignHCenter
    //             onClicked: client.refreshDeviceList()
    //         }
    //     }
    // }

    // 确保键盘焦点在窗口
    Component.onCompleted: keyboardListener.forceActiveFocus()
}
