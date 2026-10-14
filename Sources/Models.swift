import Foundation
import SwiftData

@Model
final class Transcript {
    var uuid = UUID()
    /// The text that was pasted (after cleanup).
    var text: String
    /// What was heard before cleanup, kept when cleanup changed it.
    var rawText: String?
    var createdAt: Date
    var duration: Double
    var engine: String
    /// Cloud preset ID when transcribed in the cloud.
    var provider: String?
    /// The app that was frontmost when dictation started.
    var appName: String?
    /// "done" or "failed". A failed dictation keeps its audio so it can be retried.
    var status: String = "done"
    var audioFileName: String?
    var errorMessage: String?
    var pasted: Bool = false

    init(text: String, rawText: String? = nil, duration: Double, engine: TranscriptionEngine, provider: String?,
         appName: String?, createdAt: Date = .now) {
        self.text = text
        self.rawText = rawText
        self.duration = duration
        self.engine = engine.rawValue
        self.provider = provider
        self.appName = appName
        self.createdAt = createdAt
    }

    var isFailed: Bool { status == "failed" }

    var engineTitle: String {
        guard let provider else { return "On this Mac" }
        return CloudPreset.preset(id: provider).title
    }

    var audioURL: URL? { audioFileName.map { Store.recordingsFolder.appendingPathComponent($0) } }

    var usage: UsageRecord { UsageRecord(date: createdAt, duration: duration, provider: provider) }
}

enum Store {
    static let folder: URL = {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("InfinityFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }()

    /// Audio kept for dictations that haven't been transcribed successfully yet.
    static let recordingsFolder: URL = {
        let recordings = Store.folder.appendingPathComponent("Recordings", isDirectory: true)
        try? FileManager.default.createDirectory(at: recordings, withIntermediateDirectories: true)
        return recordings
    }()

    /// History lives in its own file rather than the shared `default.store`.
    static let container: ModelContainer = {
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("History.store"))
        do {
            return try ModelContainer(for: Transcript.self, configurations: configuration)
        } catch {
            fatalError("Could not open the history store: \(error)")
        }
    }()

    /// Moves a fresh recording out of the temporary folder so it survives until transcribed.
    static func keepRecording(_ url: URL) -> URL {
        let destination = recordingsFolder.appendingPathComponent(url.lastPathComponent)
        do {
            try FileManager.default.moveItem(at: url, to: destination)
            return destination
        } catch {
            return url
        }
    }

    static func deleteRecording(_ url: URL?) {
        guard let url else { return }
        try? FileManager.default.removeItem(at: url)
    }

    /// Number of saved recordings and their total size in bytes.
    static func recordingsUsage() -> (count: Int, bytes: Int64) {
        let files = (try? FileManager.default.contentsOfDirectory(at: recordingsFolder, includingPropertiesForKeys: [.fileSizeKey])) ?? []
        let bytes = files.reduce(Int64(0)) { $0 + Int64((try? $1.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
        return (files.count, bytes)
    }
}

enum RecordingRetention: Int, CaseIterable, Identifiable {
    case forever = 0
    case days30 = 30
    case days7 = 7

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .forever: "Keep forever"
        case .days30: "Delete after 30 days"
        case .days7: "Delete after 7 days"
        }
    }

    /// Whether a recording made at `date` should be deleted at `now`. Failed dictations are kept for retry.
    func isExpired(_ date: Date, now: Date, calendar: Calendar = .current) -> Bool {
        guard self != .forever, let cutoff = calendar.date(byAdding: .day, value: -rawValue, to: now) else { return false }
        return date < cutoff
    }
}

enum SettingsKey {
    static let hotkey = "hotkey"
    static let engine = "engine"
    static let cloudPreset = "cloudPreset"
    static let customBaseURL = "customBaseURL"
    static let customModel = "customModel"
    static let cleanupMode = "cleanupMode"
    static let cleanupModel = "cleanupModel"
    static let playSounds = "playSounds"
    static let restoreClipboard = "restoreClipboard"
    static let onboarded = "onboarded"
    static let keepRecordings = "keepRecordings"
    static let recordingRetention = "recordingRetention"
}
