import AppKit
import AVFoundation
import Combine
import ServiceManagement

@MainActor
final class MixerModel: ObservableObject {
    @Published private(set) var settings: MixerSettings
    @Published private(set) var devices: [InputDevice] = []
    @Published private(set) var status = EngineStatus.stopped
    @Published private(set) var driverInstalled = false
    @Published private(set) var driverVersion = ""
    @Published private(set) var desiredRunning = false
    @Published private(set) var busy = false
    @Published private(set) var errorMessage: String?
    @Published private(set) var notice: String?
    @Published private(set) var diagnosticMessage: String?
    @Published private(set) var diagnosticPassed = false
    @Published private(set) var loginEnabled = SMAppService.mainApp.status == .enabled
    @Published private(set) var permission = AVCaptureDevice.authorizationStatus(for: .audio)
    @Published private(set) var virtualInputInUse: Bool?
    @Published private var requestingPermission = false

    private let worker = EngineWorker()
    private var timer: Timer?
    private var observers: [NSObjectProtocol] = []
    private var polling = false
    private var didAutoStart = false
    private var sleeping = false
    private var quitting = false
    private var recoveryAttempts = 0
    private var nextRecovery = Date.distantPast
    private var controlsUpdate: DispatchWorkItem?
    private var captureDemand = CaptureDemand()
    private var commandVersion = 0

