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
        case .missingAPIKey: "Add your OpenAI API key in Settings."
        case .api(let message): message
        }
    }
}

enum TranscriptionEngine: String, CaseIterable, Identifiable {
    case onDevice
    case openAI

    var id: String { rawValue }

    var title: String {
        switch self {
        case .onDevice: "On-device (Apple)"
        case .openAI: "OpenAI Whisper"
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

/// OpenAI's transcription endpoint (`whisper-1`).
struct OpenAITranscriber: Transcriber {
    let apiKey: String
    var model = "whisper-1"
    var session: URLSession = .shared

    func transcribe(_ audio: URL) async throws -> String {
        var body = MultipartBody()
        body.addField("model", model)
        body.addField("response_format", "json")
        body.addFile("file", filename: "speech.wav", mimeType: "audio/wav", contents: try Data(contentsOf: audio))

        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/audio/transcriptions")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(body.contentType, forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 60

        let (data, response) = try await session.upload(for: request, from: body.finalized())
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        struct Success: Decodable { let text: String }
        struct Failure: Decodable { struct Detail: Decodable { let message: String }; let error: Detail }
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(Failure.self, from: data))?.error.message ?? "OpenAI returned HTTP \(status)."
            throw FlowError.api(message)
        }
        return try JSONDecoder().decode(Success.self, from: data).text
    }
}
