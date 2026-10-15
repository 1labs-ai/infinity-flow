import Foundation
import Observation
import SwiftData

/// One recorded meeting: two audio tracks cut into short chunks, their transcript, your own notes,
/// and the AI notes written afterwards.
final class Meeting: ExpandedModel {
    var uuid: UUID = UUID() {
        @storageRestrictions(accesses: _$backingData, initializes: _uuid)
        init { _$backingData.setValue(forKey: \.uuid, to: newValue); _uuid = _SwiftDataNoType() }
        get { read(\.uuid) }
        set { write(\.uuid, newValue) }
    }
    private var _uuid: _SwiftDataNoType

    var title: String {
        @storageRestrictions(accesses: _$backingData, initializes: _title)
        init { _$backingData.setValue(forKey: \.title, to: newValue); _title = _SwiftDataNoType() }
        get { read(\.title) }
        set { write(\.title, newValue) }
    }
    private var _title: _SwiftDataNoType

    var createdAt: Date {
        @storageRestrictions(accesses: _$backingData, initializes: _createdAt)
        init { _$backingData.setValue(forKey: \.createdAt, to: newValue); _createdAt = _SwiftDataNoType() }
        get { read(\.createdAt) }
        set { write(\.createdAt, newValue) }
    }
    private var _createdAt: _SwiftDataNoType

    var endedAt: Date? {
        @storageRestrictions(accesses: _$backingData, initializes: _endedAt)
        init { _$backingData.setValue(forKey: \.endedAt, to: newValue); _endedAt = _SwiftDataNoType() }
        get { read(\.endedAt) }
        set { write(\.endedAt, newValue) }
    }
    private var _endedAt: _SwiftDataNoType

    /// Seconds recorded, not counting pauses.
    var duration: Double = 0 {
        @storageRestrictions(accesses: _$backingData, initializes: _duration)
        init { _$backingData.setValue(forKey: \.duration, to: newValue); _duration = _SwiftDataNoType() }
        get { read(\.duration) }
        set { write(\.duration, newValue) }
    }
    private var _duration: _SwiftDataNoType

    /// See `MeetingStatus`.
    var status: String = MeetingStatus.recording.rawValue {
        @storageRestrictions(accesses: _$backingData, initializes: _status)
        init { _$backingData.setValue(forKey: \.status, to: newValue); _status = _SwiftDataNoType() }
        get { read(\.status) }
        set { write(\.status, newValue) }
    }
    private var _status: _SwiftDataNoType

