---
name: Mac Mic Mixer
description: 遵循 macOS 系统约定的多输入麦克风混音工具
rounded:
  input-card: "12pt"
  feedback-banner: "12pt"
spacing:
  compact: "8pt"
  controls: "10pt"
  group: "12pt"
  feedback: "14pt"
  card: "16pt"
  content: "20pt"
components:
  mixer-content:
    padding: "{spacing.content}"
  mixer-header:
    padding: "12pt 20pt"
  feedback-banner:
    rounded: "{rounded.feedback-banner}"
    padding: "{spacing.feedback}"
  input-card:
    rounded: "{rounded.input-card}"
    padding: "{spacing.card}"
  input-device:
    height: "26pt"
  gain-readout:
    width: "42pt"
  output-bar:
    padding: "14pt 20pt"
  settings-panel:
    padding: "{spacing.content}"
    width: "360pt"
---

# Design System: Mac Mic Mixer

## Overview

**Creative North Star: "macOS 原生操作工具"**

界面延续已确认的单窗口操作流程与 macOS 系统视觉。设备选择、实际收音状态、音量和开始/停止操作构成主要层级。使用 SwiftUI 与 AppKit 标准控件，让用户沿用桌面系统的操作习惯。

本文依据 [MixerView.swift](app/MixerView.swift)、[MacMicMixerApp.swift](app/MacMicMixerApp.swift)、[MixerModel.swift](app/MixerModel.swift)、[Models.swift](app/Models.swift) 与用户确认的卡片布局，记录当前实现。目标为 Apple 芯片 Mac，运行部署基线为 macOS 13。macOS 原生界面夹具以 `NSHostingView` 承载当前 SwiftUI 视图，替换 `MixerModel` 数据，覆盖两路、四路、宽窗口、深色、最小窗口、停止、断线、空态、设置面板与启动状态切换，存于 `.build/ui-qa/`。夹具中的电平与设备状态来自测试数据。

已安装应用的当前截图存于 `.build/logs/card-ui-installed.png`，其中 `MiRemoteV 2ch` 和 `Wireless Mic Rx` 的卡片完整显示，两路均显示“正在收音”。用户点击开始后确认“正常显示，两路都在收音”。目标应用听感、回读及长期稳定性按[验证记录](docs/validation.md)单独验收。

**Key Characteristics:**

- 系统字体、语义颜色、SF Symbols 和原生交互。
- 窗口宽度固定为（640pt），紧凑输入卡片组成两列网格，中部滚动，顶部与底部操作固定可见。
- 状态使用文字与符号表达，颜色补充含义。
- 当前运行状态、持续保留的诊断结果与累计计数分别表达。

## Colors

颜色由 macOS 与 SwiftUI 按系统外观和用户强调色解析。frontmatter 保留点值几何参数，原生语义颜色记录在 `.impeccable/design.json` 的 `extensions.native` 中。

### Primary

- **系统强调色**（`.accentColor`）用于一般电平条。主要按钮使用 `.borderedProminent` 的系统外观。

### Neutral

- **主要前景**（`.primary` / `Color.primary`）用于正文、设备名称与状态文字。卡片边线以主要前景的低不透明度（0.08）绘制。
- **次要前景**（`.secondary` / `Color.secondary`）用于输入序号、辅助文案、通知、停止或静音图标与成功诊断结果。
- **窗口表面**（`Color(nsColor: .windowBackgroundColor)`）用于紧凑顶部栏。
- **内容底色**（`Color(nsColor: .underPageBackgroundColor)`）用于中部滚动区域及窗口内容基底。
- **控件表面**（`Color(nsColor: .controlBackgroundColor)`）用于输入卡片与固定输出栏。

### Status

- **系统红色**（`.red` / `Color.red`）用于错误与失败的回读验证结果。
- **系统绿色**（`.green` / `Color.green`）用于健康的顶部状态图标与运行期间有效、未静音输入的图标。
- **系统橙色**（`.orange`）用于断线或等待收音的输入图标、当前电平接近满幅时的电平条与输出警告。插件和权限提示背景使用系统橙色的低不透明度（0.08）。累计限幅帧数本身不触发当前警告。

**The Semantic Color Rule.** 保留系统语义颜色及其明暗外观适配。对比度结论以原生渲染和测量为依据。

