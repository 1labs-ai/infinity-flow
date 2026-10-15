import Foundation
import Speech

enum FlowError: LocalizedError {
    case noMicrophone
    case speechUnavailable
    case missingAPIKey
    case api(String)

    /// The provider doesn't have this model (anymore) for this key.
    var isMissingModel: Bool {
        guard case .api(let message) = self else { return false }
        let lowered = message.lowercased()
        return lowered.contains("does not exist") || lowered.contains("decommissioned") || lowered.contains("model_not_found")
            || lowered.contains("not found") && lowered.contains("model")
    }

    var errorDescription: String? {
        switch self {
        case .noMicrophone: "No microphone is available."
        case .speechUnavailable: "Speech recognition isn't available for this language."
        case .missingAPIKey: "Add your API key in Settings › Transcription."
        case .api(let message): message
        }
    }
}

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case onDevice
    /// Stored as "openAI" by earlier builds; now any OpenAI-compatible provider with the user's key.
    case cloud = "openAI"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: "On this Mac (free, private)"
        case .cloud: "Cloud, with your own API key"
        }
    }
}

protocol Transcriber {
    func transcribe(_ audio: URL) async throws -> String
}

/// Apple's speech recognizer, kept on device whenever the language supports it.
struct AppleSpeechTranscriber: Transcriber {
    var locale: Locale = .current

    func transcribe(_ audio: URL) async throws -> String {
        guard let recognizer = SFSpeechRecognizer(locale: locale), recognizer.isAvailable else {
            throw FlowError.speechUnavailable
        }
        let request = SFSpeechURLRecognitionRequest(url: audio)
        request.requiresOnDeviceRecognition = recognizer.supportsOnDeviceRecognition
        request.addsPunctuation = true
        request.shouldReportPartialResults = false
        return try await withCheckedThrowingContinuation { continuation in
            var finished = false
            recognizer.recognitionTask(with: request) { result, error in
                guard !finished else { return }
                if let result, result.isFinal {
                    finished = true
                    continuation.resume(returning: result.bestTranscription.formattedString)
                } else if let error {
                    finished = true
                    // "No speech detected" is an empty transcript, not a failure.
                    let code = (error as NSError).code
                    if code == 1110 || code == 203 {
                        continuation.resume(returning: "")
                    } else {
                        continuation.resume(throwing: error)
                    }
                }
            }
        }
    }
}

/// Any OpenAI-compatible transcription endpoint (`POST /audio/transcriptions`), called with the user's own key.
/// Audio goes straight to that provider; Infinity Flow has no server.
struct CloudTranscriber: Transcriber {
    let baseURL: String
    let model: String
    let apiKey: String?
    /// ISO-639-1 code such as "hi"; `nil` lets the model detect the language.
    var language: String?
    /// Text the model continues from: earlier transcript and spelling hints. Whisper reads up to 224 tokens.
    var prompt: String?
    var session: URLSession = .shared

    func transcribe(_ audio: URL) async throws -> String {
        try await request(audio, format: "json").text
    }

    /// Transcribes with a timestamp for each sentence, so a meeting's turns can be put in the order they were said.
    /// Sentences the model itself rates as probably not speech (Whisper's invented "Thank you." on noise) are dropped.
    /// Servers without timestamps get a single line.
    func transcribeTimed(_ audio: URL) async throws -> (text: String, lines: [TimedText]?) {
        let result: Response
        do {
            result = try await request(audio, format: "verbose_json")
        } catch FlowError.api(let message) where message.contains("HTTP 400") || message.lowercased().contains("response_format") {
            return (try await request(audio, format: "json").text, nil)
        }
        guard let segments = result.segments else { return (result.text, nil) }
        let lines = segments.filter { !$0.isLikelyNotSpeech }.map {
            TimedText(start: $0.start, end: $0.end, text: $0.text.trimmingCharacters(in: .whitespacesAndNewlines))
        }.filter { !$0.text.isEmpty }
        return (lines.map(\.text).joined(separator: " "), lines)
    }

    struct Response: Decodable {
        struct Segment: Decodable {
            let start: Double
            let end: Double
            let text: String
            let no_speech_prob: Double?
            let avg_logprob: Double?

            /// Whisper's own signals for a sentence made up from silence or noise.
            var isLikelyNotSpeech: Bool {
                (no_speech_prob ?? 0) > 0.6 && (avg_logprob ?? 0) < -0.8
            }
        }
        let text: String
        let segments: [Segment]?
    }

