import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import QtMultimedia
// 引入 Labs 模块用于原生文件夹对话框
import Qt.labs.platform 1.1 as Native
import com.mycompany.stream 1.0
import MyRobot 1.0

ApplicationWindow {
    id: window
    width: 1150
    height: 750
    visible: true
    title: "ROV Host"

    // --- 全局状态与配色 ---
    property bool showUI: true // 控制 UI 显示/隐藏的状态
    readonly property color colorBg: "#121212"
    readonly property color colorSurface: "#AA1e1e1e"
    readonly property color colorPrimary: "#00e5ff"
    readonly property color colorText: "#e0e0e0"

    background: Rectangle { color: "black" }

    // --- 后端逻辑组件 ---
    VideoBackend {
        id: videoBackend
        Component.onCompleted: videoBackend.setVideoSink(videoOutput.videoSink)
    }

    RobotClient {
        id: robotClient
        onLogMessage: (msg) => {
            logArea.append("[%1] %2".arg(Qt.formatTime(new Date(), "hh:mm:ss")).arg(msg))
        }
        Component.onCompleted: {
            let defaultPath = robotClient.getDefaultConfigPath()
            if (!robotClient.importConfig(defaultPath)) applyHardcodedDefaults()
        }

        function applyHardcodedDefaults() {
            robotClient.clearMappings()
            robotClient.addMapping("joy_lx", "move", "x", 1.0)
            robotClient.addMapping("joy_ly", "move", "y", -1.0)
            robotClient.addMapping("joy_rx", "move", "rot", 1.0)
            robotClient.addMapping("joy_ry", "move", "z", -1.0)
            robotClient.addMapping("key_W", "move", "y", 1.0)
            robotClient.addMapping("key_S", "move", "y", -1.0)
            robotClient.addMapping("key_A", "move", "x", -1.0)
            robotClient.addMapping("key_D", "move", "x", 1.0)
            robotClient.addMapping("btn_a", "set_depth_locked", "btn_status", 1.0)
            robotClient.addMapping("key_Space", "set_depth_locked", "btn_status", 1.0)
        }
    }

    Connections {
        target: Backend
        function onInputTriggered(source, key, value) {
            robotClient.updateInputState(source, key, value)
        }
    }

    // --- 对话框组件 ---
    Native.FolderDialog {
        id: folderDialog
        title: "选择录制视频保存目录"
        currentFolder: "file:///" + videoBackend.recordPath
        onAccepted: {
            var path = folderDialog.folder.toString();
            path = path.replace(/^(file:\/{3})|(file:\/\/)/, "");
            if (Qt.platform.os === "windows" && path.length > 2 && path[0] === "/" && path[2] === ":") {
                path = path.substring(1);
            }
            videoBackend.recordPath = path
        }
    }

    FileDialog {
        id: importDialog
        title: "选择映射配置文件"
        nameFilters: ["JSON files (*.json)"]
        onAccepted: robotClient.importConfig(selectedFile)
    }

    FileDialog {
        id: exportDialog
        title: "导出配置文件"
        fileMode: FileDialog.SaveFile
        nameFilters: ["JSON files (*.json)"]
        currentFile: "file:///" + robotClient.getDefaultConfigPath()
        onAccepted: robotClient.exportConfig(selectedFile)
    }

    // --- 视频显示区域 ---
    VideoOutput {
        id: videoOutput
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    // --- [新增] UI 切换按钮 ---
    // 采用悬浮半透明设计，确保隐藏后不遮挡视频，仅在边缘显示
    Button {
        id: uiToggleBtn
        z: 200
        anchors.right: parent.right
        anchors.rightMargin: showUI ? 20 : 5
        anchors.verticalCenter: parent.verticalCenter
        width: 36; height: 36

        padding: 0

        // 动态图标：显示/隐藏
        text: showUI ? "H" : "S"

        background: Rectangle {
            radius: 20
            color: showUI ? "#44000000" : "#881e1e1e"
            border.color: "#66ffffff"
            border.width: 1
        }

        contentItem: Text {
            text: uiToggleBtn.text
            font.pixelSize: 18
            anchors.fill: parent
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            color: "white"
        }

        onClicked: showUI = !showUI

        // 鼠标悬停动画
        opacity: hovered ? 1.0 : 0.4
        Behavior on opacity { NumberAnimation { duration: 200 } }
        Behavior on anchors.rightMargin { NumberAnimation { duration: 300; easing.type: Easing.OutQuad } }
    }

    // --- 顶部状态栏 ---
    Rectangle {
        id: topStatusBar
        width: parent.width - 40; height: 55
        // 动态位置逻辑：隐藏时向上滑出屏幕
        y: showUI ? 15 : -height - 20
        anchors.horizontalCenter: parent.horizontalCenter
        color: colorSurface; radius: 10; border.color: "#33ffffff"; z: 100

        // 平滑移动动画
        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors.fill: parent; anchors.leftMargin: 15; anchors.rightMargin: 15; spacing: 15

            RowLayout {
                Rectangle {
                    width: 10; height: 10; radius: 5
                    color: robotClient.isConnected ? "#00c853" : "#ff5252"
                    SequentialAnimation on opacity {
                        running: true; loops: Animation.Infinite
                        NumberAnimation { from: 1; to: 0.4; duration: 800 }
                        NumberAnimation { from: 0.4; to: 1; duration: 800 }
                    }
                }
                Text { text: robotClient.isConnected ? "控制链路已连接" : "未连接机器人"; color: "white"; font.pixelSize: 13 }
            }

            Rectangle { width: 1; height: 25; color: "#44ffffff" }

            TabBar {
                id: modeTabBar; Layout.preferredWidth: 200; currentIndex: Backend.inputMode
                onCurrentIndexChanged: Backend.inputMode = currentIndex
                background: null
                TabButton { text: "🎮 Gamepad"; contentItem: Text { text: parent.text; color: parent.checked ? colorPrimary : "#888"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
                TabButton { text: "⌨️ Keyboard"; contentItem: Text { text: parent.text; color: parent.checked ? colorPrimary : "#888"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter } }
            }

            RowLayout {
                visible: Backend.inputMode === 0
                spacing: 8
                Rectangle { width: 1; height: 25; color: "#44ffffff"; Layout.rightMargin: 5 }
                ComboBox {

                id: deviceCombo

                model: Backend.deviceList

                currentIndex: Backend.currentDeviceIndex

                onActivated: (index) => Backend.currentDeviceIndex = index



                Layout.preferredHeight: 20

                Layout.preferredWidth: 180

                flat: true



                // 设置字体大小

                font.pixelSize: 12



                contentItem: Text {

                text: deviceCombo.displayText

                color: colorPrimary

                verticalAlignment: Text.AlignVCenter

                leftPadding: 10

                font: deviceCombo.font // 继承字体

                }



                // 下拉项高度与主控件一致

                delegate: ItemDelegate {

                width: deviceCombo.width

                height: deviceCombo.Layout.preferredHeight



                contentItem: Text {

                text: modelData

                color: "white" // 黑色背景上的白色文字

                verticalAlignment: Text.AlignVCenter

                leftPadding: 10

                font: deviceCombo.font

                }



                padding: 0

                verticalPadding: 0



                // 鼠标悬停/选中背景色

                background: Rectangle {

                color: parent.highlighted ? "#444" : "transparent"

                }

                }



                // 弹出列表黑色背景

                popup: Popup {

                y: deviceCombo.height

                width: deviceCombo.width

                implicitHeight: contentItem.implicitHeight

                padding: 0



                contentItem: ListView {

                clip: true

                implicitHeight: contentHeight

                model: deviceCombo.popup.visible ? deviceCombo.delegateModel : null

                currentIndex: deviceCombo.highlightedIndex



                ScrollIndicator.vertical: ScrollIndicator {}

                }



                background: Rectangle {

                color: "black" // 黑色背景

                border.color: "#333"

                border.width: 1

                }

                }

                }
                Button {
                    text: "🔄"
                    onClicked: Backend.refreshDevices()
                    background: Rectangle { implicitWidth: 28; implicitHeight: 28; color: parent.pressed ? "#66ffffff" : "#22ffffff"; radius: 4 }
                    contentItem: Text { text: parent.text; color: "white"; horizontalAlignment: Text.AlignHCenter; verticalAlignment: Text.AlignVCenter }
                }
            }

            Item { Layout.fillWidth: true }

            Button {
                text: "＋ 新建窗口"
                flat: true
                Layout.preferredHeight: 32
                contentItem: Text {
                    text: parent.text; color: "#ccc"
                    font.pixelSize: 13; verticalAlignment: Text.AlignVCenter
                }
                onClicked: {
                    var component = Qt.createComponent("Main.qml");
                    if (component.status === Component.Ready) {
                        var newWindow = component.createObject(null);
                        newWindow.show();
                    } else {
                        logArea.append("<font color='red'>窗口创建失败: " + component.errorString() + "</font>")
                    }
                }
            }

            Button {
                text: robotClient.isConnected ? "断开" : "连接"
                onClicked: {
                    if (robotClient.isConnected) robotClient.disconnectFromServer()
                    else controlSettingsPopup.open()
                }
                contentItem: Text { text: parent.text; color: "white"; font.bold: true }
                background: Rectangle { implicitWidth: 70; implicitHeight: 32; radius: 6; color: parent.pressed ? "#444" : (robotClient.isConnected ? "#ff5252" : "#0091ea") }
            }

            Button {
                text: "⚙️ 设置"
                onClicked: controlSettingsPopup.open()
                background: Rectangle { color: "#22ffffff"; radius: 6; implicitWidth: 80; implicitHeight: 32 }
                contentItem: Text { text: parent.text; color: colorPrimary; horizontalAlignment: Text.AlignHCenter }
            }
        }
    }

    // --- 底部视频控制面板 ---
    Rectangle {
        id: videoControlPanel
        width: parent.width - 40; height: 80
        // 动态位置逻辑：隐藏时向下滑出屏幕
        y: showUI ? parent.height - height - 15 : parent.height + 20
        anchors.horizontalCenter: parent.horizontalCenter
        color: colorSurface; radius: 12; border.color: "#33ffffff"

        // 平滑移动动画
        Behavior on y { NumberAnimation { duration: 400; easing.type: Easing.OutQuad } }

        RowLayout {
            anchors.fill: parent; anchors.margins: 12; spacing: 15

            ColumnLayout {
                spacing: 2
                RowLayout {
                    RadioButton { id: rbRtsp; text: "RTSP"; checked: true; contentItem: Text { text: parent.text; color: "white"; leftPadding: 30 } }
                    RadioButton { id: rbCam; text: "USB"; contentItem: Text { text: parent.text; color: "white"; leftPadding: 30 } }
                }
            }

            TextField {
                id: urlField; visible: rbRtsp.checked; Layout.fillWidth: true;
                text: "rtsp://127.0.0.1:8554/live"; color: "white"
                background: Rectangle { color: "#22ffffff"; radius: 6 }
            }

            ComboBox { id: camCombo; visible: rbCam.checked; Layout.fillWidth: true; model: mediaDevices.videoInputs; textRole: "description" }

            ComboBox {
                id: decoderCombo; visible: rbRtsp.checked
                Layout.preferredWidth: 140; Layout.preferredHeight: 32
                model: ["d3d11h265dec", "avdec_h265", "nvh265dec"]
                currentIndex: 0; background: Rectangle { color: "#22ffffff"; radius: 6 }
                contentItem: Text { text: decoderCombo.displayText; color: "#ccc"; verticalAlignment: Text.AlignVCenter; leftPadding: 10; font.pixelSize: 12 }
            }

            RowLayout {
                spacing: 10
                Button {
                    text: videoBackend.isPlaying ? "停止" : "播放"
                    Layout.preferredWidth: 80
                    onClicked: {
                        if (videoBackend.isPlaying) videoBackend.stopVideo()
                        else {
                            if (rbRtsp.checked) videoBackend.startVideo(urlField.text, decoderCombo.currentText, false)
                            else videoBackend.startVideo(camCombo.currentIndex.toString(), "", true)
                        }
                    }
                }
                Button {
                    enabled: videoBackend.isPlaying; text: videoBackend.isRecording ? "停止录制" : "录制视频"
                    highlighted: videoBackend.isRecording; Layout.preferredWidth: 100
                    onClicked: videoBackend.toggleRecording(); palette.highlight: "#ff5252"
                }
            }
        }
    }

    // --- 配置弹窗 (三页结构) ---
    Popup {
        id: controlSettingsPopup
        x: (parent.width - width) / 2; y: (parent.height - height) / 2
        width: 500; height: 550
        modal: true; focus: true
        background: Rectangle { color: "#1e1e1e"; radius: 15; border.color: "#444" }

        ColumnLayout {
            anchors.fill: parent; anchors.margins: 20; spacing: 10
            Text { text: "系统详细配置"; color: colorPrimary; font.pointSize: 14; font.bold: true; Layout.bottomMargin: 5 }

            TabBar {
                id: popupTabBar; Layout.fillWidth: true; background: null
                TabButton { text: "连接与录制"; contentItem: Text { text: parent.text; color: parent.checked ? colorPrimary : "#888"; horizontalAlignment: Text.AlignHCenter } }
                TabButton { text: "控制与映射"; contentItem: Text { text: parent.text; color: parent.checked ? colorPrimary : "#888"; horizontalAlignment: Text.AlignHCenter } }
                TabButton { text: "运行日志"; contentItem: Text { text: parent.text; color: parent.checked ? colorPrimary : "#888"; horizontalAlignment: Text.AlignHCenter } }
            }

            StackLayout {
                id: settingsStack; Layout.fillWidth: true; Layout.fillHeight: true; currentIndex: popupTabBar.currentIndex

                ColumnLayout {
                    spacing: 15
                    GroupBox {
                        title: "服务器连接"; Layout.fillWidth: true
                        background: Rectangle { color: "transparent"; border.color: "#333"; radius: 8 }
                        label: Text { text: parent.title; color: "#888" }
                        ColumnLayout {
                            anchors.fill: parent
                            TextField { id: ipSet; text: "192.168.137.219"; placeholderText: "IP"; Layout.fillWidth: true; color: "white" }
                            TextField { id: portSet; text: "8888"; placeholderText: "Port"; Layout.fillWidth: true; color: "white" }
                            Button { text: "保存并尝试连接"; Layout.fillWidth: true; onClicked: robotClient.connectToServer(ipSet.text, parseInt(portSet.text)) }
                        }
                    }
                    GroupBox {
                        title: "视频录制路径"; Layout.fillWidth: true
                        background: Rectangle { color: "transparent"; border.color: "#333"; radius: 8 }
                        label: Text { text: parent.title; color: "#888" }
                        RowLayout {
                            anchors.fill: parent; anchors.margins: 5
                            TextField { id: pathField; text: videoBackend.recordPath; Layout.fillWidth: true; readOnly: true; color: "white"; background: Rectangle { color: "#2a2a2a"; radius: 4 } }
                            Button { text: "浏览"; onClicked: folderDialog.open() }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                    spacing: 15
                    GroupBox {
                        title: "控制频率"; Layout.fillWidth: true
                        background: Rectangle { color: "transparent"; border.color: "#333"; radius: 8 }
                        label: Text { text: parent.title; color: "#888" }
                        RowLayout {
                            anchors.fill: parent
                            Text { text: "频率: " + freqSlider.value + " Hz"; color: colorText }
                            Slider { id: freqSlider; from: 1; to: 100; stepSize: 1; value: robotClient.frequency; Layout.fillWidth: true; onValueChanged: robotClient.frequency = value }
                        }
                    }
                    GroupBox {
                        title: "映射配置"; Layout.fillWidth: true
                        background: Rectangle { color: "transparent"; border.color: "#333"; radius: 8 }
                        label: Text { text: parent.title; color: "#888" }
                        RowLayout {
                            spacing: 10
                            Button { text: "导入 JSON"; onClicked: importDialog.open() }
                            Button { text: "导出当前"; onClicked: exportDialog.open() }
                            Button { text: "恢复默认"; onClicked: robotClient.applyHardcodedDefaults() }
                        }
                    }
                    Item { Layout.fillHeight: true }
                }

                ColumnLayout {
                    ScrollView {
                        Layout.fillWidth: true; Layout.fillHeight: true
                        TextArea { id: logArea; readOnly: true; font.family: "Monospace"; font.pixelSize: 11; color: "#aaa"; background: Rectangle { color: "#111"; radius: 4 } selectByMouse: true }
                    }
                }
            }
            Button { text: "关闭"; Layout.alignment: Qt.AlignRight; onClicked: controlSettingsPopup.close() }
        }
    }

    MediaDevices { id: mediaDevices }

    Connections {
        target: videoBackend
        function onErrorMessage(msg) { logArea.append("<font color='red'>错误: " + msg + "</font>") }
    }
}
