import Foundation
import SwiftData

/// One recorded meeting: two audio tracks cut into short chunks, their transcript, your own notes,
/// and the AI notes written afterwards.
@Model
final class Meeting {
    var uuid = UUID()
    var title: String
    var createdAt: Date
    var endedAt: Date?
    /// Seconds recorded, not counting pauses.
    var duration: Double = 0
    /// See `MeetingStatus`.
    var status: String = MeetingStatus.recording.rawValue
    /// The call app detected when the meeting started, such as "Zoom".
    var appName: String?
    /// The calendar event this meeting was matched to, when calendar titles are on.
    var calendarTitle: String?
    var attendees: [String] = []
    /// What you typed during the meeting. It is fed into the AI notes.
    var userNotes: String = ""
    /// One- or two-sentence overview written by the AI.
    var summary: String?
    /// Markdown notes written by the AI: topics, decisions and key points.
    var aiNotes: String?
    /// Why notes couldn't be written, shown with a retry button.
    var notesError: String?
    /// Display names for the two speakers, set by renaming them in the transcript.
    var youName: String?
    var othersName: String?
    /// Whether any audio from other participants (system audio) was captured.
    var heardOthers: Bool = false

    @Relationship(deleteRule: .cascade, inverse: \MeetingSegment.meeting)
    var segments: [MeetingSegment]? = []

    @Relationship(deleteRule: .cascade, inverse: \MeetingActionItem.meeting)
    var actionItems: [MeetingActionItem]? = []

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

    var transcriptLines: [MeetingLine] {
        orderedSegments.filter { $0.isDone && !$0.text.isEmpty }.map {
            MeetingLine(speaker: name(of: $0.meetingSpeaker), start: $0.start, text: $0.text)
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
}

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
@Model
final class MeetingSegment {
    var uuid = UUID()
    /// See `MeetingSpeaker`.
    var speaker: String
    /// Seconds from the start of the meeting, not counting pauses.
    var start: Double
    var duration: Double
    var text: String = ""
    /// "pending", "done" or "failed". Pending and failed chunks keep their audio.
    var status: String = "pending"
    var audioFileName: String?
    var errorMessage: String?
    /// Cloud preset ID when transcribed in the cloud.
    var provider: String?
    var meeting: Meeting?

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
}

@Model
final class MeetingActionItem {
    var uuid = UUID()
    var text: String
    var done: Bool = false
    var order: Int = 0
    var createdAt: Date = Date.now
    var meeting: Meeting?

    init(text: String, order: Int) {
        self.text = text
        self.order = order
    }
}

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