    /// The call app detected when the meeting started, such as "Zoom".
    var appName: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _appName)
        init { _$backingData.setValue(forKey: \.appName, to: newValue); _appName = _SwiftDataNoType() }
        get { read(\.appName) }
        set { write(\.appName, newValue) }
    }
    private var _appName: _SwiftDataNoType

    /// The calendar event this meeting was matched to, when calendar titles are on.
    var calendarTitle: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _calendarTitle)
        init { _$backingData.setValue(forKey: \.calendarTitle, to: newValue); _calendarTitle = _SwiftDataNoType() }
        get { read(\.calendarTitle) }
        set { write(\.calendarTitle, newValue) }
    }
    private var _calendarTitle: _SwiftDataNoType

    var attendees: [String] = [] {
        @storageRestrictions(accesses: _$backingData, initializes: _attendees)
        init { _$backingData.setValue(forKey: \.attendees, to: newValue); _attendees = _SwiftDataNoType() }
        get { read(\.attendees) }
        set { write(\.attendees, newValue) }
    }
    private var _attendees: _SwiftDataNoType

    /// What you typed during the meeting. It is fed into the AI notes.
    var userNotes: String = "" {
        @storageRestrictions(accesses: _$backingData, initializes: _userNotes)
        init { _$backingData.setValue(forKey: \.userNotes, to: newValue); _userNotes = _SwiftDataNoType() }
        get { read(\.userNotes) }
        set { write(\.userNotes, newValue) }
    }
    private var _userNotes: _SwiftDataNoType

    /// One- or two-sentence overview written by the AI.
    var summary: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _summary)
        init { _$backingData.setValue(forKey: \.summary, to: newValue); _summary = _SwiftDataNoType() }
        get { read(\.summary) }
        set { write(\.summary, newValue) }
    }
    private var _summary: _SwiftDataNoType

    /// Markdown notes written by the AI: topics, decisions and key points.
    var aiNotes: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _aiNotes)
        init { _$backingData.setValue(forKey: \.aiNotes, to: newValue); _aiNotes = _SwiftDataNoType() }
        get { read(\.aiNotes) }
        set { write(\.aiNotes, newValue) }
    }
    private var _aiNotes: _SwiftDataNoType

    /// Why notes couldn't be written, shown with a retry button.
    var notesError: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _notesError)
        init { _$backingData.setValue(forKey: \.notesError, to: newValue); _notesError = _SwiftDataNoType() }
        get { read(\.notesError) }
        set { write(\.notesError, newValue) }
    }
    private var _notesError: _SwiftDataNoType

    /// Display names for the two speakers, set by renaming them in the transcript.
    var youName: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _youName)
        init { _$backingData.setValue(forKey: \.youName, to: newValue); _youName = _SwiftDataNoType() }
        get { read(\.youName) }
        set { write(\.youName, newValue) }
    }
    private var _youName: _SwiftDataNoType

    var othersName: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _othersName)
        init { _$backingData.setValue(forKey: \.othersName, to: newValue); _othersName = _SwiftDataNoType() }
        get { read(\.othersName) }
        set { write(\.othersName, newValue) }
    }
    private var _othersName: _SwiftDataNoType

    /// Whether any audio from other participants (system audio) was captured.
    var heardOthers: Bool = false {
        @storageRestrictions(accesses: _$backingData, initializes: _heardOthers)
        init { _$backingData.setValue(forKey: \.heardOthers, to: newValue); _heardOthers = _SwiftDataNoType() }
        get { read(\.heardOthers) }
        set { write(\.heardOthers, newValue) }
    }
    private var _heardOthers: _SwiftDataNoType

    var segments: [MeetingSegment]? = [] {
        @storageRestrictions(accesses: _$backingData, initializes: _segments)
        init { _$backingData.setValue(forKey: \.segments, to: newValue); _segments = _SwiftDataNoType() }
        get { read(\.segments) }
        set { write(\.segments, newValue) }
    }
    private var _segments: _SwiftDataNoType

    var actionItems: [MeetingActionItem]? = [] {
        @storageRestrictions(accesses: _$backingData, initializes: _actionItems)
        init { _$backingData.setValue(forKey: \.actionItems, to: newValue); _actionItems = _SwiftDataNoType() }
        get { read(\.actionItems) }
        set { write(\.actionItems, newValue) }
    }
    private var _actionItems: _SwiftDataNoType

    init(title: String, createdAt: Date = .now) {
        self.title = title
        self.createdAt = createdAt
    }

    var meetingStatus: MeetingStatus { MeetingStatus(rawValue: status) ?? .done }

    var folder: URL { MeetingStore.folder(for: uuid) }

    /// Segments in spoken order.
    var orderedSegments: [MeetingSegment] {
        (segments ?? []).sorted { $0.start == $1.start ? $0.speaker < $1.speaker : $0.start < $1.start }
    }

    var orderedActionItems: [MeetingActionItem] {
        (actionItems ?? []).sorted { $0.order == $1.order ? $0.createdAt < $1.createdAt : $0.order < $1.order }
    }

    func name(of speaker: MeetingSpeaker) -> String {
        let custom = speaker == .you ? youName : othersName
        if let custom, !custom.trimmingCharacters(in: .whitespaces).isEmpty { return custom }
        return speaker.defaultName(attendees: attendees)
    }

    /// The conversation in the order it was said: each part split into its timed sentences, both tracks merged,
    /// and echo of the call removed from your track.
    var transcriptLines: [MeetingLine] {
        let lines = orderedSegments.filter { $0.isDone && !$0.text.isEmpty }.flatMap {
            TrackLine.lines(speaker: $0.meetingSpeaker, partStart: $0.start, partDuration: $0.duration, text: $0.text,
                            timed: $0.sentences, segment: $0.uuid)
        }
        return TrackLine.conversation(lines).map {
            MeetingLine(speaker: name(of: $0.speaker), start: $0.start, text: $0.text, segment: $0.segment)
        }
    }

    /// Usage for the cost meter: one record per cloud request.
    var usage: [UsageRecord] {
        (segments ?? []).filter(\.isDone).map {
            UsageRecord(date: createdAt.addingTimeInterval($0.start), duration: $0.duration, provider: $0.provider)
        }
    }

    /// Usage for the privacy receipt: the whole meeting counts once, as cloud if any part was sent.
    var privacyRecord: UsageRecord {
        let cloud = (segments ?? []).first { $0.provider != nil }?.provider
        return UsageRecord(date: createdAt, duration: duration, provider: cloud)
    }

    // MARK: SwiftData (what `@Model` would generate; see ExpandedModel)

    private var _$backingData: any BackingData<Meeting> = Meeting.createBackingData()
    let _$observationRegistrar = ObservationRegistrar()

    var persistentBackingData: any BackingData<Meeting> {
        get { _$backingData }
        set { _$backingData = newValue }
    }

    static var schemaMetadata: [Schema.PropertyMetadata] {
        [
            Schema.PropertyMetadata(name: "uuid", keypath: \Meeting.uuid, defaultValue: UUID(), metadata: nil),
            Schema.PropertyMetadata(name: "title", keypath: \Meeting.title, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "createdAt", keypath: \Meeting.createdAt, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "endedAt", keypath: \Meeting.endedAt, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "duration", keypath: \Meeting.duration, defaultValue: 0.0, metadata: nil),
            Schema.PropertyMetadata(name: "status", keypath: \Meeting.status, defaultValue: MeetingStatus.recording.rawValue, metadata: nil),
            Schema.PropertyMetadata(name: "appName", keypath: \Meeting.appName, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "calendarTitle", keypath: \Meeting.calendarTitle, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "attendees", keypath: \Meeting.attendees, defaultValue: [String](), metadata: nil),
            Schema.PropertyMetadata(name: "userNotes", keypath: \Meeting.userNotes, defaultValue: "", metadata: nil),
            Schema.PropertyMetadata(name: "summary", keypath: \Meeting.summary, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "aiNotes", keypath: \Meeting.aiNotes, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "notesError", keypath: \Meeting.notesError, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "youName", keypath: \Meeting.youName, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "othersName", keypath: \Meeting.othersName, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "heardOthers", keypath: \Meeting.heardOthers, defaultValue: false, metadata: nil),
            Schema.PropertyMetadata(name: "segments", keypath: \Meeting.segments, defaultValue: [MeetingSegment](), metadata: Schema.Relationship(deleteRule: .cascade, inverse: \MeetingSegment.meeting)),
            Schema.PropertyMetadata(name: "actionItems", keypath: \Meeting.actionItems, defaultValue: [MeetingActionItem](), metadata: Schema.Relationship(deleteRule: .cascade, inverse: \MeetingActionItem.meeting)),
        ]
    }

    required init(backingData: any BackingData<Meeting>) {
        _uuid = _SwiftDataNoType()
        _title = _SwiftDataNoType()
        _createdAt = _SwiftDataNoType()
        _endedAt = _SwiftDataNoType()
        _duration = _SwiftDataNoType()
        _status = _SwiftDataNoType()
        _appName = _SwiftDataNoType()
        _calendarTitle = _SwiftDataNoType()
        _attendees = _SwiftDataNoType()
        _userNotes = _SwiftDataNoType()
        _summary = _SwiftDataNoType()
        _aiNotes = _SwiftDataNoType()
        _notesError = _SwiftDataNoType()
        _youName = _SwiftDataNoType()
        _othersName = _SwiftDataNoType()
        _heardOthers = _SwiftDataNoType()
        _segments = _SwiftDataNoType()
        _actionItems = _SwiftDataNoType()
        persistentBackingData = backingData
    }
}

