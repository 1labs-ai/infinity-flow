import SwiftData
import SwiftUI

@main
struct InfinityFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = FlowController()
    @State private var meetings = MeetingController()

    var body: some Scene {
        Window("Infinity Flow", id: "hub") {
            HubView()
                .environment(controller)
                .environment(meetings)
                .frame(minWidth: 760, minHeight: 500)
        }
        .modelContainer(controller.container)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent().environment(controller).environment(meetings)
        } label: {
            Image(systemName: meetings.isRecording ? "record.circle" : controller.state == .listening ? "waveform.circle.fill" : "waveform")
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        UserDefaults.standard.register(defaults: [SettingsKey.showInDock: true])
        DockIcon.apply()
    }
}

/// Shows the app in the Dock (default), or only in the menu bar.
enum DockIcon {
    static func apply() {
        let show = UserDefaults.standard.bool(forKey: SettingsKey.showInDock)
        NSApp.setActivationPolicy(show ? .regular : .accessory)
        if show { NSApp.activate() }
    }
}

struct MenuBarContent: View {
    @Environment(FlowController.self) private var controller
    @Environment(MeetingController.self) private var meetings
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.hotkey) private var hotkey = Hotkey.fn.rawValue

    var body: some View {
        Text(statusText)
        Divider()
        Button("Open Infinity Flow") {
            openWindow(id: "hub")
            NSApp.activate()
        }
        if meetings.isRecording {
            Button("Stop meeting notes") { meetings.stop() }
            Button(meetings.phase == .paused ? "Resume meeting notes" : "Pause meeting notes") {
                meetings.phase == .paused ? meetings.resume() : meetings.pause()
            }
        } else {
            Button("Start meeting notes") { meetings.start() }
                .disabled(meetings.phase != .idle)
        }
        Divider()
        Button("Paste last transcript") { controller.pasteLastTranscript() }
            .disabled(controller.lastTranscript == nil)
        if let last = controller.lastTranscript {
            Text(last.count > 25 ? last.prefix(25) + "..." : last)
        }
        Divider()
        Button("Quit Infinity Flow") { NSApp.terminate(nil) }
            .keyboardShortcut("q")
    }

    private var statusText: String {
        if meetings.isRecording { return meetings.phase == .paused ? "Meeting notes paused" : "Taking meeting notes…" }
        switch controller.state {
        case .listening: return "Listening…"
        case .transcribing: return "Transcribing…"
        default: return "Hold \((Hotkey(rawValue: hotkey) ?? .fn).title) to dictate"
        }
    }
}
