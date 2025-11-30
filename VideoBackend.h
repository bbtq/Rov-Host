#ifndef VIDEOBACKEND_H
#define VIDEOBACKEND_H

#include <QObject>
#include <QVideoSink>
#include <QDebug>
#include <gst/gst.h>

class VideoBackend : public QObject
{
    Q_OBJECT
    // 我们只需要读取状态，不需要由 QML 设置 Sink
    Q_PROPERTY(bool isPlaying READ isPlaying NOTIFY isPlayingChanged)

public:
    explicit VideoBackend(QObject *parent = nullptr);
    ~VideoBackend();

    // 关键修复：接收 QML 的 videoSink (作为 QObject* 传入以避免类型系统问题)
    Q_INVOKABLE void setVideoSink(QObject *sink);

    // 启动视频，不需要再传 videoItem 了，因为我们已经保存了 sink
    Q_INVOKABLE void startVideo(const QString &url, const QString &decoderName);

    Q_INVOKABLE void stopVideo();
    Q_INVOKABLE void togglePlayPause();

    bool isPlaying() const { return m_isPlaying; }

signals:
    void isPlayingChanged();
    void errorMessage(QString msg);

private:
    // GStreamer 回调
    static GstFlowReturn on_new_sample(GstElement *sink, VideoBackend *self);
    void handleFrame(GstSample *sample);
    void cleanup();

    GstElement *m_pipeline = nullptr;
    GstElement *m_appsink = nullptr;
    QVideoSink *m_videoSink = nullptr; // C++ 内部持有的指针
    bool m_isPlaying = false;
};

#endif // VIDEOBACKEND_H