extension Meeting: Observable {}

enum MeetingStatus: String {
    /// Capturing audio (also while paused).
    case recording
    /// Audio has stopped; chunks are still being transcribed or notes written.
    case processing
    case done
}

enum MeetingSpeaker: String, CaseIterable {
    /// Your microphone.
    case you
    /// Everything your Mac plays: the other people on the call.
    case others

    func defaultName(attendees: [String]) -> String {
        switch self {
        case .you: "You"
        case .others: attendees.count == 1 ? attendees[0] : "Others"
        }
    }
}

/// A chunk of one speaker's audio and its transcript.
final class MeetingSegment: ExpandedModel {
    var uuid: UUID = UUID() {
        @storageRestrictions(accesses: _$backingData, initializes: _uuid)
        init { _$backingData.setValue(forKey: \.uuid, to: newValue); _uuid = _SwiftDataNoType() }
        get { read(\.uuid) }
        set { write(\.uuid, newValue) }
    }
    private var _uuid: _SwiftDataNoType

    /// See `MeetingSpeaker`.
    var speaker: String {
        @storageRestrictions(accesses: _$backingData, initializes: _speaker)
        init { _$backingData.setValue(forKey: \.speaker, to: newValue); _speaker = _SwiftDataNoType() }
        get { read(\.speaker) }
        set { write(\.speaker, newValue) }
    }
    private var _speaker: _SwiftDataNoType

