import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    static weak var model: MixerModel?
    private var terminating = false
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        if terminating { return .terminateLater }
        guard let model = Self.model else { return .terminateNow }
        terminating = true
        model.terminate { sender.reply(toApplicationShouldTerminate: true) }
        return .terminateLater
    }
    func applicationDidFinishLaunching(_ notification: Notification) {
        let id = Bundle.main.bundleIdentifier ?? "com.macmicmixer.app"
        let others = NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
        if let existing = others.first {
            existing.activate(options: .activateIgnoringOtherApps)
            NSApp.terminate(nil)
        }
    }
}

@main
struct MacMicMixerApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    @StateObject private var model = MixerModel()
    var body: some Scene {
        Window("Mac Mic Mixer", id: "mixer") {
            MixerView(model: model).onAppear { AppDelegate.model = model }
        }
        .defaultSize(width: 640, height: model.settings.inputs.count > 2 ? 560 : 420)
        .windowResizability(.contentSize)
        .commands {
            CommandGroup(replacing: .newItem) {}
            CommandGroup(replacing: .help) { Button("Mac Mic Mixer 使用说明") { model.openHelp() } }
        }
        MenuBarExtra("Mac Mic Mixer", systemImage: model.healthy ? "waveform" : "mic") {
            MenuContent(model: model)
        }
    }
}

private struct MenuContent: View {
    @Environment(\.openWindow) private var openWindow
    @ObservedObject var model: MixerModel
    var body: some View {
        Text(model.statusTitle)
        Button("打开混音窗口") { openWindow(id: "mixer"); NSApp.activate(ignoringOtherApps: true) }
        Button(model.actionTitle) {
            if model.desiredRunning { model.stop() } else { model.start() }
        }.disabled(model.busy || (!model.desiredRunning && !model.canStart))
        Divider()
        Button("退出 Mac Mic Mixer") { NSApp.terminate(nil) }.keyboardShortcut("q")
    }
}
