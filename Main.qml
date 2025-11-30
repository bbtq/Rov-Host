import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtMultimedia // 引入 Qt 多媒体模块
import com.mycompany.stream 1.0

ApplicationWindow {
    visible: true
    width: 800
    height: 600
    title: "GStreamer AppSink Player"
    color: "black"

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
        width: parent.width * 0.9
        height: 80
        anchors.bottom: parent.bottom
        anchors.bottomMargin: 20
        anchors.horizontalCenter: parent.horizontalCenter
        radius: 15
        color: "#AA1e1e1e"
        border.color: "#33ffffff"
        border.width: 1

        RowLayout {
            anchors.fill: parent
            anchors.margins: 15
            spacing: 15

            TextField {
                id: urlField
                Layout.fillWidth: true
                // RTSP 测试地址
                text: "rtsp://wowzaec2demo.streamlock.net/vod/mp4:BigBuckBunny_115k.mp4"
                selectByMouse: true
                color: "white"
                background: Rectangle { color: "#22ffffff"; radius: 8 }
            }

            ComboBox {
                id: decoderCombo
                Layout.preferredWidth: 150
                model: ["d3d11h265dec", "avdec_h265", "nvh265dec"]
                currentIndex: 0
                background: Rectangle { color: "#22ffffff"; radius: 8 }
            }

            Button {
                text: backend.isPlaying ? "Stop" : "Play"
                Layout.preferredWidth: 80
                onClicked: {
                    if (backend.isPlaying) {
                        backend.stopVideo() // 简单起见，这里直接停止
                    } else {
                        // 【修复】：只需要传 URL 和解码器，不需要传 videoItem 了
                        backend.startVideo(urlField.text, decoderCombo.currentText)
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