    /// Seconds from the start of the meeting, not counting pauses.
    var start: Double {
        @storageRestrictions(accesses: _$backingData, initializes: _start)
        init { _$backingData.setValue(forKey: \.start, to: newValue); _start = _SwiftDataNoType() }
        get { read(\.start) }
        set { write(\.start, newValue) }
    }
    private var _start: _SwiftDataNoType

    var duration: Double {
        @storageRestrictions(accesses: _$backingData, initializes: _duration)
        init { _$backingData.setValue(forKey: \.duration, to: newValue); _duration = _SwiftDataNoType() }
        get { read(\.duration) }
        set { write(\.duration, newValue) }
    }
    private var _duration: _SwiftDataNoType

    var text: String = "" {
        @storageRestrictions(accesses: _$backingData, initializes: _text)
        init { _$backingData.setValue(forKey: \.text, to: newValue); _text = _SwiftDataNoType() }
        get { read(\.text) }
        set { write(\.text, newValue) }
    }
    private var _text: _SwiftDataNoType

    /// "pending", "done" or "failed". Pending and failed chunks keep their audio.
    var status: String = "pending" {
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

    /// Cloud preset ID when transcribed in the cloud.
    var provider: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _provider)
        init { _$backingData.setValue(forKey: \.provider, to: newValue); _provider = _SwiftDataNoType() }
        get { read(\.provider) }
        set { write(\.provider, newValue) }
    }
    private var _provider: _SwiftDataNoType

    var meeting: Meeting? {
        @storageRestrictions(accesses: _$backingData, initializes: _meeting)
        init { _$backingData.setValue(forKey: \.meeting, to: newValue); _meeting = _SwiftDataNoType() }
        get { read(\.meeting) }
        set { write(\.meeting, newValue) }
    }
    private var _meeting: _SwiftDataNoType

    /// The part's sentences with their times (JSON `[TimedText]`), when the engine gave timestamps.
    var timedLines: String? {
        @storageRestrictions(accesses: _$backingData, initializes: _timedLines)
        init { _$backingData.setValue(forKey: \.timedLines, to: newValue); _timedLines = _SwiftDataNoType() }
        get { read(\.timedLines) }
        set { write(\.timedLines, newValue) }
    }
    private var _timedLines: _SwiftDataNoType

    var sentences: [TimedText]? {
        get { timedLines.flatMap { try? JSONDecoder().decode([TimedText].self, from: Data($0.utf8)) } }
        set { timedLines = newValue.flatMap { try? String(decoding: JSONEncoder().encode($0), as: UTF8.self) } }
    }

    init(speaker: MeetingSpeaker, start: Double, duration: Double, audioFileName: String) {
        self.speaker = speaker.rawValue
        self.start = start
        self.duration = duration
        self.audioFileName = audioFileName
    }

    var meetingSpeaker: MeetingSpeaker { MeetingSpeaker(rawValue: speaker) ?? .others }
    var isDone: Bool { status == "done" }
    var isFailed: Bool { status == "failed" }
    var isPending: Bool { status == "pending" }

    var audioURL: URL? {
        guard let audioFileName, let meeting else { return nil }
        return meeting.folder.appendingPathComponent(audioFileName)
    }

    // MARK: SwiftData (what `@Model` would generate; see ExpandedModel)

    private var _$backingData: any BackingData<MeetingSegment> = MeetingSegment.createBackingData()
    let _$observationRegistrar = ObservationRegistrar()

    var persistentBackingData: any BackingData<MeetingSegment> {
        get { _$backingData }
        set { _$backingData = newValue }
    }

    static var schemaMetadata: [Schema.PropertyMetadata] {
        [
            Schema.PropertyMetadata(name: "uuid", keypath: \MeetingSegment.uuid, defaultValue: UUID(), metadata: nil),
            Schema.PropertyMetadata(name: "speaker", keypath: \MeetingSegment.speaker, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "start", keypath: \MeetingSegment.start, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "duration", keypath: \MeetingSegment.duration, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "text", keypath: \MeetingSegment.text, defaultValue: "", metadata: nil),
            Schema.PropertyMetadata(name: "status", keypath: \MeetingSegment.status, defaultValue: "pending", metadata: nil),
            Schema.PropertyMetadata(name: "audioFileName", keypath: \MeetingSegment.audioFileName, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "errorMessage", keypath: \MeetingSegment.errorMessage, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "provider", keypath: \MeetingSegment.provider, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "meeting", keypath: \MeetingSegment.meeting, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "timedLines", keypath: \MeetingSegment.timedLines, defaultValue: nil, metadata: nil),
        ]
    }

    required init(backingData: any BackingData<MeetingSegment>) {
        _uuid = _SwiftDataNoType()
        _speaker = _SwiftDataNoType()
        _start = _SwiftDataNoType()
        _duration = _SwiftDataNoType()
        _text = _SwiftDataNoType()
        _status = _SwiftDataNoType()
        _audioFileName = _SwiftDataNoType()
        _errorMessage = _SwiftDataNoType()
        _provider = _SwiftDataNoType()
        _meeting = _SwiftDataNoType()
        _timedLines = _SwiftDataNoType()
        persistentBackingData = backingData
    }
}

