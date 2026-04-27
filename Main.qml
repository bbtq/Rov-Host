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
    property bool showInputMonitor: true // 控制按键显示开关

    readonly property color colorBg: "#121212"
    readonly property color colorSurface: "#AA1e1e1e"
    readonly property color colorPrimary: "#00e5ff"
    readonly property color colorText: "#e0e0e0"

    // 预定义的键名列表用于下拉筛选
    readonly property var gamepadKeyList: [
        "joy_lx", "joy_ly", "joy_rx", "joy_ry", "joy_lt", "joy_rt",
        "btn_a", "btn_b", "btn_x", "btn_y", "btn_back", "btn_start",
        "btn_leftshoulder", "btn_rightshoulder", "btn_dpup", "btn_dpdown", "btn_dpleft", "btn_dpright"
    ]
    readonly property var keyboardKeyList: [
        "key_W", "key_A", "key_S", "key_D", "key_Up", "key_Down", "key_Left", "key_Right",
        "key_Space", "key_Shift", "key_Control", "key_Escape", "key_Enter", "key_Tab", "key_Q", "key_E"
    ]

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
            let lastPath = robotClient.getLastConfigPath();
            let defaultPath = robotClient.getDefaultConfigPath();

            // 策略：优先加载上次，其次加载同级目录默认，最后硬编码生成
            if (lastPath !== "" && robotClient.importConfig(lastPath)) {
                logArea.append("<b>系统:</b> 加载上次配置: " + lastPath);
            } else if (robotClient.importConfig(defaultPath)) {
                logArea.append("<b>系统:</b> 加载默认配置文件");
            } else {
                logArea.append("<i>提示: 配置文件不存在，正在生成默认配置...</i>");
                applyHardcodedDefaults();
                robotClient.exportConfig(defaultPath); // 自动生成并保存
                robotClient.saveLastConfigPath(defaultPath);
            }
            // if (!robotClient.importConfig(defaultPath)) applyHardcodedDefaults()
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
                        title: "配置管理"; Layout.fillWidth: true
                        background: Rectangle { border.color: "#333"; radius: 8; color: "transparent" }
                        label: Text { text: parent.title; color: "#888" }
                        GridLayout {
                            columns: 2; anchors.fill: parent; rowSpacing: 10; columnSpacing: 10
                            Button { text: "导入 JSON"; Layout.fillWidth: true; onClicked: importDialog.open() }
                            Button { text: "导出配置"; Layout.fillWidth: true; onClicked: exportDialog.open() }
                            Button { text: "恢复出厂"; Layout.fillWidth: true; onClicked: robotClient.applyHardcodedDefaults() }
                            Button {
                                text: "编辑映射";
                                Layout.fillWidth: true;
                                highlighted: true
                                onClicked: mappingEditorPopup.open() // 打开分页编辑器
                            }
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

    Component.onCompleted: {
            let lastPath = robotClient.getLastConfigPath();
            let defaultPath = robotClient.getDefaultConfigPath();

            if (lastPath !== "" && robotClient.importConfig(lastPath)) {
                logArea.append("<b>系统:</b> 已加载上次使用的配置: " + lastPath);
            } else {
                // 如果上次路径不可用
                if (lastPath !== "") {
                    errorDialog.text = "找不到上次的配置文件，已恢复默认配置。";
                    errorDialog.open();
                    logArea.append("<font color='orange'>警告: 上次配置丢失: </font>" + lastPath);
                }

                // 尝试加载默认文件，若无则生成
                if (!robotClient.importConfig(defaultPath)) {
                    logArea.append("<i>提示: 自动生成初始配置文件...</i>");
                    applyHardcodedDefaults();
                    robotClient.saveLastConfigPath(defaultPath);
                    robotClient.exportConfig(defaultPath); // 立即保存一份
                }
            }
        }

        // --- 映射编辑器弹窗 ---
        Popup {
            id: mappingEditorPopup
            width: 800; height: 600; x: (parent.width-width)/2; y: (parent.height-height)/2
            modal: true; focus: true
            background: Rectangle { color: "#1a1a1a"; radius: 12; border.color: colorPrimary }

            property var tempMappings: []
            onAboutToShow: tempMappings = robotClient.qmlMappings

            ColumnLayout {
                anchors.fill: parent; anchors.margins: 20; spacing: 15

                TabBar {
                    id: editorTabBar; Layout.fillWidth: true
                    TabButton { text: "🎮 手柄映射 (Gamepad)" }
                    TabButton { text: "⌨️ 键盘映射 (Keyboard)" }
                }

                // 表头
                RowLayout {
                    Layout.fillWidth: true; spacing: 10
                    Text { text: "输入键名"; color: "#888"; Layout.preferredWidth: 200 }
                    Text { text: "方法 (Method)"; color: "#888"; Layout.preferredWidth: 150 }
                    Text { text: "参数/类型"; color: "#888"; Layout.preferredWidth: 120 }
                    Text { text: "比例因子"; color: "#888"; Layout.fillWidth: true }
                    Item { Layout.preferredWidth: 40 }
                }

                ScrollView {
                    Layout.fillWidth: true; Layout.fillHeight: true; clip: true
                    ListView {
                        id: mappingListView; spacing: 8
                        model: mappingEditorPopup.tempMappings
                        delegate: RowLayout {
                            id: delegateRow
                            width: mappingListView.width; spacing: 10
                            // 根据当前 Tab 过滤显示
                            visible: (editorTabBar.currentIndex === 0 && (modelData.inputKey.startsWith("joy_") || modelData.inputKey.startsWith("btn_"))) ||
                                     (editorTabBar.currentIndex === 1 && modelData.inputKey.startsWith("key_"))
                            height: visible ? 40 : 0

                            // 优化点 4: 搜索式下拉框
                            ComboBox {
                                Layout.preferredWidth: 200
                                editable: true
                                model: editorTabBar.currentIndex === 0 ? gamepadKeyList : keyboardKeyList
                                currentIndex: model.indexOf(modelData.inputKey)

                                // 设置文字颜色为白色
                                contentItem: TextInput {
                                    text: parent.editText
                                    color: "white"
                                    selectionColor: "gray"
                                    cursorVisible: parent.activeFocus
                                    font: parent.font
                                    verticalAlignment: TextInput.AlignVCenter
                                }


                                onEditTextChanged: {
                                    mappingEditorPopup.tempMappings[index].inputKey = editText
                                }
                                // 简单的包含过滤逻辑
                                onPressedChanged: { if(pressed) model = (editorTabBar.currentIndex === 0 ? gamepadKeyList : keyboardKeyList).filter(s => s.includes(editText)) }

                            }

                            TextField {
                                text: modelData.method; Layout.preferredWidth: 150
                                color: "white"
                                background: Rectangle {
                                    color: "transparent"
                                    border.color: "white"
                                    border.width: 1
                                    radius: 4
                                }

                                onTextChanged: mappingEditorPopup.tempMappings[index].method = text
                            }

                            TextField {
                                text: modelData.paramKey; Layout.preferredWidth: 120
                                color: "white"                    // 输入文字白色
                                placeholderTextColor: "#aaaaaa"   // 占位符灰色（如果有）

                                background: Rectangle {
                                    color: "transparent"          // 或 "#333333"
                                    border.color: "white"
                                    border.width: 1
                                    radius: 4
                                }

                                onTextChanged: mappingEditorPopup.tempMappings[index].paramKey = text
                            }

                            // 优化点 2: 带有边界限制的输入栏 (-10.0 ~ 10.0)
                            TextField {
                                Layout.fillWidth: true
                                text: modelData.scale.toFixed(2)
                                validator: DoubleValidator { bottom: -10.0; top: 10.0; decimals: 2 }

                                color: "white"
                                background: Rectangle {
                                    color: "transparent"
                                    border.color: "white"
                                    border.width: 1
                                    radius: 4
                                }

                                onTextChanged: mappingEditorPopup.tempMappings[index].scale = parseFloat(text)
                            }

                            Button {
                                text: "删除";

                                onClicked: { let a = mappingEditorPopup.tempMappings; a.splice(index, 1); mappingEditorPopup.tempMappings = a }
                            }
                        }

                        footer: Button {
                            text: "＋ 添加映射项"; Layout.fillWidth: true;

                            onClicked: {
                                let a = mappingEditorPopup.tempMappings;
                                let prefix = editorTabBar.currentIndex === 0 ? "joy_new" : "key_new";
                                a.push({"inputKey": prefix, "method": "move", "paramKey": "x", "scale": 1.0});
                                mappingEditorPopup.tempMappings = a;
                            }
                        }
                    }
                }

                RowLayout {
                    Layout.alignment: Qt.AlignRight; spacing: 15
                    Button { text: "保存并应用"; highlighted: true; onClicked: { robotClient.qmlMappings = mappingEditorPopup.tempMappings; robotClient.saveCurrentConfig(); mappingEditorPopup.close() } }
                    Button { text: "恢复"; onClicked: mappingEditorPopup.tempMappings = robotClient.qmlMappings }
                    Button { text: "退出"; onClicked: mappingEditorPopup.close() }
                }
            }
        }

    MediaDevices { id: mediaDevices }

    Connections {
        target: videoBackend
        function onErrorMessage(msg) { logArea.append("<font color='red'>错误: " + msg + "</font>") }
    }

    // --- 1. 左侧动态传感器看板 ---
        Column {
            id: sensorOverlay
            anchors.left: parent.left
            anchors.leftMargin: 20
            anchors.verticalCenter: parent.verticalCenter
            spacing: 12
            z: 150
            visible: showUI // 随工具栏一起隐藏

            Repeater {
                // 动态绑定 sensorData 的所有键值对
                model: Object.keys(robotClient.sensorData)
                delegate: Rectangle {
                    width: 150; height: 50
                    color: "#CC1e1e1e"
                    radius: 8
                    border.color: colorPrimary
                    border.width: 1

                    Column {
                        anchors.centerIn: parent
                        spacing: 2
                        Text {
                            text: modelData // 键名，如“温度”
                            color: "#888"; font.pixelSize: 11; anchors.horizontalCenter: parent.horizontalCenter
                        }
                        Text {
                            text: robotClient.sensorData[modelData] // 值，如“30.89 ℃”
                            color: "white"; font.bold: true; font.pixelSize: 15; anchors.horizontalCenter: parent.horizontalCenter
                        }
                    }
                }
            }
        }

        // // --- 2. 底部实时按键监控条 ---
        // Rectangle {
        //     id: inputMonitor
        //     anchors.bottom: videoControlPanel.top
        //     anchors.bottomMargin: 10
        //     anchors.horizontalCenter: parent.horizontalCenter
        //     width: 450; height: 36
        //     color: "#AA000000"
        //     radius: 18
        //     border.color: "#33ffffff"
        //     visible: showUI && robotClient.showInputMonitor // 支持开关
        //     z: 150

        //     RowLayout {
        //         anchors.fill: parent; anchors.margins: 10
        //         Text { text: "🎮 实时输入:"; color: colorPrimary; font.bold: true; font.pixelSize: 12 }
        //         Text {
        //             color: "white"; font.family: "Monospace"; font.pixelSize: 12
        //             Layout.fillWidth: true; elide: Text.ElideRight
        //             // 实时计算当前活动输入
        //             text: {
        //                 let active = [];
        //                 // 检查主要轴
        //                 if (Math.abs(Backend.leftStickX) > 0.1) active.push("LX:" + Backend.leftStickX.toFixed(2));
        //                 if (Math.abs(Backend.leftStickY) > 0.1) active.push("LY:" + Backend.leftStickY.toFixed(2));
        //                 // 获取键盘/手柄按键字符串
        //                 let keys = Backend.pressedKeysString || "";
        //                 return (active.join(" ") + " " + keys).trim() || "IDLE";
        //             }
        //         }
        //     }
        // }
        RowLayout {
                id: inputMonitorArea
                anchors.bottom: videoControlPanel.top
                anchors.bottomMargin: 10
                anchors.horizontalCenter: parent.horizontalCenter
                height: 85 // 稍微增加高度以容纳肩键
                spacing: 15
                z: 150
                visible: showUI && robotClient.showInputMonitor

                // --- 1. 手柄正面可视化展示图 ---
                Rectangle {
                    id: gamepadVisualizer
                    width: 220; height: 85
                    color: "#CC000000" // 黑色半透明背景
                    radius: 12
                    border.color: "#33ffffff"
                    border.width: 1

                    Item {
                        anchors.fill: parent
                        anchors.margins: 5

                        // --- [顶部] 肩键区域 (LB, LT, RB, RT) ---
                        // 左侧肩键
                        Row {
                            x: 10; y: 2; spacing: 5
                            // LT
                            Rectangle {
                                width: 30; height: 8; radius: 2;
                                color: Backend.leftTrigger > 0.1 ? colorPrimary : "#33ffffff"
                                border.color: Backend.leftTrigger > 0.1 ? "white" : "transparent"
                            }
                            // LB
                            Rectangle {
                                width: 25; height: 6; radius: 2;
                                color: Backend.buttons["btn_leftshoulder"] ? colorPrimary : "#33ffffff"
                            }
                        }

                        // 右侧肩键
                        Row {
                            anchors.right: parent.right; anchors.rightMargin: 10; y: 2; spacing: 5
                            // RB
                            Rectangle {
                                width: 25; height: 6; radius: 2;
                                color: Backend.buttons["btn_rightshoulder"] ? colorPrimary : "#33ffffff"
                            }
                            // RT
                            Rectangle {
                                width: 30; height: 8; radius: 2;
                                color: Backend.rightTrigger > 0.1 ? colorPrimary : "#33ffffff"
                                border.color: Backend.rightTrigger > 0.1 ? "white" : "transparent"
                            }
                        }

                        // --- [左侧] 方向键区域 - 正菱形布局 ---
                        Item {
                            id: dpadGroup
                            x: 15; y: 40; width: 40; height: 40
                            // 上
                            Rectangle { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; width: 10; height: 10; radius: 2; color: Backend.buttons["btn_dpup"] ? colorPrimary : "#33ffffff" }
                            // 下
                            Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: 10; height: 10; radius: 2; color: Backend.buttons["btn_dpdown"] ? colorPrimary : "#33ffffff" }
                            // 左
                            Rectangle { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 2; color: Backend.buttons["btn_dpleft"] ? colorPrimary : "#33ffffff" }
                            // 右
                            Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 10; height: 10; radius: 2; color: Backend.buttons["btn_dpright"] ? colorPrimary : "#33ffffff" }
                        }

                        // --- [中间] 左右摇杆状态 ---
                        // 左摇杆 (L-Stick)
                        Rectangle {
                            x: 65; y: 15; width: 30; height: 30; radius: 15; color: "#11ffffff"; border.color: "#44ffffff"
                            Rectangle {
                                width: 10; height: 10; radius: 5; color: "white"
                                x: 10 + Backend.leftStickX * 10
                                y: 10 + Backend.leftStickY * 10
                            }
                        }
                        // 右摇杆 (R-Stick)
                        Rectangle {
                            x: 115; y: 45; width: 30; height: 30; radius: 15; color: "#11ffffff"; border.color: "#44ffffff"
                            Rectangle {
                                width: 10; height: 10; radius: 5; color: "white"
                                x: 10 + Backend.rightStickX * 10
                                y: 10 + Backend.rightStickY * 10
                            }
                        }

                        // --- [右侧] ABXY 区域 - 正菱形布局 (X左, Y上, A下, B右) ---
                        Item {
                            id: abxyGroup
                            anchors.right: parent.right; anchors.rightMargin: 15; y: 15; width: 45; height: 45
                            // Y 上 (黄色)
                            Rectangle { anchors.top: parent.top; anchors.horizontalCenter: parent.horizontalCenter; width: 14; height: 14; radius: 7;
                                        color: Backend.buttons["btn_y"] ? "#FFD700" : "#33ffffff" }
                            // A 下 (绿色)
                            Rectangle { anchors.bottom: parent.bottom; anchors.horizontalCenter: parent.horizontalCenter; width: 14; height: 14; radius: 7;
                                        color: Backend.buttons["btn_a"] ? "#32CD32" : "#33ffffff" }
                            // X 左 (蓝色)
                            Rectangle { anchors.left: parent.left; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7;
                                        color: Backend.buttons["btn_x"] ? "#1E90FF" : "#33ffffff" }
                            // B 右 (红色)
                            Rectangle { anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter; width: 14; height: 14; radius: 7;
                                        color: Backend.buttons["btn_b"] ? "#FF4500" : "#33ffffff" }
                        }
                    }
                }

                // --- 2. 实时文字输入监控条 ---
                Rectangle {
                    id: inputMonitorTextBar
                    width: 400; height: 40
                    color: "#AA000000"
                    radius: 20
                    border.color: "#33ffffff"
                    Layout.alignment: Qt.AlignVCenter

                    RowLayout {
                        anchors.fill: parent; anchors.margins: 12
                        Text { text: "⌨️ 输入监控:"; color: colorPrimary; font.bold: true; font.pixelSize: 12 }
                        Text {
                            color: "white"; font.family: "Monospace"; font.pixelSize: 12
                            Layout.fillWidth: true; elide: Text.ElideRight
                            text: {
                                let active = []
                                if (Math.abs(Backend.leftStickX) > 0.1) active.push("LX:" + Backend.leftStickX.toFixed(2))
                                if (Math.abs(Backend.leftStickY) > 0.1) active.push("LY:" + Backend.leftStickY.toFixed(2))
                                if (Backend.leftTrigger > 0.1) active.push("LT:" + Backend.leftTrigger.toFixed(2))
                                if (Backend.rightTrigger > 0.1) active.push("RT:" + Backend.rightTrigger.toFixed(2))
                                let keys = Backend.pressedKeysString || ""
                                return (active.join(" ") + " " + keys).trim() || "IDLE"
                            }
                        }
                    }
                }
            }
}
