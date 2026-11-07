import AppKit
import SwiftUI

struct MixerView: View {
    @ObservedObject var model: MixerModel
    @State private var showingSettings = false

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            GeometryReader { _ in
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        feedback
                        if model.settings.inputs.isEmpty {
                            emptyState
                        } else {
                            let columnCount = 2
                            let rowCount = (model.settings.inputs.count + columnCount - 1) / columnCount
                            VStack(spacing: 12) {
                                ForEach(0..<rowCount, id: \.self) { row in
                                    HStack(alignment: .top, spacing: 12) {
                                        ForEach(0..<columnCount, id: \.self) { column in
                                            let index = row * columnCount + column
                                            if index < model.settings.inputs.count {
                                                let input = model.settings.inputs[index]
                                                InputCard(model: model, input: input, index: index + 1)
                                                    .id(input.id)
                                                    .frame(minWidth: 0, maxWidth: .infinity)
                                            } else {
                                                Color.clear.frame(minWidth: 0, maxWidth: .infinity)
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                    .padding(20)
                    .frame(maxWidth: .infinity, alignment: .topLeading)
                }
            }
            Divider()
            OutputBar(model: model)
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .frame(minWidth: 640, idealWidth: 640, maxWidth: 640, minHeight: 420,
               idealHeight: model.settings.inputs.count > 2 ? 560 : 420)
    }

    private var header: some View {
        HStack(spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    Text("音频输入").font(.headline)
                    Text("\(model.settings.inputs.count) 路").font(.caption).foregroundStyle(.secondary)
                }
                Label {
                    Text(model.statusTitle).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: model.waitingForClient ? "clock" : model.healthy ? "checkmark.circle.fill" : "waveform")
                        .foregroundStyle(model.healthy ? Color.green : Color.secondary)
                }
                .font(.caption)
                .lineLimit(1).help(model.statusTitle)
            }
            Spacer(minLength: 12)
            Button { model.addInput() } label: { Label("添加输入", systemImage: "plus") }
                .disabled(model.desiredRunning || model.busy)
                .help(model.desiredRunning ? "停止混音后可以添加输入" : "添加一个音频输入")
            Button { showingSettings.toggle() } label: {
                Image(systemName: "gearshape").frame(width: 20, height: 18)
            }
            .accessibilityLabel("设置与连接诊断").help("设置与连接诊断")
            .popover(isPresented: $showingSettings, arrowEdge: .bottom) {
                MixerSettingsPanel(model: model) {
                    showingSettings = false
                    DispatchQueue.main.async { model.verifyLoopback() }
                }
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 12)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    @ViewBuilder private var feedback: some View {
        if !model.driverInstalled {
            VStack(alignment: .leading, spacing: 8) {
                Label("虚拟麦克风尚未就绪", systemImage: "exclamationmark.triangle").font(.headline)
                Text("请安装完整安装包，并在重启 Mac 后重新检查。").foregroundStyle(.secondary)
                HStack {
                    Button("重新检查") { model.refresh() }
                    Button("查看安装说明") { model.openHelp() }
                }
            }
            .padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        if model.permission == .denied || model.permission == .restricted {
            HStack(spacing: 12) {
                Label("需要麦克风权限才能读取所选输入。", systemImage: "mic.slash")
                Spacer()
                Button("打开系统设置") { model.openMicrophoneSettings() }
            }
            .padding(14)
            .background(Color.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 12))
        }
        if let error = model.errorMessage {
            Label(error, systemImage: "exclamationmark.circle.fill")
                .foregroundStyle(.red).textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
        if let notice = model.notice {
            Label(notice, systemImage: "info.circle")
                .foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
        }
        if let result = model.diagnosticMessage {
            Label(result, systemImage: model.diagnosticPassed ? "checkmark.circle" : "exclamationmark.circle")
                .foregroundStyle(model.diagnosticPassed ? Color.secondary : Color.red)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyState: some View {
        VStack(spacing: 12) {
            Image(systemName: "mic.badge.plus")
                .font(.system(size: 28)).foregroundStyle(.secondary).accessibilityHidden(true)
            Text("添加你的麦克风").font(.headline)
            Text("选择需要合并的音频输入，在这里分别调节音量。").foregroundStyle(.secondary)
            Button("添加第一个输入") { model.addInput() }
                .buttonStyle(.borderedProminent).disabled(model.busy)
        }
        .frame(maxWidth: .infinity, minHeight: 220)
    }
}

private struct InputCard: View {
    @ObservedObject var model: MixerModel
    let input: InputSelection
    let index: Int

    private var state: InputStatus? { model.status.inputs.first { $0.deviceUID == input.deviceUID } }
    private var device: InputDevice? { model.devices.first { $0.uid == input.deviceUID } }
    private var deviceName: String { device?.name ?? input.name }
    private var statusText: String {
        if input.deviceUID.isEmpty { return "未选择设备" }
        if device == nil { return "设备未连接" }
        if !model.desiredRunning { return "已连接" }
        if model.waitingForClient { return "待命" }
        if state?.receiving != true { return "等待收音" }
        return input.muted ? "已静音" : "正在收音"
    }
    private var statusColor: Color {
        if input.deviceUID.isEmpty { return .secondary }
        if model.waitingForClient && device != nil { return .secondary }
        if device == nil || (model.desiredRunning && state?.receiving != true) { return .orange }
        return model.desiredRunning && !input.muted ? .green : .secondary
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 8) {
                Text("输入 \(index)").font(.caption.weight(.medium)).foregroundStyle(.secondary)
                Spacer(minLength: 4)
                Label {
                    Text(statusText).foregroundStyle(.primary)
                } icon: {
                    Image(systemName: device == nil ? "mic.slash" : model.waitingForClient ? "clock" : "mic.fill")
                        .foregroundStyle(statusColor)
                }.font(.caption)
                Menu {
                    Button("移除此输入", role: .destructive) { model.removeInput(input.id) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 20, height: 18)
                }
                .menuStyle(.borderlessButton).menuIndicator(.hidden).fixedSize()
                .disabled(model.desiredRunning || model.busy)
                .accessibilityLabel("输入 \(index) 的更多操作")
                .help(model.desiredRunning ? "停止混音后可以移除此输入" : "输入操作")
            }
            Group {
                if model.desiredRunning {
                    Text(deviceName).font(.headline).lineLimit(1).truncationMode(.middle)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("输入 \(index) 设备，\(deviceName)")
                        .help("\(deviceName) · 停止混音后可以切换设备")
                } else {
                    devicePicker
                }
            }.frame(height: 26)
            LevelMeter(level: device == nil ? 0 : state?.peak ?? 0, label: "输入 \(index) 电平")
            HStack(spacing: 10) {
                Slider(value: Binding(get: { input.gain }, set: { model.setGain($0, for: input.id) }), in: 0...1.5)
                    .accessibilityLabel("输入 \(index) 音量")
                Text(input.gain, format: .percent.precision(.fractionLength(0)))
                    .font(.callout).monospacedDigit().frame(width: 42, alignment: .trailing)
                Toggle(isOn: Binding(get: { input.muted }, set: { model.setMuted($0, for: input.id) })) {
                    Label("静音", systemImage: input.muted ? "mic.slash.fill" : "mic")
                }
                .toggleStyle(.button).controlSize(.small)
                .accessibilityLabel("输入 \(index) 静音")
                .help(input.muted ? "取消静音" : "静音此输入")
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(Color.primary.opacity(0.08)) }
        .accessibilityElement(children: .contain)
    }

    private var devicePicker: some View {
        Picker("设备", selection: Binding(get: { input.deviceUID }, set: { model.selectDevice($0, for: input.id) })) {
            Text("请选择设备").tag("")
            if !input.deviceUID.isEmpty && device == nil {
                Text("\(input.name)（未连接）").tag(input.deviceUID)
            }
            ForEach(model.devices.filter { device in
                !model.settings.inputs.contains { $0.id != input.id && $0.deviceUID == device.uid }
            }) { device in Text(device.name).tag(device.uid) }
        }
        .labelsHidden().disabled(model.busy)
        .accessibilityLabel("输入 \(index) 设备").help(deviceName)
    }
}

private struct OutputBar: View {
    @ObservedObject var model: MixerModel

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 10) {
                        Text("混合输出").font(.caption).foregroundStyle(.secondary)
                        Text("Mac Mic Mixer").font(.callout.weight(.medium)).textSelection(.enabled)
                    }
                    .help("在会议或录音 App 中选择 Mac Mic Mixer 麦克风")
                    LevelMeter(level: model.status.outputPeak, label: "混合输出电平")
                }.frame(maxWidth: .infinity)
                Button {
                    if model.desiredRunning { model.stop() } else { model.start() }
                } label: {
                    Label(model.actionTitle,
                          systemImage: model.desiredRunning ? "stop.fill" : "play.fill")
                        .frame(minWidth: 94)
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .keyboardShortcut(.return, modifiers: .command)
                .disabled(model.busy || (!model.desiredRunning && !model.canStart))
            }
            HStack(spacing: 12) {
                Text("总音量").font(.callout).foregroundStyle(.secondary)
                Slider(value: Binding(get: { model.settings.masterGain }, set: model.setMasterGain), in: 0...1.5)
                    .accessibilityLabel("总音量")
                Text(model.settings.masterGain, format: .percent.precision(.fractionLength(0)))
                    .font(.callout).monospacedDigit().frame(width: 42, alignment: .trailing)
                Text(model.waitingForClient ? "待命时释放实体麦克风" : "关闭窗口后继续混音")
                    .font(.caption).foregroundStyle(.secondary).fixedSize()
            }
            if model.status.outputPeak > 0.95 {
                Label("电平接近满幅，请降低输入或总音量。", systemImage: "exclamationmark.triangle")
                    .font(.caption).foregroundStyle(.orange)
            }
        }
        .padding(.horizontal, 20).padding(.vertical, 14)
        .background(Color(nsColor: .controlBackgroundColor))
    }
}

private struct MixerSettingsPanel: View {
    @ObservedObject var model: MixerModel
    let verify: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("设置").font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                Toggle("按需采集麦克风", isOn: Binding(
                    get: { model.settings.captureOnDemand }, set: model.setCaptureOnDemand))
                    .disabled(model.busy)
                Text("其他 App 使用虚拟麦克风时采集，结束约 1 秒后释放。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Toggle(model.settings.captureOnDemand ? "打开应用时自动待命" : "打开应用时自动开始混音", isOn: Binding(
                    get: { model.settings.startOnLaunch }, set: model.setStartOnLaunch))
                Toggle("登录 Mac 时启动", isOn: Binding(get: { model.loginEnabled }, set: model.setLoginEnabled))
            }.toggleStyle(.checkbox)
            Text("停止混音后可以增删或切换输入。退出应用将停止混音。")
                .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            Divider()
            VStack(alignment: .leading, spacing: 10) {
                Text("连接诊断").font(.subheadline.weight(.semibold))
                LabeledContent("虚拟麦克风", value: model.driverInstalled ? model.driverVersion : "未就绪")
                LabeledContent("积压丢帧", value: "\(model.status.droppedFrames)")
                LabeledContent("缓冲欠载", value: "\(model.status.underrunFrames)")
                LabeledContent("累计限幅帧", value: "\(model.status.clippedFrames)")
                Text("计数持续增长或听到断音时，请停止混音并重新连接设备。")
                    .font(.caption).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
                Button("发送测试音并验证虚拟麦克风…", action: verify)
                    .disabled(model.busy || !model.driverInstalled)
            }.font(.callout).monospacedDigit()
            Divider()
            Button { model.openHelp() } label: { Label("使用说明", systemImage: "questionmark.circle") }
        }
        .padding(20).frame(width: 360)
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
