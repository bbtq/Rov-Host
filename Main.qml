import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia // 引入 Qt 多媒体模块
// [新增] 引入 Labs 模块用于原生对话框
import Qt.labs.platform 1.1 as Native
import com.mycompany.stream 1.0

ApplicationWindow {
    visible: true
    width: 900
    height: 600
    title: "GStreamer AppSink Player"
    color: Qt.rgba(0,0,0,0.5)//"black"

    MediaDevices {
            id: mediaDevices
    }

    // [新增] 文件夹选择对话框
    Native.FolderDialog {
            id: folderDialog
            title: "Select Recording Folder"
            currentFolder: "file:///" + backend.recordPath
            // 注意：这里千万不要写 anchors.fill 或 anchors.centerIn
            // 因为它是弹出的原生系统窗口，位置由操作系统管理
            onAccepted: {
                var path = folderDialog.folder.toString();
                // 清理前缀
                path = path.replace(/^(file:\/{3})|(file:\/\/)/, "");
                // Windows 特殊处理：如果路径变成了 /C:/Users... 去掉开头的 /
                if (Qt.platform.os === "windows" && path.length > 2 && path[0] === "/" && path[2] === ":") {
                    path = path.substring(1);
                }
                backend.recordPath = path
            }
        }

    // [新增] 设置弹窗
    Dialog {
        id: settingsDialog
        title: "Settings"
        anchors.centerIn: parent
        width: 400
        standardButtons: Dialog.Ok

        ColumnLayout {
            spacing: 10
            width: parent.width

            Label { text: "Recording Path:"; font.bold: true }

            RowLayout {
                Layout.fillWidth: true
                TextField {
                    id: pathField
                    text: backend.recordPath
                    Layout.fillWidth: true
                    readOnly: true // 只读，强制通过浏览选择，防止格式错误
                }
                Button {
                    text: "Browse"
                    onClicked: folderDialog.open()
                }
            }
        }
    }

    VideoBackend {
        id: backend
        // 【核心修复】: 当组件加载完成后，把 videoOut 的 videoSink 传给 C++
        // videoOut.videoSink 是只读的，但我们可以把它作为参数传递
        Component.onCompleted: {
            backend.setVideoSink(videoOut.videoSink)
        }
    }

    VideoOutput {
        id: videoOut
        anchors.fill: parent
        // 不要在这里写 source: backend
        // 也不要写 videoSink: ...
        // 保持这里仅仅是一个显示容器
    }

    // 底部控制面板
    Rectangle {
        id: controlPanel
        width: parent.width * 0.95
        height: 100 // 稍微加高一点
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 15
        color: "#AA1e1e1e"
        border.color: "#33ffffff"
        border.width: 1

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 5

            // [新增] 第一行：模式切换 (RTSP / Camera)
            RowLayout {
                Layout.fillWidth: true
                spacing: 20

                Label {
                    text: "Mode:"
                    color: "white"
                    font.bold: true
                }

                RadioButton {
                    id: rbRtsp
                    text: "RTSP Stream"
                    checked: true // 默认选中
                    contentItem: Text { text: rbRtsp.text; color: "white"; leftPadding: rbRtsp.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                }

                RadioButton {
                    id: rbCamera
                    text: "USB Camera"
                    contentItem: Text { text: rbCamera.text; color: "white"; leftPadding: rbCamera.indicator.width + 4; verticalAlignment: Text.AlignVCenter }
                }

                Item { Layout.fillWidth: true } // 占位符

                Button {
                                     text: "⚙ Settings"
                                     flat: true
                                     contentItem: Text { text: parent.text; color: "#ccc"; font.pixelSize: 14 }
                                     onClicked: settingsDialog.open()
                }
            }

            // 第二行：原有的控制项，根据模式自动变化
            RowLayout {
                Layout.fillWidth: true
                spacing: 15

                // [修改]：输入区域 (StackLayout 或者简单的 Visible 绑定)

                // 1. RTSP URL 输入框 (仅 RTSP 模式显示)
                TextField {
                    id: urlField
                    visible: rbRtsp.checked
                    Layout.fillWidth: true
                    text: "rtsp://127.0.0.1:8554/"
                    selectByMouse: true
                    color: "white"
                    background: Rectangle { color: "#22ffffff"; radius: 8 }
                    placeholderText: "Enter RTSP URL..."
                }

                // 2. [新增] 摄像头选择框 (仅 Camera 模式显示)
                ComboBox {
                    id: camCombo
                    visible: rbCamera.checked
                    Layout.fillWidth: true
                    // model 直接绑定到系统检测到的摄像头列表
                    model: mediaDevices.videoInputs
                    textRole: "description" // 显示摄像头的名称

                    background: Rectangle { color: "#22ffffff"; radius: 8 }
                    contentItem: Text {
                        text: camCombo.displayText
                        color: "white"
                        verticalAlignment: Text.AlignVCenter
                        leftPadding: 10
                    }
                }

                // 3. 解码器选择 (仅 RTSP 模式显示，摄像头一般由 decodebin 自动处理)
                ComboBox {
                    id: decoderCombo
                    visible: rbRtsp.checked
                    Layout.preferredWidth: 150
                    model: ["d3d11h265dec", "avdec_h265", "nvh265dec"]
                    currentIndex: 0
                    background: Rectangle { color: "#22ffffff"; radius: 8 }
                    contentItem: Text { text: decoderCombo.displayText; color: "white"; verticalAlignment: Text.AlignVCenter; leftPadding: 10 }
                }

                // 4. 播放按钮
                Button {
                    text: backend.isPlaying ? "Stop" : "Play"
                    Layout.preferredWidth: 80
                    onClicked: {
                        if (backend.isPlaying) {
                            backend.stopVideo()
                        } else {
                            if (rbRtsp.checked) {
                                // RTSP 模式：传 URL，解码器，isCamera=false
                                backend.startVideo(urlField.text, decoderCombo.currentText, false)
                            } else {
                                // Camera 模式：传 索引，解码器(忽略)，isCamera=true
                                // mediaDevices.videoInputs 的顺序通常对应系统的 device-index
                                // 我们直接传入当前选中的 index
                                backend.startVideo(camCombo.currentIndex.toString(), "", true)
                            }
                        }
                    }
                }
                // [新增] 录制按钮
                Button {
                    id: recordBtn
                    // 仅在播放时可用
                    enabled: backend.isPlaying
                    // 根据状态变色
                    background: Rectangle {
                        color: backend.isRecording ? "#ccff0000" : "#44ffffff"
                        radius: 8
                    }
                    contentItem: RowLayout {
                        spacing: 5
                        // 红点图标
                        Rectangle {
                            width: 10; height: 10; radius: 5
                            color: backend.isRecording ? "white" : "red"
                        }
                        Text {
                            text: backend.isRecording ? "Stop Record" : "Record"
                            color: "white"
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                    onClicked: {
                        backend.toggleRecording()
                    }
                }
            }
        }
    }

    Dialog {
        id: errorDialog
        title: "Error"
        property alias text: msgLabel.text
        anchors.centerIn: parent
        standardButtons: Dialog.Ok
        Label { id: msgLabel; color: "white" }
    }

    Connections {
        target: backend
        function onErrorMessage(msg) {
            errorDialog.text = msg
            errorDialog.open()
        }
    }
}
