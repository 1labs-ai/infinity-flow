import SwiftData
import SwiftUI

@main
struct InfinityFlowApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var controller = FlowController()

    var body: some Scene {
        Window("Infinity Flow", id: "hub") {
            HubView()
                .environment(controller)
                .frame(minWidth: 760, minHeight: 500)
        }
        .modelContainer(controller.container)
        .windowResizability(.contentMinSize)

        MenuBarExtra {
            MenuBarContent().environment(controller)
        } label: {
            Image(systemName: controller.state == .listening ? "waveform.circle.fill" : "waveform")
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
    @Environment(\.openWindow) private var openWindow
    @AppStorage(SettingsKey.hotkey) private var hotkey = Hotkey.fn.rawValue

    var body: some View {
        Text(statusText)
        Divider()
        Button("Open Infinity Flow") {
            openWindow(id: "hub")
            NSApp.activate()
        }
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
        switch controller.state {
        case .listening: "Listening…"
        case .transcribing: "Transcribing…"
        default: "Hold \((Hotkey(rawValue: hotkey) ?? .fn).title) to dictate"
        }
    }
}
