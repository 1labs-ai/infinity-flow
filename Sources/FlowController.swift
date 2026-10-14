import AppKit
import Observation
import SwiftData

/// Runs the dictation loop: hotkey down → record → hotkey up → transcribe → clean up → paste → history.
///
/// Nothing is lost: the recording is kept until the text is transcribed, a failed dictation is saved with its
/// audio for a retry, and a paste no app accepted leaves the text on the clipboard.
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
            SettingsKey.cloudPreset: CloudPreset.groq.id,
            SettingsKey.cleanupMode: CleanupMode.light.rawValue,
            SettingsKey.playSounds: true,
            SettingsKey.restoreClipboard: true,
            SettingsKey.keepRecordings: true,
            SettingsKey.recordingRetention: RecordingRetention.forever.rawValue,
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
        applyRecordingRetention()
    }

    /// Deletes recordings past the chosen retention period. Failed dictations keep theirs for retry.
    func applyRecordingRetention(now: Date = .now) {
        let retention = RecordingRetention(rawValue: defaults.integer(forKey: SettingsKey.recordingRetention)) ?? .forever
        let all = (try? container.mainContext.fetch(FetchDescriptor<Transcript>())) ?? []
        for transcript in all where transcript.audioFileName != nil && !transcript.isFailed && retention.isExpired(transcript.createdAt, now: now) {
            Store.deleteRecording(transcript.audioURL)
            transcript.audioFileName = nil
        }
        try? container.mainContext.save()
    }

    func deleteAudio(_ transcript: Transcript) {
        Store.deleteRecording(transcript.audioURL)
        transcript.audioFileName = nil
        try? container.mainContext.save()
    }

    /// Removes every saved recording except those of failed dictations, which are needed for retry.
    func deleteAllRecordings() {
        let all = (try? container.mainContext.fetch(FetchDescriptor<Transcript>())) ?? []
        let keep = Set(all.filter(\.isFailed).compactMap(\.audioFileName))
        let files = (try? FileManager.default.contentsOfDirectory(at: Store.recordingsFolder, includingPropertiesForKeys: nil)) ?? []
        for file in files where !keep.contains(file.lastPathComponent) { Store.deleteRecording(file) }
        for transcript in all where !transcript.isFailed { transcript.audioFileName = nil }
        try? container.mainContext.save()
    }

    /// Re-reads the hotkey after Settings change it.
    func applySettings() {
        hotkeyMonitor.hotkey = Hotkey(rawValue: defaults.string(forKey: SettingsKey.hotkey) ?? "") ?? .fn
        hotkeyMonitor.start()
    }

    func pasteLastTranscript() {
        guard let lastTranscript else { return }
        Task { await deliver(lastTranscript) }
    }

    func copyLastTranscript() {
        guard let lastTranscript else { return }
        TextInserter.write(lastTranscript)
    }

    /// Transcribes a failed dictation again from its saved audio. The result goes to the clipboard,
    /// since the app it was meant for is no longer in front.
    func retry(_ transcript: Transcript) async {
        guard let audio = transcript.audioURL, FileManager.default.fileExists(atPath: audio.path) else {
            transcript.errorMessage = "The audio for this dictation is no longer available."
            return
        }
        do {
            let result = try await transcribe(audio)
            transcript.text = result.text
            transcript.rawText = result.raw == result.text ? nil : result.raw
            transcript.engine = result.engine.rawValue
            transcript.provider = result.provider
            transcript.status = "done"
            transcript.errorMessage = nil
            if !defaults.bool(forKey: SettingsKey.keepRecordings) {
                Store.deleteRecording(audio)
                transcript.audioFileName = nil
            }
            lastTranscript = result.text
            TextInserter.write(result.text)
        } catch {
            transcript.errorMessage = error.localizedDescription
        }
        try? container.mainContext.save()
    }

    func delete(_ transcript: Transcript) {
        Store.deleteRecording(transcript.audioURL)
        container.mainContext.delete(transcript)
        try? container.mainContext.save()
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
        if let recording = recorder.stop() { Store.deleteRecording(recording.url) }
        state = .idle
        pill?.hide()
    }

    /// Keeps capturing briefly after release so the last word isn't clipped.
    static let trailingCapture: Duration = .milliseconds(300)

    private func finishRecording() {
        guard state == .listening else { return }
        endSession()
        state = .transcribing
        play("Pop")
        let app = sourceApp
        Task {
            try? await Task.sleep(for: Self.trailingCapture)
            guard let recording = recorder.stop() else {
                state = .idle
                pill?.hide()
                return
            }
            let audio = Store.keepRecording(recording.url)
            do {
                let result = try await transcribe(audio)
                guard !result.text.isEmpty else {
                    Store.deleteRecording(audio)
                    show(error: "We couldn't hear you. Is your microphone muted?")
                    return
                }
                let transcript = Transcript(text: result.text, rawText: result.raw == result.text ? nil : result.raw,
                                            duration: recording.duration, engine: result.engine, provider: result.provider, appName: app)
                if defaults.bool(forKey: SettingsKey.keepRecordings) {
                    transcript.audioFileName = audio.lastPathComponent
                } else {
                    Store.deleteRecording(audio)
                }
                container.mainContext.insert(transcript)
                lastTranscript = result.text
                transcript.pasted = await deliver(result.text)
                try? container.mainContext.save()
            } catch {
                let engine = currentEngine
                let failed = Transcript(text: "", duration: recording.duration, engine: engine,
                                        provider: engine == .cloud ? currentPreset.id : nil, appName: app)
                failed.status = "failed"
                failed.audioFileName = audio.lastPathComponent
                failed.errorMessage = error.localizedDescription
                container.mainContext.insert(failed)
                try? container.mainContext.save()
                show(error: "\(error.localizedDescription) Saved to History to retry.")
            }
        }
    }

    /// Pastes into the focused app; if no app accepts it, leaves it on the clipboard and says so.
    @discardableResult
    private func deliver(_ text: String) async -> Bool {
        let outcome = await TextInserter.insert(text, restoreClipboard: defaults.bool(forKey: SettingsKey.restoreClipboard))
        switch outcome {
        case .pasted:
            play("Morse")
            state = .idle
            pill?.hide()
            return true
        case .notAccepted:
            show(error: "Click a textbox and press ⌘V to paste.")
        case .noPermission:
            show(error: "Copied. Allow Accessibility to paste automatically.")
        }
        return false
    }

    // MARK: - Transcription and cleanup

    private struct TranscriptionResult {
        let text: String
        let raw: String
        let engine: TranscriptionEngine
        let provider: String?
    }

    private var currentEngine: TranscriptionEngine {
        TranscriptionEngine(rawValue: defaults.string(forKey: SettingsKey.engine) ?? "") ?? .onDevice
    }

    private var currentPreset: CloudPreset {
        CloudPreset.preset(id: defaults.string(forKey: SettingsKey.cloudPreset))
    }

    /// The base URL and model for the selected cloud preset; Custom reads them from Settings.
    private var cloudEndpoint: (baseURL: String, model: String) {
        let preset = currentPreset
        guard preset == .custom else { return (preset.baseURL, preset.model) }
        return (defaults.string(forKey: SettingsKey.customBaseURL) ?? "", defaults.string(forKey: SettingsKey.customModel) ?? "")
    }

    private func transcribe(_ audio: URL) async throws -> TranscriptionResult {
        let engine = currentEngine
        let raw: String
        var provider: String?
        switch engine {
        case .onDevice:
            raw = try await AppleSpeechTranscriber().transcribe(audio)
        case .cloud:
            let preset = currentPreset
            let key = APIKeyStore.read(provider: preset.id)
            if preset.requiresKey, key == nil { throw FlowError.missingAPIKey }
            let endpoint = cloudEndpoint
            raw = try await CloudTranscriber(baseURL: endpoint.baseURL, model: endpoint.model, apiKey: key).transcribe(audio)
            provider = preset.id
        }
        let heard = TranscriptText.clean(raw) ?? ""
        return TranscriptionResult(text: await cleanUp(heard), raw: heard, engine: engine, provider: provider)
    }

    private func cleanUp(_ text: String) async -> String {
        guard !text.isEmpty else { return text }
        let mode = CleanupMode(rawValue: defaults.string(forKey: SettingsKey.cleanupMode) ?? "") ?? .light
        guard mode != .off else { return text }
        let light = LightCleanup.clean(text)
        guard mode == .ai, let cleaner = aiCleaner(),
              let polished = try? await cleaner.clean(light),
              CleanupGuard.isSafe(original: text, cleaned: polished)
        else { return light }
        return polished.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Apple Intelligence on this Mac when available; otherwise the chat model set for the cloud provider.
    private func aiCleaner() -> TextCleaner? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleIntelligenceCleaner.isAvailable {
            return AppleIntelligenceCleaner()
        }
        #endif
        let model = defaults.string(forKey: SettingsKey.cleanupModel)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !model.isEmpty else { return nil }
        let preset = currentPreset
        return CloudChatCleaner(baseURL: cloudEndpoint.baseURL, model: model, apiKey: APIKeyStore.read(provider: preset.id))
    }

    static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return AppleIntelligenceCleaner.isAvailable }
        #endif
        return false
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
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [weak self] in
            guard let self, case .error = self.state else { return }
            self.state = .idle
            self.pill?.hide()
        }
    }

    private func play(_ name: String) {
        guard defaults.bool(forKey: SettingsKey.playSounds) else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }

    /// Event taps only work once Accessibility is granted, so reinstall them when it is.
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