    private static var settingsURL: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("MacMicMixer", isDirectory: true).appendingPathComponent("settings.json")
    }

    init() {
        if let data = try? Data(contentsOf: Self.settingsURL),
           let saved = try? JSONDecoder().decode(MixerSettings.self, from: data) {
            settings = saved
        } else { settings = MixerSettings() }
        // Saved configuration is never trusted as proof of connected devices.
        settings.inputs = settings.inputs.filter { !$0.deviceUID.isEmpty }
        var seen = Set<String>()
        settings.inputs = settings.inputs.filter { seen.insert($0.deviceUID).inserted }
        settings.masterGain = min(max(settings.masterGain.isFinite ? settings.masterGain : 0.75, 0), 1.5)
        for index in settings.inputs.indices {
            let gain = settings.inputs[index].gain
            settings.inputs[index].gain = min(max(gain.isFinite ? gain : 0.7, 0), 1.5)
        }
        let refreshTimer = Timer(timeInterval: 0.25, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
        RunLoop.main.add(refreshTimer, forMode: .common)
        timer = refreshTimer
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in self?.suspend() }
        })
        observers.append(center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                self.sleeping = false
                self.nextRecovery = Date().addingTimeInterval(2)
                self.refresh()
            }
        })
        refresh()
    }

    var canStart: Bool {
        driverInstalled && !settings.inputs.isEmpty && settings.inputs.allSatisfy { !$0.deviceUID.isEmpty }
            && settings.inputs.contains { item in devices.contains { $0.uid == item.deviceUID } }
    }
    var statusTitle: String {
        if sleeping { return "休眠期间暂停" }
        if busy { return "正在处理音频连接…" }
        if let errorMessage, !desiredRunning { return errorMessage }
        if !driverInstalled { return "需要安装虚拟麦克风" }
        if !desiredRunning { return "混音已停止" }
        if requestingPermission { return "等待麦克风授权…" }
        if settings.captureOnDemand && virtualInputInUse == nil { return "无法检测虚拟麦克风使用状态" }
        if waitingForClient { return "待命中，等待其他 App 使用麦克风" }
        if status.starting && !healthy { return "正在等待音频输入…" }
        if !status.outputReady { return "虚拟输出正在恢复" }
        if !status.anyReceiving { return "等待输入设备收音" }
        if !status.allReceiving { return "部分输入暂时中断" }
        return "正在输出混合声音"
    }
    var healthy: Bool { desiredRunning && status.outputReady && status.allReceiving && !busy }
    var waitingForClient: Bool {
        desiredRunning && settings.captureOnDemand && virtualInputInUse == false && !status.running && !busy
    }
    var actionTitle: String {
        if desiredRunning { return waitingForClient ? "停止待命" : "停止混音" }
        return settings.captureOnDemand ? "开始待命" : "开始混音"
    }

    func refresh() {
        guard !polling, !busy, !sleeping, !quitting else { return }
        polling = true
        let version = commandVersion
        worker.refresh { [weak self] result in
            guard let self else { return }
            self.polling = false
            guard !self.quitting, !self.busy, !self.sleeping, self.commandVersion == version else { return }
            switch result {
            case let .success((list, state)):
                self.devices = list.inputs.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
                self.driverInstalled = list.driverInstalled
                self.driverVersion = list.driverVersion
                self.virtualInputInUse = list.virtualInputInUse
                self.status = state
                self.permission = AVCaptureDevice.authorizationStatus(for: .audio)
                if self.desiredRunning && (self.permission == .denied || self.permission == .restricted) {
                    self.stop()
                    self.errorMessage = "麦克风权限已关闭，请在系统设置中恢复"
                    return
                }
                if !self.didAutoStart {
                    let allowedToArm = self.permission == .authorized ||
                        (self.settings.captureOnDemand && self.permission == .notDetermined)
                    if !self.settings.startOnLaunch || self.settings.inputs.isEmpty || !allowedToArm {
                        self.didAutoStart = true
                    } else if self.canStart {
                        self.didAutoStart = true
                        self.start()
                    }
                }
                self.reconcileCapture()
                if state.outputReady { self.recoveryAttempts = 0 }
            case let .failure(error):
                self.errorMessage = error.localizedDescription
                if self.settings.captureOnDemand {
                    self.virtualInputInUse = nil
                    self.reconcileCapture()
                }
            }
        }
    }

    func start() {
        guard !busy, !quitting else { return }
        didAutoStart = true
        guard canStart else {
            errorMessage = driverInstalled ? "请添加并连接至少一个输入设备" : "请使用完整安装包安装虚拟麦克风，并重启 Mac"
            return
        }
        permission = AVCaptureDevice.authorizationStatus(for: .audio)
        guard permission == .authorized || permission == .notDetermined else {
            errorMessage = "请在系统设置中允许 Mac Mic Mixer 使用麦克风"; return
        }
        desiredRunning = true
        errorMessage = nil
        recoveryAttempts = 0
        nextRecovery = .distantPast
        captureDemand = CaptureDemand()
        reconcileCapture()
    }

    private func reconcileCapture() {
        guard desiredRunning, !busy, !sleeping, !quitting else { return }
        let shouldCapture = captureDemand.wantsCapture(
            armed: desiredRunning, onDemand: settings.captureOnDemand,
            clientInUse: virtualInputInUse, capturing: status.running,
            now: ProcessInfo.processInfo.systemUptime)
        if shouldCapture {
            if permission == .notDetermined {
                if status.running { pauseCapture() }
                requestMicrophoneAccess()
                return
            }
            if !status.starting && !status.outputReady && Date() >= nextRecovery { recover() }
        } else if status.running {
            pauseCapture()
        }
    }

    private func requestMicrophoneAccess() {
        guard !requestingPermission, !quitting else { return }
        requestingPermission = true
        AVCaptureDevice.requestAccess(for: .audio) { [weak self] granted in
            DispatchQueue.main.async {
                guard let self else { return }
                self.requestingPermission = false
                self.permission = AVCaptureDevice.authorizationStatus(for: .audio)
                guard !self.quitting else { return }
                if granted {
                    self.reconcileCapture()
                } else {
                    self.stop()
                    self.errorMessage = "需要麦克风权限才能合并输入"
                }
            }
        }
    }

    private func beginStart() {
        guard !busy, !sleeping, !quitting else { return }
        busy = true
        errorMessage = nil
        commandVersion += 1
        let version = commandVersion
        worker.start(settings) { [weak self] error in
            guard let self, !self.quitting, self.commandVersion == version else { return }
            self.busy = false
            if let error {
                self.errorMessage = error
                self.nextRecovery = Date().addingTimeInterval(min(pow(2, Double(self.recoveryAttempts)), 30))
            }
            self.refresh()
        }
    }

    private func recover() {
        guard !busy, desiredRunning, !sleeping, Date() >= nextRecovery else { return }
        guard !settings.captureOnDemand || virtualInputInUse == true else { return }
        recoveryAttempts += 1
        nextRecovery = Date().addingTimeInterval(min(pow(2, Double(recoveryAttempts)), 30))
        if driverInstalled && canStart { beginStart() }
    }

    func stop() {
        guard !quitting else { return }
        didAutoStart = true
        desiredRunning = false
        captureDemand = CaptureDemand()
        busy = true
        controlsUpdate?.cancel()
        commandVersion += 1
        let version = commandVersion
        worker.stop { [weak self] in
            guard let self, !self.quitting, self.commandVersion == version else { return }
            self.busy = false
            self.status = .stopped
            self.refresh()
        }
    }

    private func pauseCapture() {
        busy = true
        commandVersion += 1
        let version = commandVersion
        worker.stop { [weak self] in
            guard let self, !self.quitting, self.commandVersion == version else { return }
            self.busy = false
            self.status = .stopped
            self.errorMessage = nil
            self.recoveryAttempts = 0
            self.nextRecovery = .distantPast
            self.refresh()
        }
    }

    private func suspend() {
        sleeping = true
        captureDemand = CaptureDemand()
        pauseCapture()
    }

    func addInput() {
        guard !desiredRunning, !busy else { return }
        settings.inputs.append(InputSelection())
        save()
    }
    func removeInput(_ id: UUID) {
        guard !desiredRunning, !busy else { return }
        settings.inputs.removeAll { $0.id == id }
        save()
    }
    func selectDevice(_ uid: String, for id: UUID) {
        guard !desiredRunning, !busy, let index = settings.inputs.firstIndex(where: { $0.id == id }) else { return }
        guard !settings.inputs.contains(where: { $0.id != id && $0.deviceUID == uid && !uid.isEmpty }) else { return }
        settings.inputs[index].deviceUID = uid
        settings.inputs[index].name = devices.first(where: { $0.uid == uid })?.name ?? "未选择设备"
        save()
    }
    func setGain(_ gain: Double, for id: UUID) {
        guard let index = settings.inputs.firstIndex(where: { $0.id == id }) else { return }
        settings.inputs[index].gain = gain
        saveAndUpdateControls()
    }
    func setMuted(_ muted: Bool, for id: UUID) {
        guard let index = settings.inputs.firstIndex(where: { $0.id == id }) else { return }
        settings.inputs[index].muted = muted
        saveAndUpdateControls()
    }
    func setMasterGain(_ gain: Double) { settings.masterGain = gain; saveAndUpdateControls() }
    func setStartOnLaunch(_ enabled: Bool) { settings.startOnLaunch = enabled; save() }
    func setCaptureOnDemand(_ enabled: Bool) {
        guard !busy, !quitting else { return }
        settings.captureOnDemand = enabled
        captureDemand = CaptureDemand()
        save()
        if desiredRunning && enabled && virtualInputInUse != true && status.running {
            pauseCapture()
        } else {
            reconcileCapture()
        }
    }

    private func saveAndUpdateControls() {
        save()
        controlsUpdate?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.desiredRunning else { return }
            self.worker.controls(self.settings)
        }
        controlsUpdate = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.06, execute: item)
    }
    private func save() {
        do {
            let url = Self.settingsURL
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try JSONEncoder().encode(settings).write(to: url, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        } catch { errorMessage = "设置保存失败：\(error.localizedDescription)" }
    }

    func setLoginEnabled(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            loginEnabled = SMAppService.mainApp.status == .enabled
            if enabled && !loginEnabled { notice = "请在系统设置的“登录项”中允许此应用" }
        } catch { errorMessage = "无法更新登录启动：\(error.localizedDescription)" }
    }

    func verifyLoopback() {
        guard !busy, driverInstalled else { return }
        let alert = NSAlert()
        alert.messageText = "验证虚拟麦克风"
        alert.informativeText = "将暂停混音，向虚拟麦克风发送约 4 秒测试音，再读取它验证两路混合。正在使用此麦克风的其他 App 也会收到测试音。"
        alert.addButton(withTitle: "发送测试音并验证")
        alert.addButton(withTitle: "取消")
        guard alert.runModal() == .alertFirstButtonReturn else { return }
        guard AVCaptureDevice.authorizationStatus(for: .audio) == .authorized else {
            errorMessage = "请先开始一次混音以获得麦克风权限"; return
        }
        let resume = desiredRunning
        desiredRunning = false
        busy = true
        commandVersion += 1
        let version = commandVersion
        notice = "正在发送并回读测试音…"
        diagnosticMessage = nil
        worker.verify { [weak self] result in
            guard let self, !self.quitting, self.commandVersion == version else { return }
            self.busy = false
            self.status = .stopped
            self.notice = nil
            switch result {
            case let .success(value):
                self.diagnosticPassed = value.ok
                self.diagnosticMessage = value.ok ? "验证通过：虚拟麦克风同时读到了两路测试音，左右声道一致。" : "验证失败：\(value.error)"
            case let .failure(error):
                self.diagnosticPassed = false
                self.diagnosticMessage = "验证失败：\(error.localizedDescription)"
            }
            if resume { self.start() } else { self.refresh() }
        }
    }

    func openMicrophoneSettings() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Microphone") { NSWorkspace.shared.open(url) }
    }
    func openHelp() {
        if let url = Bundle.main.url(forResource: "使用说明", withExtension: "html") { NSWorkspace.shared.open(url) }
    }
    func terminate(_ done: @escaping @MainActor () -> Void) {
        quitting = true
        commandVersion += 1
        desiredRunning = false
        timer?.invalidate()
        controlsUpdate?.cancel()
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers { center.removeObserver(observer) }
        observers.removeAll()
        worker.shutdown(done)
    }
}
