#include "VideoBackend.h"
#include <QVideoFrame>
#include <gst/video/video.h>

VideoBackend::VideoBackend(QObject *parent) : QObject(parent)
{
    // 初始化 GStreamer
    gst_init(nullptr, nullptr);
}

VideoBackend::~VideoBackend()
{
    cleanup();
}

void VideoBackend::setVideoSink(QObject *sink)
{
    // 将 QML 传来的对象转换为 QVideoSink
    m_videoSink = qobject_cast<QVideoSink*>(sink);
    if (m_videoSink) {
        qDebug() << "VideoSink set successfully!";
    } else {
        qDebug() << "Error: Failed to cast object to QVideoSink";
    }
}

void VideoBackend::cleanup()
{
    if (m_pipeline) {
        gst_element_set_state(m_pipeline, GST_STATE_NULL);
        gst_object_unref(m_pipeline);
        m_pipeline = nullptr;
    }
    m_appsink = nullptr;
    m_isPlaying = false;
    emit isPlayingChanged();
}

void VideoBackend::startVideo(const QString &url, const QString &decoderName)
{
    if (!m_videoSink) {
        emit errorMessage("VideoSink not initialized. Component not ready?");
        return;
    }

    cleanup(); // 先停止之前的

    // 构建管道
    // 关键点：
    // 1. videoconvert ! video/x-raw,format=RGBA: 强制转为 RGBA，这是 QImage 最喜欢的格式
    // 2. appsink: 用于回调获取数据
    QString pipeStr = QString(
                          "rtspsrc location=%1 latency=200 ! "
                          "rtph265depay ! h265parse ! %2 ! "
                          "videoconvert ! video/x-raw,format=RGBA ! "
                          "appsink name=mysink emit-signals=true sync=false drop=true"
                          ).arg(url, decoderName);

    qDebug() << "Pipeline:" << pipeStr;

    GError *error = nullptr;
    m_pipeline = gst_parse_launch(pipeStr.toUtf8().constData(), &error);

    if (error) {
        emit errorMessage(QString("Pipeline Error: %1").arg(error->message));
        g_error_free(error);
        return;
    }

    // 获取 appsink 元素并连接信号
    m_appsink = gst_bin_get_by_name(GST_BIN(m_pipeline), "mysink");
    if (m_appsink) {
        g_signal_connect(m_appsink, "new-sample", G_CALLBACK(on_new_sample), this);
        gst_object_unref(m_appsink); // get_by_name 会增加引用计数，这里释放一下
    } else {
        emit errorMessage("AppSink not found in pipeline");
        return;
    }

    GstStateChangeReturn ret = gst_element_set_state(m_pipeline, GST_STATE_PLAYING);
    if (ret == GST_STATE_CHANGE_FAILURE) {
        emit errorMessage("Failed to start playback");
        cleanup();
        return;
    }

    m_isPlaying = true;
    emit isPlayingChanged();
}

void VideoBackend::stopVideo()
{
    cleanup();
}

void VideoBackend::togglePlayPause()
{
    if (!m_pipeline) return;
    if (m_isPlaying) {
        gst_element_set_state(m_pipeline, GST_STATE_PAUSED);
        m_isPlaying = false;
    } else {
        gst_element_set_state(m_pipeline, GST_STATE_PLAYING);
        m_isPlaying = true;
    }
    emit isPlayingChanged();
}

// 静态回调：从 GStreamer 线程跳回 C++ 类
GstFlowReturn VideoBackend::on_new_sample(GstElement *sink, VideoBackend *self)
{
    GstSample *sample;
    g_signal_emit_by_name(sink, "pull-sample", &sample);
    if (sample) {
        self->handleFrame(sample);
        gst_sample_unref(sample);
        return GST_FLOW_OK;
    }
    return GST_FLOW_ERROR;
}

// 处理每一帧数据
void VideoBackend::handleFrame(GstSample *sample)
{
    if (!m_videoSink) return;

    GstBuffer *buffer = gst_sample_get_buffer(sample);
    GstCaps *caps = gst_sample_get_caps(sample);
    GstStructure *s = gst_caps_get_structure(caps, 0);

    int width, height;
    gst_structure_get_int(s, "width", &width);
    gst_structure_get_int(s, "height", &height);

    GstMapInfo map;
    if (gst_buffer_map(buffer, &map, GST_MAP_READ)) {
        // 创建 QVideoFrame
        // 注意：这里必须使用 QVideoFrameFormat (Qt6)
        QVideoFrameFormat format(QSize(width, height), QVideoFrameFormat::Format_RGBA8888);
        QVideoFrame frame(format);

        // 必须 map 为 WriteOnly 才能把数据拷进去
        if (frame.map(QVideoFrame::WriteOnly)) {
            memcpy(frame.bits(0), map.data, map.size);
            frame.unmap();

            // 重要：设置开始时间，否则可能无法渲染
            frame.setStartTime(0);

            // 推送给 VideoOutput
            m_videoSink->setVideoFrame(frame);
        }
        gst_buffer_unmap(buffer, &map);
    }
}
