import AppKit

enum Hotkey: String, CaseIterable, Identifiable {
    case fn
    case rightOption
    case rightCommand

    var id: String { rawValue }

    var title: String {
        switch self {
        case .fn: "fn (Globe)"
        case .rightOption: "Right Option ⌥"
        case .rightCommand: "Right Command ⌘"
        }
    }

    /// Virtual key code and the modifier flag that is set while the key is down.
    var keyCode: UInt16 {
        switch self {
        case .fn: 63
        case .rightOption: 61
        case .rightCommand: 54
        }
    }

    var flag: NSEvent.ModifierFlags {
        switch self {
        case .fn: .function
        case .rightOption: .option
        case .rightCommand: .command
        }
    }
}

/// Watches modifier-key changes system-wide (requires Accessibility) and in our own windows.
final class HotkeyMonitor {
    private var monitors: [Any] = []
    var hotkey: Hotkey = .fn
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Void)?
    /// ⌃⌘V and ⌃⌘C.
    var onPasteLast: (() -> Void)?
    var onCopyLast: (() -> Void)?

    func start() {
        stop()
        if let global = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] in self?.handle($0) }) {
            monitors.append(global)
        }
        if let local = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged, handler: { [weak self] in self?.handle($0); return $0 }) {
            monitors.append(local)
        }
        if let globalKeys = NSEvent.addGlobalMonitorForEvents(matching: .keyDown, handler: { [weak self] in self?.handleKey($0) }) {
            monitors.append(globalKeys)
        }
        if let localKeys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] in self?.handleKey($0); return $0 }) {
            monitors.append(localKeys)
        }
    }

    func stop() {
        monitors.forEach(NSEvent.removeMonitor)
        monitors.removeAll()
    }

    private func handleKey(_ event: NSEvent) {
        let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
        switch (event.keyCode, mods) {
        case (53, _): onEscape?()
        case (9, [.control, .command]): onPasteLast?()
        case (8, [.control, .command]): onCopyLast?()
        default: break
        }
    }

    private func handle(_ event: NSEvent) {
        guard event.keyCode == hotkey.keyCode else { return }
        if event.modifierFlags.contains(hotkey.flag) {
            onPress?()
        } else {
            onRelease?()
        }
    }
}
