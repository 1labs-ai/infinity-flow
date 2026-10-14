import AppKit

/// Types text into the focused app by pasting it, then restores the user's clipboard.
enum TextInserter {
    /// Returns false when Accessibility isn't granted; the text is then left on the clipboard.
    @MainActor
    @discardableResult
    static func insert(_ text: String, restoreClipboard: Bool = true) -> Bool {
        let pasteboard = NSPasteboard.general
        let saved = restoreClipboard ? snapshot(pasteboard) : []
        pasteboard.clearContents()
        // Concealed/transient markers ask clipboard managers not to record dictated text.
        let item = NSPasteboardItem()
        item.setString(text, forType: .string)
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.ConcealedType"))
        item.setString("", forType: NSPasteboard.PasteboardType("org.nspasteboard.TransientType"))
        pasteboard.writeObjects([item])
        let ourChange = pasteboard.changeCount

        guard Permissions.accessibilityGranted else { return false }
        postCommandV()

        if restoreClipboard {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Leave the clipboard alone if something else wrote to it meanwhile.
                guard pasteboard.changeCount == ourChange else { return }
                pasteboard.clearContents()
                if !saved.isEmpty { pasteboard.writeObjects(saved) }
            }
        }
        return true
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
