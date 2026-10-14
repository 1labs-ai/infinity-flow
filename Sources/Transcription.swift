import Foundation
import Speech

enum FlowError: LocalizedError {
    case noMicrophone
    case speechUnavailable
    case missingAPIKey
    case api(String)

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
    var session: URLSession = .shared

    func transcribe(_ audio: URL) async throws -> String {
        guard let url = CloudPreset.endpoint(base: baseURL, path: "/audio/transcriptions") else {
            throw FlowError.api("Set a server URL in Settings › Transcription.")
        }
        var body = MultipartBody()
        body.addField("model", model)
        body.addField("response_format", "json")
        body.addFile("file", filename: "speech.wav", mimeType: "audio/wav", contents: try Data(contentsOf: audio))

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let (data, response) = try await session.upload(for: request, from: body.finalized())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        struct Success: Decodable { let text: String }
        guard status == 200 else { throw FlowError.api(Self.errorMessage(status: status, data: data)) }
        return try JSONDecoder().decode(Success.self, from: data).text
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