    private func request(_ audio: URL, format: String) async throws -> Response {
        guard let url = CloudPreset.endpoint(base: baseURL, path: "/audio/transcriptions") else {
            throw FlowError.api("Set a server URL in Settings › Transcription.")
        }
        var body = MultipartBody()
        body.addField("model", model)
        body.addField("response_format", format)
        if format == "verbose_json" { body.addField("timestamp_granularities[]", "segment") }
        if let language { body.addField("language", language) }
        if let prompt, !prompt.isEmpty { body.addField("prompt", prompt) }
        body.addFile("file", filename: "speech.wav", mimeType: "audio/wav", contents: try Data(contentsOf: audio))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 90

        let (data, response) = try await session.upload(for: request, from: body.finalized())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = Self.errorMessage(status: status, data: data)
            throw FlowError.api(status == 400 && !message.contains("HTTP") ? "\(message) (HTTP 400)" : message)
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    /// Checks the server and key without sending audio, using `GET /models`.
    static func testConnection(baseURL: String, apiKey: String?, session: URLSession = .shared) async -> Result<String, FlowError> {
        guard let url = CloudPreset.endpoint(base: baseURL, path: "/models") else {
            return .failure(.api("That server URL isn't valid."))
        }
        var request = URLRequest(url: url)
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 15
        do {
            let (data, response) = try await session.data(for: request)
            let status = (response as? HTTPURLResponse)?.statusCode ?? 0
            return status == 200 ? .success("Connected") : .failure(.api(errorMessage(status: status, data: data)))
        } catch {
            return .failure(.api("Couldn't reach the server: \(error.localizedDescription)"))
        }
    }

    static func errorMessage(status: Int, data: Data) -> String {
        struct Failure: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }
        if status == 401 || status == 403 { return "The API key was rejected." }
        if status == 429 { return "Rate limit reached. Try again in a moment." }
        return (try? JSONDecoder().decode(Failure.self, from: data))?.error.message ?? "The server returned HTTP \(status)."
    }
}

/// The engine, provider and chat model chosen in Settings. Dictation and meeting notes both read them from here.
enum EngineSettings {
    private static var defaults: UserDefaults { .standard }

    static var engine: TranscriptionEngine {
        TranscriptionEngine(rawValue: defaults.string(forKey: SettingsKey.engine) ?? "") ?? .onDevice
    }

    static var preset: CloudPreset {
        CloudPreset.preset(id: defaults.string(forKey: SettingsKey.cloudPreset))
    }

    /// The base URL and model for the selected cloud preset; Custom reads them from Settings.
    static var cloudEndpoint: (baseURL: String, model: String) {
        let preset = preset
        guard preset == .custom else { return (preset.baseURL, preset.model) }
        return (defaults.string(forKey: SettingsKey.customBaseURL) ?? "", defaults.string(forKey: SettingsKey.customModel) ?? "")
    }

    static var cleanupMode: CleanupMode {
        CleanupMode(rawValue: defaults.string(forKey: SettingsKey.cleanupMode) ?? "") ?? .light
    }

    struct Heard {
        /// Whitespace-normalized text, or "" when nothing was said.
        let text: String
        let engine: TranscriptionEngine
        /// Cloud preset ID, or `nil` when transcribed on this Mac.
        let provider: String?
        /// Sentences with times from the start of the audio, when the engine provides them.
        var lines: [TimedText]? = nil
    }

    /// Transcribes a dictation with the engine and language chosen in Settings. No cleanup is applied.
    static func transcribe(_ audio: URL) async throws -> Heard {
        let engine = engine
        let language = speechLanguage
        switch engine {
        case .onDevice:
            let raw = try await AppleSpeechTranscriber(locale: language.locale).transcribe(audio)
            return Heard(text: TranscriptText.clean(raw) ?? "", engine: engine, provider: nil)
        case .cloud:
            let preset = preset
            let key = APIKeyStore.read(provider: preset.id)
            if preset.requiresKey, key == nil { throw FlowError.missingAPIKey }
            let endpoint = cloudEndpoint
            let raw = try await CloudTranscriber(baseURL: endpoint.baseURL, model: transcriptionModel(for: language), apiKey: key,
                                                 language: language.whisperLanguage,
                                                 prompt: SpeechLanguage.prompt(style: language.stylePrompt, context: "")).transcribe(audio)
            return Heard(text: TranscriptText.clean(raw) ?? "", engine: engine, provider: preset.id)
        }
    }

