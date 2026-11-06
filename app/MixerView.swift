import SwiftUI

struct MixerView: View {
    @ObservedObject var model: MixerModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: model.healthy ? "waveform.circle.fill" : "mic.circle")
                        .font(.system(size: 36)).foregroundStyle(model.healthy ? Color.accentColor : .secondary)
                        .accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 5) {
                        Text("Mac Mic Mixer").font(.title2.weight(.semibold))
                        Text(model.statusTitle).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer()
                    Button(model.desiredRunning ? "停止混音" : "开始混音") {
                        if model.desiredRunning { model.stop() } else { model.start() }
                    }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(model.busy || (!model.desiredRunning && !model.canStart))
                }

                if !model.driverInstalled {
                    GroupBox {
                        VStack(alignment: .leading, spacing: 10) {
                            Label("虚拟麦克风尚未就绪", systemImage: "exclamationmark.triangle")
                                .font(.headline)
                            Text("请使用完整的 Mac Mic Mixer 安装包安装应用和虚拟麦克风，然后重启 Mac。")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            HStack {
                                Button("重新检查") { model.refresh() }
                                Button("查看安装说明") { model.openHelp() }
                            }
                        }.frame(maxWidth: .infinity, alignment: .leading).padding(8)
                    }
                }

                if model.permission == .denied || model.permission == .restricted {
                    HStack(alignment: .top) {
                        Label("需要麦克风权限才能读取所选输入。", systemImage: "mic.slash")
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer()
                        Button("打开系统设置") { model.openMicrophoneSettings() }
                    }
                    .padding(12).background(.quaternary, in: RoundedRectangle(cornerRadius: 8))
                }

                if let error = model.errorMessage {
                    Label(error, systemImage: "exclamationmark.circle.fill")
                        .foregroundStyle(.red).fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
                if let notice = model.notice {
                    Label(notice, systemImage: "info.circle").foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if let result = model.diagnosticMessage {
                    Label(result, systemImage: model.diagnosticPassed ? "checkmark.circle" : "exclamationmark.circle")
                        .foregroundStyle(model.diagnosticPassed ? Color.secondary : Color.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("音频输入").font(.headline)
                        Spacer()
                        Button { model.addInput() } label: { Label("添加输入", systemImage: "plus") }
                            .disabled(model.desiredRunning || model.busy)
                    }
                    if model.settings.inputs.isEmpty {
                        VStack(spacing: 10) {
                            Image(systemName: "mic.badge.plus").font(.largeTitle).foregroundStyle(.secondary)
                                .accessibilityHidden(true)
                            Text("选择要合并的麦克风").font(.headline)
                            Text("点击“添加输入”，选择蓝牙、USB、内置或虚拟输入。")
                                .foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("添加第一个输入") { model.addInput() }.disabled(model.busy)
                        }.frame(maxWidth: .infinity).padding(.vertical, 28)
                    } else {
                        ForEach(Array(model.settings.inputs.enumerated()), id: \.element.id) { index, input in
                            InputRow(model: model, input: input, index: index + 1)
                            if index < model.settings.inputs.count - 1 { Divider() }
                        }
                    }
                    if model.desiredRunning {
                        Text("停止混音后可以调整输入设备，音量和静音可随时修改。")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Divider()
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("虚拟麦克风").font(.headline)
                        Spacer()
                        Text("Mac Mic Mixer").foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Text("在其他 App 的麦克风设置中选择此名称，即可收到上方所有输入的混合声音。")
                        .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                    LevelMeter(level: model.status.outputPeak, label: "混合输出电平")
                    HStack {
                        Text("总音量").frame(width: 54, alignment: .leading)
                        Slider(value: Binding(get: { model.settings.masterGain }, set: model.setMasterGain), in: 0...1.5)
                            .accessibilityLabel("总音量")
                        Text(model.settings.masterGain, format: .percent.precision(.fractionLength(0)))
                            .monospacedDigit().frame(width: 48, alignment: .trailing)
                    }
                    if model.status.outputPeak > 0.95 {
                        Label("电平接近满幅，请适当降低输入或总音量。", systemImage: "exclamationmark.triangle")
                            .font(.callout).foregroundStyle(.orange)
                    }
                }

                Divider()
                VStack(alignment: .leading, spacing: 10) {
                    Toggle("打开应用时自动开始已配置的混音", isOn: Binding(
                        get: { model.settings.startOnLaunch }, set: model.setStartOnLaunch))
                    Toggle("登录 Mac 时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
                    Text("关闭窗口后继续收音；退出应用将停止混音。")
                        .font(.caption).foregroundStyle(.secondary)
                    DisclosureGroup("连接诊断") {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("驱动：\(model.driverInstalled ? model.driverVersion : "未就绪")")
                            Text("积压丢帧：\(model.status.droppedFrames) · 缓冲欠载：\(model.status.underrunFrames)")
                                .monospacedDigit()
                            Text("本次运行累计输出限幅帧：\(model.status.clippedFrames)").monospacedDigit()
                            Text("计数在启动时可能增加；持续增长或听到断音时请停止并重新连接设备。")
                                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                            Button("发送测试音并验证虚拟麦克风…") { model.verifyLoopback() }
                                .disabled(model.busy || !model.driverInstalled)
                        }.font(.callout).padding(.top, 8)
                    }
                }.toggleStyle(.checkbox)
            }.padding(24)
        }
        .frame(minWidth: 640, idealWidth: 680, minHeight: 560, idealHeight: 760)
        .toolbar { Button { model.openHelp() } label: { Label("使用说明", systemImage: "questionmark.circle") } }
    }
}

