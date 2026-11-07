---
version: 1
slug: "app-mixerview-swift"
primary_target: "app/MixerView.swift"
related_targets: ["app/MacMicMixerApp.swift"]
---

# 混音窗口

平台为原生 macOS SwiftUI，采用 Operate 模式。用户需要同时查看数路麦克风，快速调音量、静音并控制混合输出。

## Direction contract

### THESIS
每个输入拥有紧凑卡片，常用两至四路输入及总输出在默认窗口内同时可见。

### OWN-WORLD
延续 macOS 系统字体、SF Symbols、语义背景与强调色。卡片使用轻边框和连续圆角，明暗外观跟随系统。

### STORY
用户添加输入，查看真实收音状态，分别调节音量与静音，在底部控制混音，并在目标应用选择 Mac Mic Mixer。

### FIRST VIEWPORT
顶部为输入数量、运行状态、添加输入和设置。按用户最新要求，窗口固定为当前最小宽度 640pt，高度可调，输入卡片固定两列。底部固定输出名称、电平、总音量和开始或停止按钮。输入较多时滚动中部区域。

### FORM
采用用户于 2026-11-07 明确确认的两列卡片布局及固定输出栏。卡片略宽于高。设置收纳自动启动、登录启动、诊断与帮助。错误和断线保留就近反馈。

### FINISH
unreviewed and undocumented is unfinished; this build ends with the finish review, the verdict, DESIGN.md, and every shipping raster carrying its provenance

实现使用现有 MixerModel 操作，保持 UID 选择、静音、增益及诊断结果语义。原生窗口最小与最大宽度均验证为 640pt，高度可调。按需采集默认待命，外部软件读取虚拟输入时采集，结束后释放。
