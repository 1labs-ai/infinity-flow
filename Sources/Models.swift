import Foundation
import SwiftData

@Model
final class Transcript {
    var uuid = UUID()
    var text: String
    var createdAt: Date
    var duration: Double
    var engine: String
    /// The app that was frontmost when dictation started.
    var appName: String?

    init(text: String, duration: Double, engine: TranscriptionEngine, appName: String?, createdAt: Date = .now) {
        self.text = text
        self.duration = duration
        self.engine = engine.rawValue
        self.appName = appName
        self.createdAt = createdAt
    }

    var engineTitle: String { TranscriptionEngine(rawValue: engine)?.title ?? engine }
}

enum Store {
    /// History lives in its own file rather than the shared `default.store`.
    static let container: ModelContainer = {
        let folder = URL.applicationSupportDirectory.appendingPathComponent("InfinityFlow", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let configuration = ModelConfiguration(url: folder.appendingPathComponent("History.store"))
        do {
            return try ModelContainer(for: Transcript.self, configurations: configuration)
        } catch {
            fatalError("Could not open the history store: \(error)")
        }
    }()
}

enum SettingsKey {
    static let hotkey = "hotkey"
    static let engine = "engine"
    static let playSounds = "playSounds"
    static let restoreClipboard = "restoreClipboard"
    static let onboarded = "onboarded"
}
