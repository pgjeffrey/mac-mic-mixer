# 第三方源码与查阅索引

本目录保存 Mac Mic Mixer 首版拟复用的两个上游项目。2026-11-06 已从官方 GitHub 仓库获取下列正式版本，保留上游源码、构建文件、文档、许可证及独立 Git 工作区。

```text
third_party/
├── README.md           # 本文件：版本和代码入口
├── obs-studio/         # OBS Studio 上游源码
└── BlackHole/          # BlackHole 上游源码
```

## 1. 固定版本

| 目录 | 官方仓库 | 标签 | 实际提交 |
| --- | --- | --- | --- |
| `obs-studio/` | <https://github.com/obsproject/obs-studio> | `33.0.1` | `65c320b46e1af5c7a555161aea6182cdf7a8c524` |
| `BlackHole/` | <https://github.com/ExistentialAudio/BlackHole> | `v0.7.1` | `e2b22aaaba4e507a097131704bf96dabc004d9cf` |

两个工作区使用 `--depth 1 --branch <标签>` 获取，当前处于固定标签对应的 detached HEAD 状态，仅包含浅历史。本次未修改上游文件，未执行上游构建或安装脚本。

源码归档中的第三方目录不包含 Git 历史，使用 `source-snapshots.json` 保存固定提交与逐文件 SHA-256。`make sources` 同样支持核对这种源码快照，不需要覆盖归档内源码或重新克隆。

OBS 的浏览器插件、WebSocket 插件及 Windows DirectShow 依赖三个 Git 子模块尚未下载；上表中的 OBS 父仓库源码已检出，下面列出的音频代码均可直接查阅。后续构建根据选定功能补齐必要子模块和外部构建依赖，不将当前源码准备状态视为已经具备完整构建环境。

## 2. OBS Studio：采集、混音和输出

| 代码入口 | 作用 |
| --- | --- |
| [README.rst](obs-studio/README.rst) | 上游简介、许可证和开发文档入口 |
| [docs/sphinx/frontends.rst](obs-studio/docs/sphinx/frontends.rst) | 自建前端使用 libobs 的初始化、模块加载和关闭流程 |
| [docs/sphinx/reference-core.rst](obs-studio/docs/sphinx/reference-core.rst) | 核心上下文、音频配置及输出设备等 API 说明 |
| [libobs/obs.h](obs-studio/libobs/obs.h) | libobs 公开接口，包括启动、音频配置和监听输出设备设置 |
| [plugins/mac-capture/mac-audio.c](obs-studio/plugins/mac-capture/mac-audio.c) | macOS 音频输入、回调和设备重连；注册 `coreaudio_input_capture` 输入源 |
| [plugins/mac-capture/audio-device-enum.c](obs-studio/plugins/mac-capture/audio-device-enum.c) | macOS 音频设备枚举 |
| [plugins/mac-capture/plugin-main.c](obs-studio/plugins/mac-capture/plugin-main.c) | macOS 采集插件入口和输入源注册 |
| [libobs/obs-source.c](obs-studio/libobs/obs-source.c) | 输入源生命周期、音频数据及源控制的相关实现 |
| [libobs/obs-audio.c](obs-studio/libobs/obs-audio.c) | 音频线程、缓冲及多源混音，包含 `mix_audio` 和 `audio_callback` |
| [libobs/media-io/audio-io.c](obs-studio/libobs/media-io/audio-io.c) | 音频输出线程、格式转换连接及输出处理 |
| [libobs/media-io/audio-resampler-ffmpeg.c](obs-studio/libobs/media-io/audio-resampler-ffmpeg.c) | 基于 FFmpeg 的重采样实现，存在对应外部依赖 |
| [libobs/obs-audio-controls.c](obs-studio/libobs/obs-audio-controls.c) | 音量控制和电平表相关实现 |
| [libobs/audio-monitoring/osx/coreaudio-output.c](obs-studio/libobs/audio-monitoring/osx/coreaudio-output.c) | macOS 音频监听输出，可用于向虚拟输出设备写入音频 |
| [libobs/audio-monitoring/osx/coreaudio-enum-devices.c](obs-studio/libobs/audio-monitoring/osx/coreaudio-enum-devices.c) | macOS 监听输出设备枚举 |
| [libobs/CMakeLists.txt](obs-studio/libobs/CMakeLists.txt) | 核心库构建边界和依赖 |
| [plugins/mac-capture/CMakeLists.txt](obs-studio/plugins/mac-capture/CMakeLists.txt) | macOS 采集插件源码和框架依赖；当前同时列有音频和视频代码 |
| [COPYING](obs-studio/COPYING) | GPL 许可证正文，版本适用说明见上游 README |

