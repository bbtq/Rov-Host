#include "VideoBackend.h"
#include <QVideoFrame>
#include <QDir>
#include <QUrl>
#include <QDateTime>
// 引入 Ghost Pad 头文件
#include <gst/gstghostpad.h>

VideoBackend::VideoBackend(QObject *parent) : QObject(parent)
{
    gst_init(nullptr, nullptr);
    m_recordPath = QDir::currentPath();
}

VideoBackend::~VideoBackend()
{
    cleanup();
}

void VideoBackend::setVideoSink(QObject *sink)
{
    m_videoSink = qobject_cast<QVideoSink*>(sink);
    if (!m_videoSink) {
        qDebug() << "Error: Failed to cast object to QVideoSink";
    }
}

void VideoBackend::startVideo(const QString &source, const QString &decoderName, bool isCamera)
{
    if (!m_videoSink) {
        emit errorMessage("VideoSink not initialized. Component not ready?");
        return;
    }

    cleanup();
    m_isCamera = isCamera; // 记住当前模式

    QString pipeStr;
    if (isCamera) {
        // 摄像头模式
        // ksvideosrc -> decodebin -> videoconvert -> tee -> ...
        pipeStr = QString(
                      "mfvideosrc device-index=%1 ! decodebin ! videoconvert ! "
                      "tee name=t ! queue ! "
                      "video/x-raw,format=RGBA ! "
                      "appsink name=mysink emit-signals=true sync=false drop=true"
                      ).arg(source);
    } else {
        // RTSP 模式
        // rtspsrc -> depay -> parse -> tee -> ...
        pipeStr = QString(
                      "rtspsrc location=%1 latency=200 ! "
                      "rtph265depay ! h265parse ! " // 如果是H264流，请自行改为 h264parse
                      "tee name=t ! queue ! "
                      "%2 ! " // 解码器
                      "videoconvert ! video/x-raw,format=RGBA ! "
                      "appsink name=mysink emit-signals=true sync=false drop=true"
                      ).arg(source, decoderName);
    }

    qDebug() << "Pipeline:" << pipeStr;

    GError *error = nullptr;
    m_pipeline = gst_parse_launch(pipeStr.toUtf8().constData(), &error);

    if (error) {
        emit errorMessage(QString("Pipeline Error: %1").arg(error->message));
        g_error_free(error);
        return;
    }

    m_tee = gst_bin_get_by_name(GST_BIN(m_pipeline), "t");
    m_appsink = gst_bin_get_by_name(GST_BIN(m_pipeline), "mysink");

    if (m_appsink) {
        g_signal_connect(m_appsink, "new-sample", G_CALLBACK(on_new_sample), this);
        gst_object_unref(m_appsink);
    } else {
        emit errorMessage("AppSink not found");
        return;
    }

    if (gst_element_set_state(m_pipeline, GST_STATE_PLAYING) == GST_STATE_CHANGE_FAILURE) {
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

void VideoBackend::toggleRecording()
{
    if (!m_isPlaying || !m_pipeline || !m_tee) {
        emit errorMessage("Cannot record: Video not playing");
        return;
    }

    if (m_isRecording) {
        stopRecordingInternal();
    } else {
        // --- 开始录制 ---
        QString timestamp = QDateTime::currentDateTime().toString("yyyyMMdd_HHmmss");

        // 路径清理
        QString cleanPath = m_recordPath;
        if (cleanPath.startsWith("file:///")) cleanPath = cleanPath.mid(8);
        else if (cleanPath.startsWith("file://")) cleanPath = cleanPath.mid(7);
        if (cleanPath.startsWith("/") && cleanPath.contains(":")) cleanPath = cleanPath.mid(1);

        // 使用 .mkv (容错率高)
        QString filename = QString("%1/video_%2.mkv").arg(cleanPath, timestamp);
        qDebug() << "Recording to:" << filename;

        // 1. 创建通用元件
        GstElement *queue = gst_element_factory_make("queue", "rec_queue");
        GstElement *mux = gst_element_factory_make("matroskamux", "rec_mux");
        GstElement *sink = gst_element_factory_make("filesink", "rec_sink");

        // 【关键修复 2】：设置 filesink async=false，防止阻塞主管道
        if (sink) g_object_set(sink, "async", FALSE, NULL);

        // 2. 适配层：解决格式冲突
        GstElement *adapter = nullptr; // 编码或解析
        GstElement *converter = nullptr; // 【关键修复 1】：颜色转换

        if (m_isCamera) {
            // 摄像头模式 (数据源是 RGBA)
            // 必须：RGBA -> videoconvert -> YUV -> x264enc -> mux
            converter = gst_element_factory_make("videoconvert", "rec_convert");
            adapter = gst_element_factory_make("x264enc", "rec_enc");
            if(adapter) {
                // 实时录制优化参数
                g_object_set(adapter, "tune", 0x00000004, "speed-preset", 1, "bitrate", 2000, NULL);
            }
        } else {
            // RTSP 模式 (数据源是 H265/H264)
            // 不需要 videoconvert，只需要 parser
            // 假设是 H265。如果是 H264 (BigBuckBunny)，这里一定要改 h264parse！
            adapter = gst_element_factory_make("h265parse", "rec_parse");
            if(adapter) g_object_set(adapter, "config-interval", -1, NULL);
        }

        if (!queue || !mux || !sink || !adapter || (m_isCamera && !converter)) {
            emit errorMessage("Failed to create recording elements");
            return;
        }

        g_object_set(sink, "location", filename.toUtf8().constData(), NULL);

        // 3. 创建 Bin
        m_recBin = gst_bin_new("rec_bin");

        if (m_isCamera) {
            // 摄像头：加入 converter
            gst_bin_add_many(GST_BIN(m_recBin), queue, converter, adapter, mux, sink, NULL);
            // queue -> converter -> encoder -> mux -> sink
            if (!gst_element_link_many(queue, converter, adapter, mux, sink, NULL)) {
                emit errorMessage("Failed to link camera recording elements"); return;
            }
        } else {
            // RTSP：直接连接
            gst_bin_add_many(GST_BIN(m_recBin), queue, adapter, mux, sink, NULL);
            // queue -> parser -> mux -> sink
            if (!gst_element_link_many(queue, adapter, mux, sink, NULL)) {
                emit errorMessage("Failed to link RTSP recording elements"); return;
            }
        }

        // 4. Ghost Pad (层级修复)
        GstPad *queueSinkPad = gst_element_get_static_pad(queue, "sink");
        GstPad *ghostPad = gst_ghost_pad_new("sink", queueSinkPad);
        gst_element_add_pad(m_recBin, ghostPad);
        gst_object_unref(queueSinkPad);

        // 5. 启动并连接
        gst_bin_add(GST_BIN(m_pipeline), m_recBin);
        gst_element_sync_state_with_parent(m_recBin);

        m_teeSrcPad = gst_element_request_pad_simple(m_tee, "src_%u");
        GstPad *binSinkPad = gst_element_get_static_pad(m_recBin, "sink");

        if (gst_pad_link(m_teeSrcPad, binSinkPad) != GST_PAD_LINK_OK) {
            emit errorMessage("Failed to link recording branch");
            stopRecordingInternal();
        } else {
            m_isRecording = true;
            emit isRecordingChanged();
        }

        if (binSinkPad) gst_object_unref(binSinkPad);
    }
}

void VideoBackend::stopRecordingInternal()
{
    if (!m_isRecording || !m_recBin) return;

    qDebug() << "Stopping recording...";

    // 1. 发送 EOS 保证文件完整写入
    GstPad *sinkPad = gst_element_get_static_pad(m_recBin, "sink");
    if (sinkPad) {
        gst_pad_send_event(sinkPad, gst_event_new_eos());
        gst_object_unref(sinkPad);
    }

    // 2. 断开并移除
    if (m_teeSrcPad) {
        gst_pad_unlink(m_teeSrcPad, sinkPad); // 这里的 sinkPad 实际上是 NULL 也可以，只要 src 没问题
        gst_element_release_request_pad(m_tee, m_teeSrcPad);
        gst_object_unref(m_teeSrcPad);
        m_teeSrcPad = nullptr;
    }

    gst_element_set_state(m_recBin, GST_STATE_NULL);
    gst_bin_remove(GST_BIN(m_pipeline), m_recBin);
    m_recBin = nullptr;

    m_isRecording = false;
    emit isRecordingChanged();
}

void VideoBackend::cleanup()
{
    if (m_isRecording) stopRecordingInternal();
    if (m_tee) { gst_object_unref(m_tee); m_tee = nullptr; }
    if (m_pipeline) {
        gst_element_set_state(m_pipeline, GST_STATE_NULL);
        gst_object_unref(m_pipeline);
        m_pipeline = nullptr;
    }
    m_appsink = nullptr;
    m_isPlaying = false;
    emit isPlayingChanged();
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
        QVideoFrameFormat format(QSize(width, height), QVideoFrameFormat::Format_RGBA8888);
        QVideoFrame frame(format);

        if (frame.map(QVideoFrame::WriteOnly)) {
            memcpy(frame.bits(0), map.data, map.size);
            frame.unmap();
            frame.setStartTime(0);
            m_videoSink->setVideoFrame(frame);
        }
        gst_buffer_unmap(buffer, &map);
    }
}