    /// For AI polish of dictation: a large cloud model when a key is set (it understands Hinglish and
    /// self-corrections far better), otherwise Apple Intelligence on this Mac, otherwise the chat model set by hand.
    static func polishModel() -> LanguageModel? {
        if cloudReady, let model = meetingModel(timeout: 15), model is CloudChatModel { return model }
        return languageModel(timeout: 15)
    }

    /// English-only speech uses the provider's fast model; anything else uses its multilingual model, because
    /// fast distilled models tend to translate Hindi into English instead of writing down what was said.
    static func transcriptionModel(for language: SpeechLanguage) -> String {
        guard language != .english, let multilingual = preset.multilingualModel, preset != .custom else { return cloudEndpoint.model }
        return multilingual
    }

    /// Whether a cloud provider is ready to use: a key for providers that need one, a server for Custom.
    static var cloudReady: Bool {
        let preset = preset
        if preset == .custom { return CloudPreset.endpoint(base: cloudEndpoint.baseURL, path: "/") != nil && !cloudEndpoint.model.isEmpty }
        return !preset.requiresKey || APIKeyStore.read(provider: preset.id) != nil
    }

    static var meetingEngine: TranscriptionEngine {
        let chosen = TranscriptionEngine(rawValue: defaults.string(forKey: SettingsKey.meetingEngine) ?? "") ?? .cloud
        return chosen == .cloud && cloudReady ? .cloud : .onDevice
    }

    static var speechLanguage: SpeechLanguage {
        SpeechLanguage(rawValue: defaults.string(forKey: SettingsKey.speechLanguage) ?? "") ?? .forThisMac
    }

    /// Transcribes one part of a meeting. `context` is the transcript just before it, which keeps names,
    /// spelling and script (Devanagari or Roman) consistent from part to part.
    static func transcribeMeeting(_ audio: URL, context: String) async throws -> Heard {
        let language = speechLanguage
        switch meetingEngine {
        case .onDevice:
            let raw = try await AppleSpeechTranscriber(locale: language.locale).transcribe(audio)
            return Heard(text: TranscriptText.clean(raw) ?? "", engine: .onDevice, provider: nil)
        case .cloud:
            let preset = preset
            let endpoint = cloudEndpoint
            // With automatic detection, earlier parts (possibly in another language) would steer this one, so context
            // is only sent once the language is known.
            let transcriber = CloudTranscriber(baseURL: endpoint.baseURL, model: transcriptionModel(for: language), apiKey: APIKeyStore.read(provider: preset.id),
                                               language: language.whisperLanguage,
                                               prompt: SpeechLanguage.prompt(style: language.stylePrompt, context: language == .auto ? "" : context))
            let result = try await transcriber.transcribeTimed(audio)
            return Heard(text: TranscriptText.clean(result.text) ?? "", engine: .cloud, provider: preset.id, lines: result.lines)
        }
    }

    /// For meeting notes and questions: a large cloud model when a key is set (far better at long, mixed-language
    /// meetings), otherwise Apple Intelligence on this Mac.
    static func meetingModel(timeout: TimeInterval = 180) -> LanguageModel? {
        if cloudReady {
            let chosen = defaults.string(forKey: SettingsKey.cleanupModel)?.trimmingCharacters(in: .whitespaces) ?? ""
            let model = chosen.isEmpty ? preset.chatModel : chosen
            if !model.isEmpty {
                return CloudChatModel(baseURL: cloudEndpoint.baseURL, model: model, apiKey: APIKeyStore.read(provider: preset.id),
                                      timeout: timeout, fallbacks: preset.chatModels)
            }
        }
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleIntelligenceModel.isAvailable { return AppleIntelligenceModel() }
        #endif
        return nil
    }

    /// Apple Intelligence on this Mac when available; otherwise the chat model set for the cloud provider, if any.
    static func languageModel(timeout: TimeInterval = 30) -> LanguageModel? {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *), AppleIntelligenceModel.isAvailable {
            return AppleIntelligenceModel()
        }
        #endif
        let model = defaults.string(forKey: SettingsKey.cleanupModel)?.trimmingCharacters(in: .whitespaces) ?? ""
        guard !model.isEmpty else { return nil }
        return CloudChatModel(baseURL: cloudEndpoint.baseURL, model: model, apiKey: APIKeyStore.read(provider: preset.id), timeout: timeout)
    }

    static var appleIntelligenceAvailable: Bool {
        #if canImport(FoundationModels)
        if #available(macOS 26.0, *) { return AppleIntelligenceModel.isAvailable }
        #endif
        return false
    }
}
