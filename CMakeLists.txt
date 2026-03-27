cmake_minimum_required(VERSION 3.16)

project(rov_control VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Network Widgets Multimedia QuickControls2)

qt_standard_project_setup(REQUIRES 6.5)


# --- 配置 SDL2 路径 (请根据实际路径修改) ---
set(SDL2_DIR "${CMAKE_SOURCE_DIR}/SDL2CV") # 假设在项目根目录
include_directories(${SDL2_DIR}/include)
link_directories(${SDL2_DIR}/lib/x64)    # 假设是 64位构建

# --- 设置 gstreamer 路径 ---
set(GST_ROOT "C:/gstreamer/1.0/msvc_x86_64")
set(GST_INCLUDE_DIRS
    "${GST_ROOT}/include/gstreamer-1.0"
    "${GST_ROOT}/include"
    "${GST_ROOT}/lib/glib-2.0/include"
    "${GST_ROOT}/include/glib-2.0"
)

set(GST_LIBRARIES
    "${GST_ROOT}/lib/gstreamer-1.0.lib"
    "${GST_ROOT}/lib/gobject-2.0.lib"
    "${GST_ROOT}/lib/glib-2.0.lib"
    "${GST_ROOT}/lib/gstvideo-1.0.lib"
    "${GST_ROOT}/lib/gstapp-1.0.lib"
)

qt_add_executable(approv_control
    main.cpp
    RobotClient.cpp
    RobotClient.h
    GamepadBackend.cpp
    GamepadBackend.h
    VideoBackend.cpp
    VideoBackend.h
)

qt_add_qml_module(approv_control
    URI Main
    QML_FILES
        Main.qml
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(approv_control PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.approv_control
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

# 包含 GStreamer 头文件
target_include_directories(approv_control PRIVATE ${GST_INCLUDE_DIRS})

target_link_libraries(approv_control
    PRIVATE
    Qt6::Quick
    Qt6::Network
    Qt6::Widgets
    Qt6::Multimedia
    Qt6::QuickControls2
    ${GST_LIBRARIES}
    PRIVATE SDL2 # 链接 SDL2.lib
)

include(GNUInstallDirs)
install(TARGETS approv_control
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
