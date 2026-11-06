# 实现架构

## 模块与接口

```text
SwiftUI 应用
  └─ EngineWorker（单一串行控制队列）
      └─ MixerBridge C 接口
          ├─ Core Audio 设备枚举与 UID 查找
          ├─ libobs 生命周期、采集模块和音频混合
          ├─ AudioPipe 有界 SPSC 缓冲
          └─ HALOutput → 隐藏输出 MacMicMixer_2_UID
                                  ↓ BlackHole 环形缓冲
其他 App ← 公开输入 MacMicMixer_UID（Mac Mic Mixer）
```

外部接口集中在 [MixerBridge.h](../native/include/MixerBridge.h)：设备列表、启动、音量控制、停止、状态快照和虚拟麦克风回读验证。控制调用全部位于同一串行队列，音频回调仅读写预分配缓冲和原子状态。

`EngineWorker` 的完成回调明确隔离到 `MainActor`，计时器与电源通知也切回该隔离域更新界面状态。跨队列设置和状态载荷使用可发送的值类型；C 句柄仅在音频串行控制队列内创建、访问和销毁。

## 采集和混音

[input-module.c](../native/input-module.c) 注册上游 `coreaudio_input_capture`，编译固定版本的 `mac-audio.c` 和设备枚举源码，不修改上游文件。每个选中 UID 对应一个私有 OBS 输入源；强制单声道后进入同一混音场景。

OBS 33 的混音根节点来自视频主画布。为保留正式 libobs 混音实现，初始化隐藏的 16 × 16、1 fps Metal 主画布，使用同一场景激活和混合输入。因此软件仍需打包 `libobs-metal` 和相应依赖，但没有视频界面或录制输出。

libobs 的 macOS 资源查找使用框架自身的 `Resources`，构建脚本会验证并保留其 effect 文件。引擎为 OBS 注册主线程任务调度，在异步退出流程中保持主线程可用。

OBS 负责输入格式转换和源时序处理，内部使用 48 kHz 浮点音频。输入增益、静音以及总增益在 OBS 内应用，总增益位于最终混合限幅之前。`audio_output_connect` 提供交错双声道混音回调。

## 输出缓冲与虚拟设备

[AudioPipe.hpp](../native/core/AudioPipe.hpp) 将最终双声道折叠为相同的单声道内容，并将其复制到输出左右声道。缓冲为单生产者、单消费者，容量固定；满时记录丢帧，欠载输出静音，积压超过阈值时由消费者丢弃旧数据以限制延迟。

本项目 [HALOutput](../native/HALOutput.cpp) 通过 Audio Unit 输出到已安装驱动的隐藏输出。输出状态同时检查 OBS 混音回调、HAL 渲染回调、设备存活与错误，输入状态根据实际捕获回调更新。电平为零不被视为故障，静音不会被误判为掉线。

驱动使用 BlackHole 原始 C 源码，通过 [DriverConfig.h](../native/driver/DriverConfig.h) 定义本项目身份：

- `com.macmicmixer.driver`：插件标识。
- `MacMicMixer_UID`：公开、仅输入的虚拟麦克风。
- `MacMicMixer_2_UID`：隐藏、仅输出的写入端。
- `Mac Mic Mixer`：用户在目标应用中选择的名称。

虚拟设备硬件格式固定为 48 kHz、两声道 Float32，避免多个接收应用修改同一个虚拟设备时钟。输入的其他采样率由 OBS 转换；目标应用按设备公布的格式读取。实际接收应用兼容性仍需验证。

两个端点使用同一个驱动内部环形缓冲。独立 `Info.plist`、工厂 UUID 和图标避免与官方 BlackHole 安装冲突。

## 生命周期与恢复

- 配置按 UID 存储在当前用户 `Application Support/MacMicMixer/settings.json`，原子写入。
- 设备列表周期刷新；保存的设备暂时缺失时保留原选择。
- 运行中音量与静音可修改；更换、增加或删除输入需要先停止。
- 输入重连复用上游采集模块的恢复逻辑；输出异常采用有上限间隔的退避重建。
- 系统休眠时停止音频链路，唤醒后在原运行意图仍有效时尝试恢复。
- 登录时尚未连接的已配置输入到达后，可继续完成自动启动。
- 关闭窗口继续运行；正常退出采用异步终止回调，等待音频资源释放后让应用退出，避免阻塞主线程。

## 回读验证

[LoopbackProbe](../native/LoopbackProbe.cpp) 读取公开虚拟输入。用户明确启动诊断后，两个独立 OBS 测试源发送 997 Hz 与 1499 Hz 音调，混音经正常输出路径进入驱动。回读端跳过启动阶段后，检查两种音调的相关幅度、采样帧数和左右声道一致性。

该检查覆盖软件源、混音、输出、虚拟设备和回读，不包含真实蓝牙设备识别或传输，因此不能代替实际设备验收。诊断结束后恢复此前混音，验证结果独立保留。

## 构建与分发

[build_macos.py](../tools/build_macos.py) 先构建固定 OBS 库，再构建桥接和小型输入模块，编译原生应用和定制驱动。依赖闭包收集会修正动态库加载路径，检查不存在构建机绝对路径，并在修改加载命令后按内部到外部顺序签名。

因为应用通过 `swiftc` 构建，脚本显式调用 `swift-stdlib-tool` 收集应用和 Metal 库所需的 Swift 运行库。动态库解析按目标架构读取，保留 Framework 的版本与资源符号链接；不同内容的库若将占用同一路径则停止打包，路径重写也不得越出应用包。

[package_macos.py](../tools/package_macos.py) 生成安装和卸载包；安装阶段不从 root 启动桌面程序，也不强杀共享音频服务，而是由安装器要求重启。卸载前验证固定路径的 bundle 标识，保留其他音频软件及用户设置。

脚本在执行任何宿主机操作前拒绝其他磁盘作为安装或卸载目标，避免固定系统路径与所选目标卷不一致。源码归档会同时生成 SHA-256 校验文件。

当前仅有 Linux 检查证据。Mac 编译、驱动加载、真实客户端回读及稳定性结论均待对应环境验证。