extension MeetingSegment: Observable {}

final class MeetingActionItem: ExpandedModel {
    var uuid: UUID = UUID() {
        @storageRestrictions(accesses: _$backingData, initializes: _uuid)
        init { _$backingData.setValue(forKey: \.uuid, to: newValue); _uuid = _SwiftDataNoType() }
        get { read(\.uuid) }
        set { write(\.uuid, newValue) }
    }
    private var _uuid: _SwiftDataNoType

    var text: String {
        @storageRestrictions(accesses: _$backingData, initializes: _text)
        init { _$backingData.setValue(forKey: \.text, to: newValue); _text = _SwiftDataNoType() }
        get { read(\.text) }
        set { write(\.text, newValue) }
    }
    private var _text: _SwiftDataNoType

    var done: Bool = false {
        @storageRestrictions(accesses: _$backingData, initializes: _done)
        init { _$backingData.setValue(forKey: \.done, to: newValue); _done = _SwiftDataNoType() }
        get { read(\.done) }
        set { write(\.done, newValue) }
    }
    private var _done: _SwiftDataNoType

    var order: Int = 0 {
        @storageRestrictions(accesses: _$backingData, initializes: _order)
        init { _$backingData.setValue(forKey: \.order, to: newValue); _order = _SwiftDataNoType() }
        get { read(\.order) }
        set { write(\.order, newValue) }
    }
    private var _order: _SwiftDataNoType