## Typography

使用 SwiftUI 系统字体。文字层级依赖原生语义样式，系统解析字号、行高和字距。固定图标尺寸独立于正文字号。

| 用途 | 已实现样式 |
| --- | --- |
| 顶部区域标题、运行时设备名、插件提示、空列表与设置标题 | `.headline` |
| 连接诊断标题 | `.subheadline.weight(.semibold)` |
| 输入序号 | `.caption.weight(.medium)` |
| 正文、设备菜单、复选框 | 继承系统默认文字样式 |
| 连接诊断、音量读数、总音量标签 | `.callout` |
| 输出名称 | `.callout.weight(.medium)` |
| 输入数量、运行及输入状态、输出标签、警告、操作提示、窗口关闭说明 | `.caption` |
| 音量百分比与诊断计数 | 在现有文字样式上添加 `.monospacedDigit()` |

空列表 SF Symbol 使用系统字体尺寸（28pt）。说明与错误按内容纵向展开，可复制的错误和虚拟麦克风名称启用文本选择。顶部状态限制一行并提供完整帮助文字。运行中的设备名限制一行、中间截断，并通过帮助文字与辅助功能标签保留完整名称。

## Layout

主窗口使用 `Window` 与零间距纵向容器。顶部栏和底部输出栏位于 `ScrollView` 之外，中部输入区域独立滚动。窗口内容最小尺寸为（640 × 420pt），最小、理想和最大宽度均为（640pt）。窗口使用 `.windowResizability(.contentSize)` 传递原生尺寸约束，允许调整高度。输入不超过两路时默认与理想高度为（420pt），超过两路时为（560pt）。

输入使用 `VStack` 直接排列行，每行使用 `HStack` 排列两张等宽卡片，行列间距均为 `spacing.group`。每张卡片保留 `.id(input.id)`，不足一行时以透明占位保持列宽。中部内容内边距使用 `spacing.content`，反馈与网格间距使用 `spacing.card`。两路并排，四路形成两行。

顶部以输入标题、数量和运行状态为左侧层级，右侧排列添加输入与设置。顶部水平元素间距使用 `spacing.card`，标题与状态间距为（4pt）。底部第一行排列输出名称、电平与开始/停止按钮，第二行排列总音量、读数和关闭窗口说明。顶部与中部、中部与底部之间使用原生 `Divider`。启动设置、连接诊断及帮助收纳在设置弹出面板。

卡片内纵向间距使用 `spacing.group`，音量控制行使用 `spacing.controls`，百分比读数右对齐。设备名称或选择器共享 frontmatter 中的高度，保持运行与停止状态的卡片节奏。空列表区域最小高度为（220pt）。夹具截图已覆盖最小窗口及较多输入，文字缩放、完整键盘与辅助功能交互需要单独核验。

## Elevation & Depth

输入卡片通过语义表面、轻边线与留白和内容底色分层。插件与权限提示使用低不透明度的系统橙色填充。窗口、弹出面板、菜单、标准控件和确认弹窗的深度由 macOS 管理。实现沿用原生阴影和材质行为。

## Shapes

按钮、设备选择器、滑块、复选框、进度条、菜单和弹窗使用原生形状。输入卡片与反馈提示使用 `RoundedRectangle`，圆角分别对应 `rounded.input-card` 和 `rounded.feedback-banner`。卡片边线贴合相同圆角轮廓。

## Components

### 主操作与窗口入口

- 固定底部输出栏中的开始/停止混音使用同一个 `.borderedProminent`、`.controlSize(.large)` 按钮，文字区分开始待命、停止待命与混音启停，播放/停止图标跟随启用状态。快捷键为 `⌘↩`。忙碌时禁用，尚不可开始时也禁用开始操作。
- 添加输入位于顶部，移除输入收纳在各卡片的省略号菜单中。菜单使用 `.borderlessButton` 与隐藏菜单指示器，移除项具有 `.destructive` 角色。设置齿轮与卡片菜单具有帮助文字和辅助功能标签。
- 设置弹出面板与系统 Help 菜单打开使用说明。标准悬停、焦点、按压和禁用外观交由系统控件实现。键盘或 VoiceOver 实测另行记录。

