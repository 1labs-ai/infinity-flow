import Foundation

/// A cloud speech-to-text provider reached through the OpenAI-compatible
/// `POST {baseURL}/audio/transcriptions` API, using the user's own key.
struct CloudPreset: Identifiable, Hashable {
    let id: String
    let title: String
    let baseURL: String
    let model: String
    /// Published list price, used only for the cost estimate. `nil` when unknown.
    let ratePerMinute: Double?
    /// Some providers bill each request for at least this many seconds.
    let minimumBilledSeconds: Double
    let keyPage: URL?
    let requiresKey: Bool
    let note: String
    /// Capable chat models on the same provider, best first, used for meeting notes and AI polish when no chat
    /// model is set. Providers retire models, so the first one that exists for the key is used.
    var chatModels: [String] = []
    /// A transcription model that transcribes Hindi and other languages as spoken instead of translating them.
    var multilingualModel: String?

    var chatModel: String { chatModels.first ?? "" }

    static let groq = CloudPreset(
        id: "groq", title: "Groq", baseURL: "https://api.groq.com/openai/v1", model: "whisper-large-v3-turbo",
        ratePerMinute: 0.04 / 60, minimumBilledSeconds: 10, keyPage: URL(string: "https://console.groq.com/keys"),
        requiresKey: true, note: "Fastest. The free tier covers most people; after that about $0.04 per hour of audio.",
        chatModels: ["openai/gpt-oss-120b", "llama-3.3-70b-versatile", "meta-llama/llama-4-maverick-17b-128e-instruct",
                     "qwen/qwen3-32b", "llama-3.1-8b-instant"],
        multilingualModel: "whisper-large-v3")

    static let openAI = CloudPreset(
        id: "openai", title: "OpenAI", baseURL: "https://api.openai.com/v1", model: "gpt-4o-mini-transcribe",
        ratePerMinute: 0.003, minimumBilledSeconds: 0, keyPage: URL(string: "https://platform.openai.com/api-keys"),
        requiresKey: true, note: "About $0.003 per minute of audio.",
        chatModels: ["gpt-4.1-mini", "gpt-4o-mini"])

    static let custom = CloudPreset(
        id: "custom", title: "Custom (OpenAI-compatible)", baseURL: "", model: "",
        ratePerMinute: nil, minimumBilledSeconds: 0, keyPage: nil,
        requiresKey: false, note: "Any OpenAI-compatible server, including local ones such as LM Studio.")

    static let all = [groq, openAI, custom]

    static func preset(id: String?) -> CloudPreset {
        all.first { $0.id == id } ?? groq
    }

    /// Joins a base URL and an API path, tolerating a trailing slash on the base.
    static func endpoint(base: String, path: String) -> URL? {
        var trimmed = base.trimmingCharacters(in: .whitespacesAndNewlines)
        while trimmed.hasSuffix("/") { trimmed.removeLast() }
        guard !trimmed.isEmpty, let url = URL(string: trimmed + path), url.scheme == "https" || url.scheme == "http" else { return nil }
        return url
    }
}

/// One dictation, meeting or meeting chunk, reduced to what the usage and privacy summaries need.
struct UsageRecord {
    let date: Date
    let duration: TimeInterval
    /// `nil` when transcribed on this Mac; otherwise the cloud preset ID.
    let provider: String?
}

enum Usage {
    static func thisMonth(_ records: [UsageRecord], now: Date, calendar: Calendar = .current) -> [UsageRecord] {
        guard let start = calendar.dateInterval(of: .month, for: now)?.start else { return records }
        return records.filter { $0.date >= start && $0.date <= now }
    }

    /// Estimated cost of the records sent to `preset`, or `nil` when the preset has no known price.
    static func estimatedCost(_ records: [UsageRecord], preset: CloudPreset) -> Double? {
        guard let rate = preset.ratePerMinute else { return nil }
        let billedSeconds = records
            .filter { $0.provider == preset.id }
            .reduce(0) { $0 + max($1.duration, preset.minimumBilledSeconds) }
        return billedSeconds / 60 * rate
    }

    static func formatCost(_ dollars: Double) -> String {
        dollars < 0.01 ? "under $0.01" : String(format: "$%.2f", dollars)
    }
}

/// "What left this Mac" for a period.
struct PrivacySummary: Equatable {
    var onDeviceCount = 0
    var onDeviceMinutes: Double = 0
    var cloudCount = 0
    var cloudMinutes: Double = 0
    var cloudProviders: Set<String> = []

    init(_ records: [UsageRecord]) {
        for record in records {
            if let provider = record.provider {
                cloudCount += 1
                cloudMinutes += record.duration / 60
                cloudProviders.insert(provider)
            } else {
                onDeviceCount += 1
                onDeviceMinutes += record.duration / 60
            }
        }
    }

    var headline: String {
        if cloudCount == 0 {
            return "No audio left this Mac."
        }
        let names = cloudProviders.sorted().map { CloudPreset.preset(id: $0).title }.joined(separator: ", ")
        return "\(cloudCount) of \(cloudCount + onDeviceCount) recordings were sent to \(names) with your key."
    }
}
