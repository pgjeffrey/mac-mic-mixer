---
name: Mac Mic Mixer
description: 遵循 macOS 系统约定的多输入麦克风混音工具
rounded:
  permission-banner: "8pt"
spacing:
  compact: "8pt"
  controls: "10pt"
  group: "12pt"
  section: "24pt"
components:
  mixer-content:
    padding: "{spacing.section}"
  permission-banner:
    rounded: "{rounded.permission-banner}"
    padding: "{spacing.group}"
  input-row:
    padding: "8pt 0"
  input-mute-button:
    width: "98pt"
  gain-readout:
    width: "48pt"
---

# Design System: Mac Mic Mixer

## Overview

**Creative North Star: "macOS 原生操作工具"**

界面延续已确认的单窗口操作流程与 macOS 系统视觉，不引入独立品牌世界。设备选择、实际收音状态、音量和开始/停止操作构成主要层级；使用 SwiftUI 与 AppKit 标准控件，让用户沿用桌面系统的操作习惯。

本文依据 [PRODUCT.md](PRODUCT.md)、[MixerView.swift](app/MixerView.swift)、[MacMicMixerApp.swift](app/MacMicMixerApp.swift)、[MixerModel.swift](app/MixerModel.swift) 与 [Models.swift](app/Models.swift) 记录已实现的源码约定。目标为 Apple 芯片 Mac，运行部署基线为 macOS 13。本次审查范围为 **SOURCE ONLY**：开发主机为 Linux，没有可用的 macOS SDK、当前版本原生截图或运行证据；源码审查通过不等于构建、视觉、辅助功能或真实音频验收完成。

**Key Characteristics:**

- 系统字体、语义颜色、SF Symbols 和原生交互。
- 可滚动的单列窗口，以留白、标题和分隔线组织内容。
- 状态使用文字与符号表达，颜色补充含义。
- 当前运行状态、持续保留的诊断结果与累计计数分别表达。

## Colors

颜色由 macOS 与 SwiftUI 按系统外观和用户强调色解析。源码没有品牌色、固定十六进制配色或明暗主题覆盖；因此 frontmatter 不填入推测的 CSS 色值。原生语义值记录在 `.impeccable/design.json` 的 `extensions.native` 中。

### Primary

- **系统强调色**（`Color.accentColor` / `.accentColor`）：健康状态图标、一般电平条；主要按钮使用 `.borderedProminent` 的系统外观。

### Neutral

- **默认前景与窗口背景**：正文和窗口沿用系统默认值，不设置独立画布颜色。
- **次要前景**（`.secondary` / `Color.secondary`）：状态说明、设备状态、提示、诊断成功结果与辅助文字。成功同时有明确文字和勾号，不单独依赖颜色。
- **第四层级填充**（`.quaternary`）：仅用于麦克风权限提示的圆角背景；这是 SwiftUI 的层级样式，不是固定灰色色板。

### Status

- **系统红色**（`.red` / `Color.red`）：错误与失败的回读验证结果。
- **系统橙色**（`.orange`）：当前电平接近满幅时的电平条，以及输出区的当前警告。累计限幅帧数本身不触发此警告。

**The Semantic Color Rule.** 保留系统语义颜色及其明暗外观适配；不从 Linux 环境推测 macOS 渲染色值，也不把源码颜色声明当作对比度验证。

## Typography

使用 SwiftUI 系统字体，不指定自定义字体家族。文字依赖原生语义样式；不另行固化系统解析后的字号、行高或字距。仅状态图标使用固定尺寸，图标尺寸不属于正文字号。

| 用途 | 已实现样式 |
| --- | --- |
| 产品名 | `.title2.weight(.semibold)` |
| 区域标题、插件提示、空列表标题 | `.headline` |
| 输入序号 | `.subheadline.weight(.medium)` |
| 正文、设备菜单、音量标签、运行状态 | 继承系统默认文字样式 |
| 连接诊断、当前输出警告 | `.callout` |
| 输入状态、操作提示、窗口关闭说明 | `.caption` |
| 音量百分比与诊断计数 | 在现有文字样式上添加 `.monospacedDigit()` |

顶部状态 SF Symbol 使用系统字体尺寸（36pt）；空列表图标使用 `.largeTitle`。说明、错误与状态文案按内容纵向展开；可复制的错误和虚拟麦克风名称启用文本选择。实际换行、文字缩放和截断情况仍需在 Mac 上核验。

## Layout

主窗口使用 `Window`、`ScrollView` 与左对齐的单列 `VStack`。窗口内容的最小尺寸为（640 × 560pt），理想尺寸为（680 × 760pt）；未设置固定最大宽度，也没有网页断点或移动端布局。

内容内边距与主要区域间距使用 `spacing.section`。输入区、输出区和顶部状态横排使用 `spacing.group`；输入行及底部设置使用 `spacing.controls`；输入行上下内边距、诊断内容间距与展开后的顶部间距使用 `spacing.compact`。顶部产品名与状态文字间距为（5pt），空列表上下留白为（28pt）。未显式指定的 `HStack` 间距由 SwiftUI 决定。

顶部状态图标、产品名/状态和主要操作共处一行。下方按条件显示插件提示、权限提示、错误、一般通知和独立诊断结果；随后是输入列表、虚拟输出、启动设置及可展开的连接诊断。输出区与设置区之间、输入行之间使用原生 `Divider`。