    var createdAt: Date = Date.now {
        @storageRestrictions(accesses: _$backingData, initializes: _createdAt)
        init { _$backingData.setValue(forKey: \.createdAt, to: newValue); _createdAt = _SwiftDataNoType() }
        get { read(\.createdAt) }
        set { write(\.createdAt, newValue) }
    }
    private var _createdAt: _SwiftDataNoType

    var meeting: Meeting? {
        @storageRestrictions(accesses: _$backingData, initializes: _meeting)
        init { _$backingData.setValue(forKey: \.meeting, to: newValue); _meeting = _SwiftDataNoType() }
        get { read(\.meeting) }
        set { write(\.meeting, newValue) }
    }
    private var _meeting: _SwiftDataNoType

    init(text: String, order: Int) {
        self.text = text
        self.order = order
    }

    // MARK: SwiftData (what `@Model` would generate; see ExpandedModel)

    private var _$backingData: any BackingData<MeetingActionItem> = MeetingActionItem.createBackingData()
    let _$observationRegistrar = ObservationRegistrar()

    var persistentBackingData: any BackingData<MeetingActionItem> {
        get { _$backingData }
        set { _$backingData = newValue }
    }

    static var schemaMetadata: [Schema.PropertyMetadata] {
        [
            Schema.PropertyMetadata(name: "uuid", keypath: \MeetingActionItem.uuid, defaultValue: UUID(), metadata: nil),
            Schema.PropertyMetadata(name: "text", keypath: \MeetingActionItem.text, defaultValue: nil, metadata: nil),
            Schema.PropertyMetadata(name: "done", keypath: \MeetingActionItem.done, defaultValue: false, metadata: nil),
            Schema.PropertyMetadata(name: "order", keypath: \MeetingActionItem.order, defaultValue: 0, metadata: nil),
            Schema.PropertyMetadata(name: "createdAt", keypath: \MeetingActionItem.createdAt, defaultValue: Date.now, metadata: nil),
            Schema.PropertyMetadata(name: "meeting", keypath: \MeetingActionItem.meeting, defaultValue: nil, metadata: nil),
        ]
    }

    required init(backingData: any BackingData<MeetingActionItem>) {
        _uuid = _SwiftDataNoType()
        _text = _SwiftDataNoType()
        _done = _SwiftDataNoType()
        _order = _SwiftDataNoType()
        _createdAt = _SwiftDataNoType()
        _meeting = _SwiftDataNoType()
        persistentBackingData = backingData
    }
}

extension MeetingActionItem: Observable {}

enum MeetingStore {
    static let folder: URL = {
        let meetings = Store.folder.appendingPathComponent("Meetings", isDirectory: true)
        try? FileManager.default.createDirectory(at: meetings, withIntermediateDirectories: true)
        return meetings
    }()

    static func folder(for id: UUID) -> URL {
        folder.appendingPathComponent(id.uuidString, isDirectory: true)
    }

    /// Audio files of a meeting and their total size in bytes.
    static func usage() -> (count: Int, bytes: Int64) {
        let keys: [URLResourceKey] = [.fileSizeKey, .isRegularFileKey]
        guard let files = FileManager.default.enumerator(at: folder, includingPropertiesForKeys: keys) else { return (0, 0) }
        var count = 0
        var bytes: Int64 = 0
        for case let file as URL in files where file.pathExtension == "wav" {
            count += 1
            bytes += Int64((try? file.resourceValues(forKeys: Set(keys)).fileSize) ?? 0)
        }
        return (count, bytes)
    }
}