建议按“公开接口 → macOS 输入源 → 音频混合 → macOS 输出 → 构建依赖”的顺序阅读。上述文件存在相互依赖，不能仅将单个 `.c` 文件复制出来就认定它可以独立编译运行。

## 3. BlackHole：虚拟音频设备

| 代码入口 | 作用 |
| --- | --- |
| [README.md](BlackHole/README.md) | 安装、构建、设备定制、采样率及使用说明 |
| [BlackHole/BlackHole.c](BlackHole/BlackHole/BlackHole.c) | Core Audio AudioServerPlugIn 驱动主体、设备属性、时钟和环形缓冲区读写 |
| [BlackHole/BlackHole.plist](BlackHole/BlackHole/BlackHole.plist) | 驱动插件元数据 |
| [BlackHole.xcodeproj/project.pbxproj](BlackHole/BlackHole.xcodeproj/project.pbxproj) | Xcode 工程与构建配置 |
| [Installer/create_installer.sh](BlackHole/Installer/create_installer.sh) | 上游安装包构建、签名等流程参考 |
| [Installer/scripts/preinstall](BlackHole/Installer/scripts/preinstall) | 安装前处理参考 |
| [Installer/scripts/postinstall](BlackHole/Installer/scripts/postinstall) | 安装后处理参考 |
| [LICENSE](BlackHole/LICENSE) | 源码 GPL v3、官方编译产物及品牌资产的许可说明 |

驱动主体中可优先查阅：

- `kDriver_Name`、`kDevice_Name`、`kNumber_Of_Channels`：名称、声道等配置。
- `BlackHole_GetZeroTimeStamp`：虚拟设备时钟。
- `BlackHole_DoIOOperation`：音频输入读取和混音写入。
- `kAudioServerPlugInIOOperationReadInput`、`kAudioServerPlugInIOOperationWriteMix`：音频在环形缓冲区中的流转。

后续基于源码定制设备时，统一处理设备名称、唯一标识、图标、版权与许可证，不直接将官方品牌资产作为本项目品牌使用。

## 4. 后续开发约定

- 先依据根目录 [实施方案](../README.md) 验证最小链路，再决定实际链接和构建范围。
- 保留上游源码结构与出处，应用自身实现放在本项目后续建立的模块中。
- 修改第三方代码前核对工作区状态，避免覆盖已有改动；记录必要补丁和修改原因。
- 更新版本时同时维护本文件中的标签和提交，并重新验证受影响链路。
- 对外分发或初始化父项目版本管理时，明确第三方源码的跟踪与获取方式；当前两个目录是独立 Git 克隆，尚未登记为父仓库子模块。
- 查阅源码无需执行安装脚本。真正的 macOS 构建、驱动安装和音频验收在对应 Mac 环境完成。

在项目根目录可使用以下命令核对版本和本地改动：

```sh
git -C third_party/obs-studio rev-parse HEAD
git -C third_party/obs-studio status --short
git -C third_party/BlackHole rev-parse HEAD
git -C third_party/BlackHole status --short
```

项目已在上游工作区之外实现应用、音频桥接和打包流程；上游文件保持未修改。依赖版本清单见 [sources.json](sources.json)，可通过项目根目录的 `make sources` 重复获取与验证。当前仍未运行 macOS 编译和音频实机验收。
