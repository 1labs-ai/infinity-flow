import Foundation
import Observation
import SwiftData

final class Transcript: ExpandedModel {
    var uuid: UUID = UUID() {
        @storageRestrictions(accesses: _$backingData, initializes: _uuid)
        init { _$backingData.setValue(forKey: \.uuid, to: newValue); _uuid = _SwiftDataNoType() }
        get { read(\.uuid) }
        set { write(\.uuid, newValue) }
    }
    private var _uuid: _SwiftDataNoType

    /// The text that was pasted (after cleanup).
    var text: String {
        @storageRestrictions(accesses: _$backingData, initializes: _text)
        init { _$backingData.setValue(forKey: \.text, to: newValue); _text = _SwiftDataNoType() }
        get { read(\.text) }
        set { write(\.text, newValue) }
    }
    private var _text: _SwiftDataNoType

    /// What was heard before cleanup, kept when cleanup changed it.
    var rawText: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _rawText)
        init { _$backingData.setValue(forKey: \.rawText, to: newValue); _rawText = _SwiftDataNoType() }
        get { read(\.rawText) }
        set { write(\.rawText, newValue) }
    }
    private var _rawText: _SwiftDataNoType

    var createdAt: Date {
        @storageRestrictions(accesses: _$backingData, initializes: _createdAt)
        init { _$backingData.setValue(forKey: \.createdAt, to: newValue); _createdAt = _SwiftDataNoType() }
        get { read(\.createdAt) }
        set { write(\.createdAt, newValue) }
    }
    private var _createdAt: _SwiftDataNoType

    var duration: Double {
        @storageRestrictions(accesses: _$backingData, initializes: _duration)
        init { _$backingData.setValue(forKey: \.duration, to: newValue); _duration = _SwiftDataNoType() }
        get { read(\.duration) }
        set { write(\.duration, newValue) }
    }
    private var _duration: _SwiftDataNoType

    var engine: String {
        @storageRestrictions(accesses: _$backingData, initializes: _engine)
        init { _$backingData.setValue(forKey: \.engine, to: newValue); _engine = _SwiftDataNoType() }
        get { read(\.engine) }
        set { write(\.engine, newValue) }
    }
    private var _engine: _SwiftDataNoType

    /// Cloud preset ID when transcribed in the cloud.
    var provider: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _provider)
        init { _$backingData.setValue(forKey: \.provider, to: newValue); _provider = _SwiftDataNoType() }
        get { read(\.provider) }
        set { write(\.provider, newValue) }
    }
    private var _provider: _SwiftDataNoType

    /// The app that was frontmost when dictation started.
    var appName: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _appName)
        init { _$backingData.setValue(forKey: \.appName, to: newValue); _appName = _SwiftDataNoType() }
        get { read(\.appName) }
        set { write(\.appName, newValue) }
    }
    private var _appName: _SwiftDataNoType

    /// "done" or "failed". A failed dictation keeps its audio so it can be retried.
    var status: String = "done" {
        @storageRestrictions(accesses: _$backingData, initializes: _status)
        init { _$backingData.setValue(forKey: \.status, to: newValue); _status = _SwiftDataNoType() }
        get { read(\.status) }
        set { write(\.status, newValue) }
    }
    private var _status: _SwiftDataNoType

    var audioFileName: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _audioFileName)
        init { _$backingData.setValue(forKey: \.audioFileName, to: newValue); _audioFileName = _SwiftDataNoType() }
        get { read(\.audioFileName) }
        set { write(\.audioFileName, newValue) }
    }
    private var _audioFileName: _SwiftDataNoType

    var errorMessage: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _errorMessage)
        init { _$backingData.setValue(forKey: \.errorMessage, to: newValue); _errorMessage = _SwiftDataNoType() }
        get { read(\.errorMessage) }
        set { write(\.errorMessage, newValue) }
    }
    private var _errorMessage: _SwiftDataNoType

    var pasted: Bool = false {
        @storageRestrictions(accesses: _$backingData, initializes: _pasted)
        init { _$backingData.setValue(forKey: \.pasted, to: newValue); _pasted = _SwiftDataNoType() }
        get { read(\.pasted) }
        set { write(\.pasted, newValue) }
    }
    private var _pasted: _SwiftDataNoType


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

    // MARK: SwiftData (what `@Model` would generate; see ExpandedModel)

    private var _$backingData: any BackingData<Transcript> = Transcript.createBackingData()
    let _$observationRegistrar = ObservationRegistrar()

    var persistentBackingData: any BackingData<Transcript> {
        get { _$backingData }
        set { _$backingData = newValue }
    }

    static var schemaMetadata: [Schema.PropertyMetadata] {
        [
            Schema.PropertyMetadata(name: "uuid", keypath: \Transcript.uuid, defaultValue: UUID(), metadata: nil),
            Schema.PropertyMetadata(name: "text", keypath: \Transcript.text, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "rawText", keypath: \Transcript.rawText, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "createdAt", keypath: \Transcript.createdAt, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "duration", keypath: \Transcript.duration, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "engine", keypath: \Transcript.engine, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "provider", keypath: \Transcript.provider, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "appName", keypath: \Transcript.appName, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "status", keypath: \Transcript.status, defaultValue: "done", metadata: nil),
            Schema.PropertyMetadata(name: "audioFileName", keypath: \Transcript.audioFileName, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "errorMessage", keypath: \Transcript.errorMessage, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "pasted", keypath: \Transcript.pasted, defaultValue: false, metadata: nil),
        ]
    }

    required init(backingData: any BackingData<Transcript>) {
        _uuid = _SwiftDataNoType()
        _text = _SwiftDataNoType()
        _rawText = _SwiftDataNoType()
        _createdAt = _SwiftDataNoType()
        _duration = _SwiftDataNoType()
        _engine = _SwiftDataNoType()
        _provider = _SwiftDataNoType()
        _appName = _SwiftDataNoType()
        _status = _SwiftDataNoType()
        _audioFileName = _SwiftDataNoType()
        _errorMessage = _SwiftDataNoType()
        _pasted = _SwiftDataNoType()
        persistentBackingData = backingData
    }
}

extension Transcript: Observable {}

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
            return try ModelContainer(for: Transcript.self, Meeting.self, MeetingSegment.self, MeetingActionItem.self,
                                      configurations: configuration)
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
    static let showInDock = "showInDock"
    static let detectMeetings = "detectMeetings"
    static let stopWhenCallEnds = "stopWhenCallEnds"
    static let meetingEchoCancellation = "meetingEchoCancellation"
    static let meetingLength = "meetingLength"
    static let meetingCalendar = "meetingCalendar"
    static let meetingEngine = "meetingEngine"
    static let speechLanguage = "speechLanguage"
    static let notesLanguage = "notesLanguage"
}