private struct InputRow: View {
    @ObservedObject var model: MixerModel
    let input: InputSelection
    let index: Int
    private var state: InputStatus? { model.status.inputs.first { $0.deviceUID == input.deviceUID } }
    private var statusText: String {
        if input.deviceUID.isEmpty { return "请选择一个输入设备" }
        if !model.devices.contains(where: { $0.uid == input.deviceUID }) { return "设备未连接" }
        if !model.desiredRunning { return "已连接" }
        if state?.receiving != true { return "等待设备收音" }
        return input.muted ? "已静音" : "正在收音"
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("输入 \(index)").font(.subheadline.weight(.medium))
                Spacer()
                Text(statusText).font(.caption).foregroundStyle(.secondary)
                Button { model.removeInput(input.id) } label: { Image(systemName: "minus.circle") }
                    .buttonStyle(.borderless).help("移除此输入").accessibilityLabel("移除输入 \(index)")
                    .disabled(model.desiredRunning || model.busy)
            }
            Picker("设备", selection: Binding(get: { input.deviceUID }, set: { model.selectDevice($0, for: input.id) })) {
                Text("请选择设备").tag("")
                if !input.deviceUID.isEmpty && !model.devices.contains(where: { $0.uid == input.deviceUID }) {
                    Text("\(input.name)（未连接）").tag(input.deviceUID)
                }
                ForEach(model.devices.filter { device in
                    !model.settings.inputs.contains { $0.id != input.id && $0.deviceUID == device.uid }
                }) { device in Text(device.name).tag(device.uid) }
            }.disabled(model.desiredRunning || model.busy)
                .accessibilityLabel("输入 \(index) 设备")
            HStack(spacing: 12) {
                Button { model.setMuted(!input.muted, for: input.id) } label: {
                    Label(input.muted ? "取消静音" : "静音", systemImage: input.muted ? "mic.slash.fill" : "mic.fill")
                }.frame(width: 98).accessibilityLabel("输入 \(index)\(input.muted ? "取消静音" : "静音")")
                Slider(value: Binding(get: { input.gain }, set: { model.setGain($0, for: input.id) }), in: 0...1.5)
                    .accessibilityLabel("输入 \(index) 音量")
                Text(input.gain, format: .percent.precision(.fractionLength(0)))
                    .monospacedDigit().frame(width: 48, alignment: .trailing)
            }
            LevelMeter(level: state?.peak ?? 0, label: "输入 \(index) 电平")
        }.padding(.vertical, 8)
    }
}

private struct LevelMeter: View {
    let level: Float
    let label: String
    private var normalized: Double {
        guard level.isFinite, level > 0 else { return 0 }
        return min(max((20 * log10(Double(level)) + 60) / 60, 0), 1)
    }
    var body: some View {
        ProgressView(value: normalized)
            .tint(level > 0.95 ? .orange : .accentColor)
            .accessibilityLabel(label)
            .accessibilityValue(level > 0 ? String(format: "%.0f 分贝", 20 * log10(Double(level))) : "无信号")
    }
}
