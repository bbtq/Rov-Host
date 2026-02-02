cmake_minimum_required(VERSION 3.16)

project(json_control VERSION 0.1 LANGUAGES CXX)

set(CMAKE_CXX_STANDARD_REQUIRED ON)

find_package(Qt6 REQUIRED COMPONENTS Quick Network)

qt_standard_project_setup(REQUIRES 6.5)


# --- 配置 SDL2 路径 (请根据实际路径修改) ---
set(SDL2_DIR "${CMAKE_SOURCE_DIR}/SDL2CV") # 假设在项目根目录
include_directories(${SDL2_DIR}/include)
link_directories(${SDL2_DIR}/lib/x64)    # 假设是 64位构建

qt_add_executable(appjson_control
    main.cpp
    RobotClient.cpp
    RobotClient.h
    GamepadBackend.cpp
    GamepadBackend.h
)

qt_add_qml_module(appjson_control
    URI json_control
    QML_FILES
        Main.qml
)

# Qt for iOS sets MACOSX_BUNDLE_GUI_IDENTIFIER automatically since Qt 6.1.
# If you are developing for iOS or macOS you should consider setting an
# explicit, fixed bundle identifier manually though.
set_target_properties(appjson_control PROPERTIES
#    MACOSX_BUNDLE_GUI_IDENTIFIER com.example.appjson_control
    MACOSX_BUNDLE_BUNDLE_VERSION ${PROJECT_VERSION}
    MACOSX_BUNDLE_SHORT_VERSION_STRING ${PROJECT_VERSION_MAJOR}.${PROJECT_VERSION_MINOR}
    MACOSX_BUNDLE TRUE
    WIN32_EXECUTABLE TRUE
)

target_link_libraries(appjson_control
    PRIVATE Qt6::Quick Qt6::Network
    PRIVATE SDL2 # 链接 SDL2.lib
)

include(GNUInstallDirs)
install(TARGETS appjson_control
    BUNDLE DESTINATION .
    LIBRARY DESTINATION ${CMAKE_INSTALL_LIBDIR}
    RUNTIME DESTINATION ${CMAKE_INSTALL_BINDIR}
)
