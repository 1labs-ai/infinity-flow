import AppKit

enum PasteOutcome: Equatable {
    /// An app read the text from the clipboard after ⌘V.
    case pasted
    /// No app took the text (no focused text box); it stays on the clipboard for a manual ⌘V.
    case notAccepted
    /// Accessibility isn't granted, so ⌘V couldn't be sent; the text is on the clipboard.
    case noPermission
}

/// Types text into the focused app by pasting it, then restores the user's clipboard.
///
/// The text is offered as *promised* clipboard data, so we learn whether an app actually read it after ⌘V.
/// If nobody does within `acceptTimeout`, the paste failed and the text is left on the clipboard instead of lost.
@MainActor
enum TextInserter {
    static let acceptTimeout: TimeInterval = 1.0
    static let restoreDelay: TimeInterval = 0.5

    private static let concealed = NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType")
    private static let transient = NSPasteboard.PasteboardType("org.nspasteboard.TransientType")
    /// Keeps the promise alive until the clipboard changes.
    private static var activePromise: PromisedText?

    static func insert(_ text: String, restoreClipboard: Bool = true) async -> PasteOutcome {
        let pasteboard = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(pasteboard) : []

        guard Permissions.accessibilityGranted else {
            write(text, to: pasteboard)
            return .noPermission
        }

        let promise = PromisedText(text)
        activePromise = promise
        let item = NSPasteboardItem()
        item.setDataProvider(promise, forTypes: [.string])
        // Concealed/transient markers ask clipboard managers not to record dictated text.
        item.setString("", forType: concealed)
        item.setString("", forType: transient)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
        let ourChange = pasteboard.changeCount

        postCommandV()
        let accepted = await promise.waitForRequest(timeout: acceptTimeout)

        guard accepted else {
            if pasteboard.changeCount == ourChange { write(text, to: pasteboard) }
            activePromise = nil
            return .notAccepted
        }
        if restoreClipboard {
            try? await Task.sleep(for: .seconds(restoreDelay))
            // Leave the clipboard alone if something else wrote to it meanwhile.
            if pasteboard.changeCount == ourChange {
                pasteboard.clearContents()
                if !saved.isEmpty { pasteboard.writeObjects(saved) }
            }
        }
        activePromise = nil
        return .pasted
    }

    /// Puts plain text on the clipboard (marked concealed) for a manual paste.
    static func write(_ text: String, to pasteboard: NSPasteboard = .general) {
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: concealed)
        pasteboard.clearContents()
        pasteboard.writeObjects([item])
    }

    private static func snapshot(_ pasteboard: NSPasteboard) -> [NSPasteboardItem] {
        (pasteboard.pasteboardItems ?? []).map { item in
            let copy = NSPasteboardItem()
            for type in item.types {
                if let data = item.data(forType: type) { copy.setData(data, forType: type) }
            }
            return copy
        }
    }

    private static func postCommandV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        let vKey: CGKeyCode = 9
        for keyDown in [true, false] {
            let event = CGEvent(keyboardEventSource: source, virtualKey: vKey, keyDown: keyDown)
            event?.flags = .maskCommand
            event?.post(tap: .cghidEventTap)
        }
    }
}

/// Clipboard text supplied on demand, recording whether any app asked for it.
private final class PromisedText: NSObject, NSPasteboardItemDataProvider {
    private let text: String
    private var requested = false
    private var continuation: CheckedContinuation<Bool, Never>?

    init(_ text: String) {
        self.text = text
    }

    func pasteboard(_ pasteboard: NSPasteboard?, item: NSPasteboardItem, provideDataForType type: NSPasteboard.PasteboardType) {
        item.setString(text, forType: type)
        requested = true
        continuation?.resume(returning: true)
        continuation = nil
    }

    @MainActor
    func waitForRequest(timeout: TimeInterval) async -> Bool {
        if requested { return true }
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
            DispatchQueue.main.asyncAfter(deadline: .now() + timeout) { [weak self] in
                guard let self, let pending = self.continuation else { return }
                self.continuation = nil
                pending.resume(returning: self.requested)
            }
        }
    }
}