输入静音按钮与百分比读数使用 frontmatter 中的固定宽度，让滑块保持对齐；总音量标签宽度为（54pt）。更窄窗口、长设备名称、较多输入及增大的文字是否仍可完整操作，需要原生窗口实测，不能仅凭 `ScrollView` 推断。

## Elevation & Depth

源码没有自定义阴影、材质、渐变或悬浮效果。插件未就绪提示采用系统 `GroupBox`；权限提示采用层级填充；其余内容通过间距、标题和 `Divider` 分组。窗口、菜单、标准控件和确认弹窗的深度由 macOS 管理，不为其编造阴影参数。

## Shapes

按钮、设备选择器、滑块、复选框、进度条、菜单和弹窗使用原生形状。唯一显式圆角是权限提示的 `RoundedRectangle`，对应 `rounded.permission-banner`。输入项是以分隔线分开的普通纵向内容，不使用独立卡片轮廓。

## Components

### 主操作与窗口入口

- 开始/停止混音使用同一个 `.borderedProminent` 按钮，文案跟随期望运行状态；快捷键为 `⌘↩`。忙碌时禁用，尚不可开始时也禁用开始操作。
- 其他动作使用默认系统按钮；移除输入使用 `.borderless` 的 `minus.circle` 按钮，并提供帮助文字和输入序号标签。
- 工具栏与系统 Help 菜单打开使用说明。标准悬停、焦点、按压和禁用外观交由系统控件实现；尚未经过键盘或 VoiceOver 实测。

### 输入行

- 每路使用设备 `Picker`、带文字的静音按钮、连续音量 `Slider`、百分比读数和电平条。
- 输入行的状态文字区分未选择、未连接、已连接、等待收音、已静音与正在收音。静音具有明确文案与不同 SF Symbol。
- 混音运行或忙碌时禁用设备选择、增删输入；音量和静音可在运行期间调整。输入与总音量滑块范围均为（0%–150%）。
- 已选择但断开的设备保留名称并标注“未连接”；其他输入已选设备不重复提供为候选项。

### 电平与限幅

- `LevelMeter` 使用原生 `ProgressView`，将线性峰值以对数方式映射到（−60–0dB）显示范围，并钳制在（0–1）。
- 当前峰值超过（0.95）时电平条显示橙色；只有当前输出峰值达到同一条件时，输出区才显示“电平接近满幅”警告。
- “本次运行累计输出限幅帧”位于连接诊断中，表达历史累计计数。它不表示当前仍在限幅；说明文字提示关注持续增长或听到断音的情况。
- 每个电平条在源码中具有独立的辅助功能标签和分贝值/“无信号”描述；装饰图标对辅助功能隐藏。实际读屏频率、朗读值和遍历顺序仍待验证。

### 恢复提示与连接诊断

- 插件未就绪使用 `GroupBox` 提供重新检查与安装说明；权限拒绝/受限时提供打开系统设置的动作。错误使用红色文字加符号，并允许复制。
- 诊断结果使用独立的 `diagnosticMessage` / `diagnosticPassed`，显示在输入区之前；普通刷新、自动恢复和恢复混音不会清除结果。下一次确认执行回读验证时才清除上次结果；结果不作为持久设置保存。
- `DisclosureGroup` 收纳驱动版本、丢帧/欠载计数、累计限幅帧与主动回读验证。按钮标注省略号，因为继续操作前会显示原生 `NSAlert`。
- 回读确认明确说明暂停混音、约四秒测试音，以及其他应用也会收到测试音；提供执行与取消。完成后显示结果，并按先前状态恢复混音。这些是源码行为，不是本次真实音频验证结果。

### 启动设置与菜单栏

- 两项持久行为设置使用 `.toggleStyle(.checkbox)`：打开应用时自动开始已配置混音、登录 Mac 时启动。它们是桌面复选框，不改用移动端开关造型。
- 关闭窗口继续运行；菜单栏 `MenuBarExtra` 提供运行状态、打开窗口、开始/停止及退出。健康时使用 `waveform`，其他状态使用 `mic`。
- `⌘Q` 退出应用并等待音频引擎收尾；关闭窗口与退出的区别在窗口内有明确文字。

## Do's and Don'ts

### Do:

- **Do** 延用 SwiftUI/AppKit 标准控件、系统语义字体颜色与 SF Symbols。
- **Do** 使用文字和图标共同表达状态，并区分当前音频状态、历史累计计数与独立诊断结果。
- **Do** 延用已记录的点值间距、音量读数对齐和单列滚动布局。
- **Do** 在 macOS 13 及目标 Apple 芯片设备上补充构建、安装、真实音频、明暗外观、窗口缩放、键盘和 VoiceOver 验证，再作运行或辅助功能结论。

### Don't:

- **Don't** 以网页/移动端样式替代当前 macOS 控件，或为工具附加未经请求的品牌视觉。
- **Don't** 把累计限幅帧当作当前持续警告，或用普通刷新清除用户刚获得的诊断结果。
- **Don't** 把系统语义色替换为猜测的固定色值，或为原生控件伪造 HTML/CSS 预览与截图依据。
- **Don't** 把源码标签、状态文案或 SOURCE ONLY 审查当作真实设备、视觉对比度、键盘或 VoiceOver 验收。
