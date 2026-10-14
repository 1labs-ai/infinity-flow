import AppKit
import Observation
import SwiftData

/// Runs the dictation loop: hotkey down → record → hotkey up → transcribe → paste → save to history.
@MainActor
@Observable
final class FlowController {
    enum State: Equatable {
        case idle, listening, transcribing
        case error(String)
    }

    private(set) var state: State = .idle
    private(set) var levels = [Float](repeating: 0, count: 10)
    /// Hands-free: locked by a double tap; the next press finishes.
    private(set) var isLocked = false
    private(set) var lastTranscript: String?
    private(set) var accessibilityGranted = Permissions.accessibilityGranted
    let container: ModelContainer

    @ObservationIgnored private let recorder = AudioRecorder()
    @ObservationIgnored private let hotkeyMonitor = HotkeyMonitor()
    @ObservationIgnored private var hold = HoldToTalk()
    @ObservationIgnored private var pill: FlowPillController?
    @ObservationIgnored private var sourceApp: String?
    @ObservationIgnored private var permissionTimer: Timer?
    @ObservationIgnored private var sessionLimit: DispatchWorkItem?

    /// Observed in Wispr Flow: sessions end at 20 minutes.
    static let maximumSession: TimeInterval = 20 * 60

    private var defaults: UserDefaults { .standard }

    init(container: ModelContainer = Store.container) {
        self.container = container
        defaults.register(defaults: [
            SettingsKey.hotkey: Hotkey.fn.rawValue,
            SettingsKey.engine: TranscriptionEngine.onDevice.rawValue,
            SettingsKey.playSounds: true,
            SettingsKey.restoreClipboard: true,
        ])
        recorder.onLevel = { [weak self] level in
            Task { @MainActor in self?.push(level) }
        }
        hotkeyMonitor.onPress = { [weak self] in self?.press() }
        hotkeyMonitor.onRelease = { [weak self] in self?.release() }
        hotkeyMonitor.onEscape = { [weak self] in self?.escape() }
        hotkeyMonitor.onPasteLast = { [weak self] in self?.pasteLastTranscript() }
        hotkeyMonitor.onCopyLast = { [weak self] in self?.copyLastTranscript() }
        pill = FlowPillController(controller: self)
        applySettings()
        watchAccessibility()
    }

    /// Re-reads the hotkey after Settings change it.
    func applySettings() {
        hotkeyMonitor.hotkey = Hotkey(rawValue: defaults.string(forKey: SettingsKey.hotkey) ?? "") ?? .fn
        hotkeyMonitor.start()
    }

    func pasteLastTranscript() {
        guard let lastTranscript else { return }
        TextInserter.insert(lastTranscript, restoreClipboard: defaults.bool(forKey: SettingsKey.restoreClipboard))
    }

    func copyLastTranscript() {
        guard let lastTranscript else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lastTranscript, forType: .string)
    }

    // MARK: - Hotkey

    private func press() {
        if state == .transcribing {
            show(error: "Still transcribing your last dictation.")
            return
        }
        perform(hold.keyDown(at: .now))
    }

    private func release() {
        let action = hold.keyUp(at: .now)
        perform(action)
        guard action == .none, hold.isActive, !hold.isLocked else { return }
        // Short press: keep listening briefly for a second press that locks hands-free.
        DispatchQueue.main.asyncAfter(deadline: .now() + hold.debounce + 0.02) { [weak self] in
            guard let self else { return }
            self.perform(self.hold.timeout(at: .now))
        }
    }

    private func escape() {
        guard hold.isActive || state == .listening else { return }
        hold.reset()
        cancelRecording()
    }

    private func perform(_ action: HoldToTalk.Action) {
        switch action {
        case .start: startRecording()
        case .lock:
            isLocked = true
            play("Bottle")
        case .stop: finishRecording()
        case .cancel: cancelRecording()
        case .none: break
        }
    }

    // MARK: - Recording

    private func startRecording() {
        guard Permissions.microphoneGranted else {
            hold.reset()
            show(error: "Infinity Flow needs microphone access to work.")
            return
        }
        sourceApp = NSWorkspace.shared.frontmostApplication?.localizedName
        do {
            try recorder.start()
        } catch {
            hold.reset()
            show(error: error.localizedDescription)
            return
        }
        levels = levels.map { _ in 0 }
        isLocked = false
        state = .listening
        let limit = DispatchWorkItem { [weak self] in
            self?.hold.reset()
            self?.finishRecording()
        }
        sessionLimit = limit
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.maximumSession, execute: limit)
        pill?.show()
        play("Tink")
    }

    private func cancelRecording() {
        endSession()
        if let recording = recorder.stop() { try? FileManager.default.removeItem(at: recording.url) }
        state = .idle
        pill?.hide()
    }

    private func finishRecording() {
        guard state == .listening, let recording = recorder.stop() else { return }
        endSession()
        state = .transcribing
        play("Pop")
        let engine = TranscriptionEngine(rawValue: defaults.string(forKey: SettingsKey.engine) ?? "") ?? .onDevice
        let app = sourceApp
        Task {
            defer { try? FileManager.default.removeItem(at: recording.url) }
            do {
                let raw = try await transcriber(for: engine).transcribe(recording.url)
                guard let text = TranscriptText.clean(raw) else {
                    show(error: "We couldn't hear you. Is your microphone muted?")
                    return
                }
                lastTranscript = text
                let pasted = TextInserter.insert(text, restoreClipboard: defaults.bool(forKey: SettingsKey.restoreClipboard))
                container.mainContext.insert(Transcript(text: text, duration: recording.duration, engine: engine, appName: app))
                try? container.mainContext.save()
                if pasted {
                    state = .idle
                    pill?.hide()
                } else {
                    show(error: "Click a textbox and use ⌃⌘V to paste.")
                }
            } catch {
                show(error: error.localizedDescription)
            }
        }
    }

    private func transcriber(for engine: TranscriptionEngine) throws -> Transcriber {
        switch engine {
        case .onDevice:
            return AppleSpeechTranscriber()
        case .openAI:
            guard let key = APIKeyStore.read() else { throw FlowError.missingAPIKey }
            return OpenAITranscriber(apiKey: key)
        }
    }

    // MARK: - Helpers

    private func endSession() {
        sessionLimit?.cancel()
        sessionLimit = nil
        isLocked = false
    }

    private func push(_ level: Float) {
        guard state == .listening else { return }
        levels.removeFirst()
        levels.append(level)
    }

    private func show(error message: String) {
        state = .error(message)
        pill?.show()
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) { [weak self] in
            guard let self, case .error = self.state else { return }
            self.state = .idle
            self.pill?.hide()
        }
    }

    private func play(_ name: String) {
        guard defaults.bool(forKey: SettingsKey.playSounds) else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// Global key monitors only receive events once Accessibility is granted, so reinstall them when it is.
    private func watchAccessibility() {
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self else { return }
                let granted = Permissions.accessibilityGranted
                if granted, !self.accessibilityGranted { self.hotkeyMonitor.start() }
                self.accessibilityGranted = granted
            }
        }
    }
}
