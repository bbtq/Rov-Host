cmake_minimum_required(VERSION 3.16)

project(GstAppSinkPlayer LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)

# =========================================================
# 1. 查找 Qt6 组件
# 注意：必须包含 Multimedia 模块，因为我们用了 QVideoSink
# =========================================================
find_package(Qt6 REQUIRED COMPONENTS Quick Widgets Multimedia)

# =========================================================
# 2. 查找 GStreamer (Windows 特供版配置)
# =========================================================
# 方案 A: 如果你配置好了 pkg-config (推荐但门槛高)
# find_package(PkgConfig REQUIRED)
# pkg_check_modules(GST REQUIRED gstreamer-1.0 gstreamer-video-1.0 gstreamer-app-1.0)

# 方案 B: 手动指定路径 (Windows 上最简单直接，推荐)
# 请根据你的实际安装路径修改 GST_ROOT
set(GST_ROOT "C:/gstreamer/1.0/msvc_x86_64")

set(GST_INCLUDE_DIRS
    "${GST_ROOT}/include/gstreamer-1.0"
    "${GST_ROOT}/include"
    "${GST_ROOT}/lib/glib-2.0/include"
    "${GST_ROOT}/include/glib-2.0"
)

#我们需要链接的核心库
set(GST_LIBRARIES
    "${GST_ROOT}/lib/gstreamer-1.0.lib"
    "${GST_ROOT}/lib/gobject-2.0.lib"
    "${GST_ROOT}/lib/glib-2.0.lib"
    "${GST_ROOT}/lib/gstvideo-1.0.lib"
    "${GST_ROOT}/lib/gstapp-1.0.lib" 
)

# =========================================================
# 3. 项目设置
# =========================================================
qt_standard_project_setup()

qt_add_executable(appGstPlayer
    main.cpp
    VideoBackend.cpp
    VideoBackend.h
)

# 包含 GStreamer 头文件
target_include_directories(appGstPlayer PRIVATE ${GST_INCLUDE_DIRS})

# 链接库：Qt 模块 + GStreamer 库
target_link_libraries(appGstPlayer
    PRIVATE 
    Qt6::Quick 
    Qt6::Widgets 
    Qt6::Multimedia 
    ${GST_LIBRARIES}
)

# =========================================================
# 4. 注册 QML 模块
# =========================================================
qt_add_qml_module(appGstPlayer
    URI Main
    VERSION 1.0
    QML_FILES Main.qml
)

# Windows 专用：为了防止运行时找不到 DLL，可以将 bin 目录加到 PATH (仅调试时有效)
if(WIN32)
    set_property(TARGET appGstPlayer PROPERTY VS_DEBUGGER_ENVIRONMENT "PATH=${GST_ROOT}/bin;%PATH%")
endif()