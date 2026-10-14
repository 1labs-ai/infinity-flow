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

    var flag: CGEventFlags {
        switch self {
        case .fn: .maskSecondaryFn
        case .rightOption: .maskAlternate
        case .rightCommand: .maskCommand
        }
    }
}

/// Watches the hold-to-talk key with a listen-only event tap at the HID level, and Esc/⌃⌘V/⌃⌘C with
/// key-down monitors. Both need Accessibility.
///
/// The tap is required for fn: with the Globe key bound to a system action, the flagsChanged events
/// that NSEvent monitors receive carry the same flags on press and release, so they can't tell them apart.
final class HotkeyMonitor {
    private var monitors: [Any] = []
    private var tap: CFMachPort?
    private var tapSource: CFRunLoopSource?
    var hotkey: Hotkey = .fn
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var onEscape: (() -> Void)?
    /// ⌃⌘V and ⌃⌘C.
    var onPasteLast: (() -> Void)?
    var onCopyLast: (() -> Void)?

    func start() {
        stop()
        startTap()
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
        if let tap { CGEvent.tapEnable(tap: tap, enable: false) }
        if let tapSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), tapSource, .commonModes) }
        tap = nil
        tapSource = nil
    }

    private func startTap() {
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon).takeUnretainedValue()
            switch type {
            case .tapDisabledByTimeout, .tapDisabledByUserInput:
                if let tap = monitor.tap { CGEvent.tapEnable(tap: tap, enable: true) }
            case .flagsChanged:
                monitor.handle(keyCode: UInt16(event.getIntegerValueField(.keyboardEventKeycode)), flags: event.flags)
            default:
                break
            }
            return Unmanaged.passUnretained(event)
        }
        guard let tap = CGEvent.tapCreate(
            tap: .cghidEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: CGEventMask(1 << CGEventType.flagsChanged.rawValue),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque())
        else { return }
        let source = CFMachPortCreateRunLoopSource(nil, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        self.tap = tap
        tapSource = source
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

    private func handle(keyCode: UInt16, flags: CGEventFlags) {
        guard keyCode == hotkey.keyCode else { return }
        if flags.contains(hotkey.flag) {
            onPress?()
        } else {
            onRelease?()
        }
    }
}