### 输入卡片

- 每路卡片按输入序号/状态/操作菜单、设备、电平、音量/读数/静音排列。静音使用 `.toggleStyle(.button)` 与 `.controlSize(.small)`，以选中外观及 SF Symbol 表达状态。
- 启用后（包含待命）设备显示为 `.headline` 名称文字，停止后显示原生设备 `Picker`。忙碌时禁用选择器，运行或忙碌时禁用增删输入。音量和静音可在运行期间调整，输入与总音量滑块范围均为（0%–150%）。
- 状态文字区分未选择设备、设备未连接、已连接、待命、等待收音、已静音与正在收音。待命用时钟符号表达。连接与收音状态具有明确文字，图标颜色补充状态。
- 已选择但断开的设备保留名称，停止时选择器候选项标注“未连接”。其他输入已选设备不重复提供为候选项。断线卡片电平归零。

### 电平与限幅

- `LevelMeter` 使用原生 `ProgressView`，将线性峰值以对数方式映射到（−60–0dB）显示范围，并钳制在（0–1）。
- 当前峰值超过（0.95）时电平条显示橙色；只有当前输出峰值达到同一条件时，输出区才显示“电平接近满幅”警告。
- “累计限幅帧”位于设置面板的连接诊断中，表达本次运行历史累计计数。说明文字提示关注持续增长或听到断音的情况。
- 每个电平条在源码中具有独立的辅助功能标签和分贝值/“无信号”描述，空态装饰图标对辅助功能隐藏。实际读屏频率、朗读值和遍历顺序仍待验证。

### 恢复提示与连接诊断

- 插件未就绪与权限拒绝/受限提示位于滚动区域顶部，分别提供重新检查/安装说明与打开系统设置的动作。错误使用红色文字加符号，并允许复制。
- 诊断结果使用独立的 `diagnosticMessage` / `diagnosticPassed`，显示在输入区之前；普通刷新、自动恢复和恢复混音不会清除结果。下一次确认执行回读验证时才清除上次结果；结果不作为持久设置保存。
- 顶部齿轮打开原生 `.popover`，其中 `MixerSettingsPanel` 收纳启动设置、驱动版本、丢帧/欠载计数、累计限幅帧、主动回读验证与帮助。面板内分组使用 `Divider`。验证按钮关闭弹出面板后再调用诊断，继续前显示原生 `NSAlert`。
- 回读确认明确说明暂停混音、约四秒测试音，以及其他应用也会收到测试音，并提供执行与取消。完成后显示结果，按先前状态恢复混音。这些行为由生产模型实现，界面截图使用夹具状态。

### 启动设置与菜单栏

- 按需采集、打开应用时自动待命或混音、登录 Mac 时启动，均使用 `.toggleStyle(.checkbox)`。按需模式提供使用时采集、结束后释放的说明，忙碌时禁用模式切换。
- 关闭窗口继续运行；菜单栏 `MenuBarExtra` 提供运行状态、打开窗口、开始/停止及退出。健康时使用 `waveform`，其他状态使用 `mic`。
- `⌘Q` 退出应用并等待音频引擎收尾；关闭窗口与退出的区别在窗口内有明确文字。

## Do's and Don'ts

### Do:

- **Do** 延用 SwiftUI/AppKit 标准控件、系统语义字体颜色与 SF Symbols。
- **Do** 使用文字和图标共同表达状态，并区分当前音频状态、历史累计计数与独立诊断结果。
- **Do** 延用已记录的点值间距、卡片网格、音量读数对齐和固定输出栏。
- **Do** 用原生明暗外观及窗口尺寸截图检查布局，并分别记录 macOS 13 兼容性、真实音频、键盘和 VoiceOver 验证。

### Don't:

- **Don't** 以网页/移动端样式替代当前 macOS 控件，或为工具附加未经请求的品牌视觉。
- **Don't** 把累计限幅帧当作当前持续警告，或用普通刷新清除用户刚获得的诊断结果。
- **Don't** 把系统语义色替换为猜测的固定色值，或为原生控件伪造 HTML/CSS 预览与截图依据。
- **Don't** 把夹具电平、设备状态或源码辅助功能标签当作真实音频、视觉对比度、键盘或 VoiceOver 验收。
