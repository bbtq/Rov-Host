#ifndef VIDEOBACKEND_H
#define VIDEOBACKEND_H

#include <QObject>
#include <QVideoSink>
#include <QDebug>
#include <QDateTime>
#include <gst/gst.h>

class VideoBackend : public QObject
{
    Q_OBJECT
    // 我们只需要读取状态，不需要由 QML 设置 Sink
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY isPlayingChanged)
    // [新增] 录制状态属性
    Q_PROPERTY(bool isRecording READ isRecording NOTIFY isRecordingChanged)
    // [新增] 录制保存路径属性
    Q_PROPERTY(QString recordPath READ recordPath WRITE setRecordPath NOTIFY recordPathChanged)

public:
    explicit VideoBackend(QObject *parent = nullptr);
    ~VideoBackend();

    // 关键修复：接收 QML 的 videoSink (作为 QObject* 传入以避免类型系统问题)
    Q_INVOKABLE void setVideoSink(QObject *sink);

    // 启动视频，不需要再传 videoItem 了，因为我们已经保存了 sink
    Q_INVOKABLE void startVideo(const QString &source, const QString &decoderName, bool isCamera);

    Q_INVOKABLE void stopVideo();
    Q_INVOKABLE void togglePlayPause();

    // [新增] 开始/停止录制
    Q_INVOKABLE void toggleRecording();

    bool isPlaying() const { return m_isPlaying; }
    // [新增] Getter & Setter
    bool isRecording() const { return m_isRecording; }
    QString recordPath() const { return m_recordPath; }
    void setRecordPath(const QString &path) {
        if (m_recordPath != path) {
            m_recordPath = path;
            emit recordPathChanged();
        }
    }

signals:
    void isPlayingChanged();
    void isRecordingChanged(); // [新增]
    void recordPathChanged();  // [新增]
    void errorMessage(QString msg);

private:
    // GStreamer 回调
    static GstFlowReturn on_new_sample(GstElement *sink, VideoBackend *self);
    void handleFrame(GstSample *sample);
    void cleanup();

    // [新增] 停止录制的内部逻辑
    void stopRecordingInternal();

    GstElement *m_pipeline = nullptr;
    GstElement *m_appsink = nullptr;
    // [新增] 录制相关的 GStreamer 元素
    GstElement *m_tee = nullptr;         // 分流器
    GstElement *m_recBin = nullptr;      // 录制分支的容器 (Queue + Mux + Sink)
    GstPad     *m_teeSrcPad = nullptr;   // 分流器的输出端口

    QVideoSink *m_videoSink = nullptr; // C++ 内部持有的指针
    bool m_isPlaying = false;
    bool m_isRecording = false; // [新增]
    bool m_isCamera = false;
    QString m_recordPath;       // [新增]
};

#endif // VIDEOBACKEND_H
