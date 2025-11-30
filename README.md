## 介绍
  使用qt和gstreamer实现的一个现代化界面的rtsp视频流播放器。
  - 支持h265解码，url设置，播放暂停

---
## 环境
  - Qt6.7.3
  - Gstreamer1.26.8

---
## 环境配置

### QT
    官网下载在线安装器即可
    
### Gstreamer
 - MSVC 64-bit (VS 2019, Release CRT)
    - 1.26.8 runtime installer
    - 1.26.8 development installer
> tips: 先下载runtime后下载dev，路径一样。下载安装后，需要配置环境变量，将gstreamer的bin目录添加到path中，否则会报错

> GSTREAMER_ROOT_X86_64 = C:\gstreamer\1.0\x86_64
> 
> GST_PLUGIN_PATH = %GSTREAMER_ROOT_X86_64%\lib\gstreamer-1.0

---
## 编译

在QT Creater中打开CMakeLists.txt，点击编译运行即可
    
---
## 打包exe

在QT Creater中打开CMakeLists.txt，点击构建，选择Release模式，然后点击构建，即可生成exe文件
新建一个打包用的文件夹，然后将exe放入
在QT 6.7.3 （MSVC 2022 64-bit）终端中，执行以下命令
``` bash
cd /d "你的打包文件夹路径"

# 假设你的源码（包含 Main.qml 的那个目录）在 C:\Projects\MyStreamPlayer
windeployqt --qmldir "C:\Projects\MyStreamPlayer" --dir . appGstPlayer.exe
```
- 检查是否有QtQuick、QtMultimedia、QtQml等文件夹，没有的话需要到QT的安装目录中（C:\Qt\...\qml\QtMultimedia）拷贝文件夹到该exe目录下
    
>   复制核心 DLL：
    打开 C:\gstreamer\1.0\msvc_x86_64\bin。
    全选 里面的所有 .dll 文件（虽然有点暴力，但这是最稳妥不报错的方法，大约几百 MB）。
    复制 到你的 MyVideoPlayer 文件夹（和 .exe 放在一起）。

>    复制 GStreamer 插件：
    在 MyVideoPlayer 文件夹里新建一个文件夹，命名为 gst-plugins。
    打开 C:\gstreamer\1.0\msvc_x86_64\lib\gstreamer-1.0。
    全选 里面的所有 .dll 文件。
    复制 到你刚才新建的 gst-plugins 文件夹中。  
>   创建一个bat用来设置相关插件的路径和启动程序
``` bat
    @echo off
    setlocal

    :: 获取当前目录
    set "APP_DIR=%~dp0"

    :: Set path for DLLs
    set "PATH=%APP_DIR%;%PATH%"

    :: Set path for GStreamer plugins
    set "GST_PLUGIN_PATH=%APP_DIR%gst-plugins"

    :: Set path for QML modules
    set "QML2_IMPORT_PATH=%APP_DIR%"

    :: 【新增】强制使用 Material 风格 (解决 QQuickRectangle 警告)
    set "QT_QUICK_CONTROLS_STYLE=Material"

    :: 启动程序
    start "" "%APP_DIR%appGstPlayer.exe"

    endlocal

```
