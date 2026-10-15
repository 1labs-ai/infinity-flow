import Foundation

/// One line of a meeting transcript, with the speaker's display name.
struct MeetingLine: Equatable {
    let speaker: String
    let start: Double
    let text: String

    var formatted: String { "[\(MeetingFormat.timestamp(start))] \(speaker): \(text)" }
}

/// Decides where to cut a track into chunks. Chunks end at a pause once they are long enough,
/// so words aren't split, and never run past `maximum` so the live transcript keeps up.
struct ChunkPolicy {
    var minimum: Double = 12
    var maximum: Double = 30
    /// A pause at least this long ends a chunk that has reached `minimum`.
    var pauseToCut: Double = 0.6
    /// Levels (0...1, see `AudioLevel.normalized`) at or above this count as speech.
    var speechLevel: Float = 0.3
    /// A chunk with less speech than this is silence and is not transcribed.
    var minimumSpeech: Double = 0.4

    private(set) var length: Double = 0
    private(set) var speech: Double = 0
    private var trailingPause: Double = 0

    init(minimum: Double = 12, maximum: Double = 30) {
        self.minimum = minimum
        self.maximum = maximum
    }

    /// Adds `seconds` of audio at `level`. Returns true when the chunk should end after this audio.
    mutating func add(seconds: Double, level: Float) -> Bool {
        length += seconds
        if level >= speechLevel {
            speech += seconds
            trailingPause = 0
        } else {
            trailingPause += seconds
        }
        // Durations are sums of buffer lengths; allow for floating-point drift.
        let slack = 1e-6
        return length >= maximum - slack || (length >= minimum - slack && trailingPause >= pauseToCut - slack)
    }

    var hasSpeech: Bool { speech >= minimumSpeech }

    mutating func reset() {
        length = 0
        speech = 0
        trailingPause = 0
    }
}

enum MeetingFormat {
    /// "4:05" or "1:02:03".
    static func timestamp(_ seconds: Double) -> String {
        let total = max(0, Int(seconds.rounded(.down)))
        let h = total / 3600, m = total / 60 % 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    /// "1 h 5 min", "12 min" or "40 s".
    static func duration(_ seconds: Double) -> String {
        let total = Int(seconds.rounded())
        if total < 60 { return "\(total) s" }
        let h = total / 3600, m = total / 60 % 60
        return h > 0 ? (m > 0 ? "\(h) h \(m) min" : "\(h) h") : "\(m) min"
    }

    /// Joins consecutive lines from the same speaker, so the transcript reads as turns rather than chunks.
    static func turns(_ lines: [MeetingLine]) -> [MeetingLine] {
        var result: [MeetingLine] = []
        for line in lines {
            if let last = result.last, last.speaker == line.speaker {
                result[result.count - 1] = MeetingLine(speaker: last.speaker, start: last.start, text: last.text + " " + line.text)
            } else {
                result.append(line)
            }
        }
        return result
    }

    static func transcript(_ lines: [MeetingLine]) -> String {
        turns(lines).map(\.formatted).joined(separator: "\n")
    }

    struct Export {
        var title: String
        var date: Date
        var duration: Double
        var attendees: [String] = []
        var summary: String?
        var actionItems: [(text: String, done: Bool)] = []
        var aiNotes: String?
        var userNotes: String = ""
        var lines: [MeetingLine] = []
    }

    /// The whole meeting as Markdown, for pasting into a doc or another notes app.
    static func markdown(_ meeting: Export) -> String {
        var parts = ["# \(meeting.title)"]
        var info = [meeting.date.formatted(date: .abbreviated, time: .shortened), duration(meeting.duration)]
        if !meeting.attendees.isEmpty { info.append("with " + meeting.attendees.joined(separator: ", ")) }
        parts.append(info.joined(separator: " · "))
        if let summary = meeting.summary?.trimmed, !summary.isEmpty {
            parts.append("## Summary\n\n\(summary)")
        }
        if !meeting.actionItems.isEmpty {
            parts.append("## Action items\n\n" + meeting.actionItems.map { "- [\($0.done ? "x" : " ")] \($0.text)" }.joined(separator: "\n"))
        }
        if let notes = meeting.aiNotes?.trimmed, !notes.isEmpty {
            parts.append("## Notes\n\n\(demoteHeadings(notes))")
        }
        if !meeting.userNotes.trimmed.isEmpty {
            parts.append("## My notes\n\n\(meeting.userNotes.trimmed)")
        }
        if !meeting.lines.isEmpty {
            let lines = turns(meeting.lines).map { "**\($0.speaker)** (\(timestamp($0.start))): \($0.text)" }
            parts.append("## Transcript\n\n" + lines.joined(separator: "\n\n"))
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// Nests the AI notes' own "## Topic" headings under "## Notes".
    private static func demoteHeadings(_ markdown: String) -> String {
        markdown.split(separator: "\n", omittingEmptySubsequences: false).map { line in
            line.hasPrefix("#") ? "#" + line : String(line)
        }.joined(separator: "\n")
    }
}

/// The AI's notes for a meeting, parsed from its reply.
struct MeetingNotes: Equatable {
    var title: String?
    var summary: String
    var notes: String
    var actionItems: [String]

    static let instructions = """
        You write meeting notes from a transcript. "You" is the person who recorded the meeting. Be accurate and \
        concise. Use only what was said, never invent names, numbers or decisions, and keep numbers, names and \
        terms exactly as written. If something is unclear, leave it out. Write in the language of the transcript.
        """

    static let format = """
        Reply in exactly this format:
        TITLE: a short title for the meeting, at most 8 words
        SUMMARY: one or two sentences on what the meeting was about and what was decided
        NOTES:
        ## A short topic heading
        - a key point, decision or detail
        (repeat for each topic)
        ACTION ITEMS:
        - a task, starting with the owner's name when one was said
        (write "- None" when there are no tasks)
        """

    static let partInstructions = """
        You take notes on one part of a longer meeting transcript. List the topics, key points, decisions, \
        numbers and tasks (with owners) from this part as short bullet points. Use only what was said. \
        Write in the language of the transcript.
        """

    /// Parses a reply written in `format`. Tolerates bold labels, missing sections and "None".
    static func parse(_ reply: String) -> MeetingNotes {
        enum Section { case none, summary, notes, actions }
        var title: String?
        var summary: [String] = []
        var notes: [String] = []
        var actions: [String] = []
        var section = Section.none

        for rawLine in reply.components(separatedBy: .newlines) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let label = line.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
            let upper = label.uppercased()
            if upper.hasPrefix("TITLE:") {
                title = String(label.dropFirst(6)).trimmed.trimmingCharacters(in: CharacterSet(charactersIn: "\"#"))
                section = .none
            } else if upper.hasPrefix("SUMMARY:") {
                section = .summary
                summary.append(String(label.dropFirst(8)))
            } else if upper.hasPrefix("NOTES:") {
                section = .notes
                notes.append(String(label.dropFirst(6)))
            } else if upper.hasPrefix("ACTION ITEMS:") {
                section = .actions
                actions.append(String(label.dropFirst(13)))
            } else {
                switch section {
                case .summary: summary.append(line)
                case .notes: notes.append(rawLine)
                case .actions: actions.append(line)
                case .none: if title == nil, !line.isEmpty, summary.isEmpty { summary.append(line) }
                }
            }
        }

        let items = actions.compactMap { line -> String? in
            var text = line.trimmed
            for prefix in ["- [ ]", "- [x]", "-", "*", "•"] where text.hasPrefix(prefix) {
                text = String(text.dropFirst(prefix.count)).trimmed
                break
            }
            if let dot = text.firstIndex(of: "."), text[..<dot].allSatisfy(\.isNumber), !text[..<dot].isEmpty {
                text = String(text[text.index(after: dot)...]).trimmed
            }
            for suffix in [" - None", " – None", " (None)", " - N/A"] where text.hasSuffix(suffix) {
                text = String(text.dropLast(suffix.count)).trimmed
            }
            let lowered = text.lowercased().trimmingCharacters(in: .punctuationCharacters)
            return text.isEmpty || lowered == "none" || lowered == "n/a" ? nil : text
        }
        return MeetingNotes(
            title: title?.isEmpty == false ? title : nil,
            summary: summary.joined(separator: " ").trimmed,
            notes: notes.joined(separator: "\n").trimmed,
            actionItems: items)
    }

    /// Splits text into pieces of at most `budget` characters, breaking between lines.
    static func split(_ lines: [String], budget: Int) -> [String] {
        var pieces: [String] = []
        var current = ""
        for line in lines {
            let line = line.count > budget ? String(line.prefix(budget)) : line
            if !current.isEmpty, current.count + line.count + 1 > budget {
                pieces.append(current)
                current = ""
            }
            current += current.isEmpty ? line : "\n" + line
        }
        if !current.isEmpty { pieces.append(current) }
        return pieces
    }
}

/// Without echo cancellation (it can't always start), a mic near speakers also hears the call. Such a "You" part
/// repeats what "Others" said at the same moment; it is dropped from the transcript.
enum EchoFilter {
    /// True when most of `mine`'s words were said by others in overlapping parts.
    static func isEcho(_ mine: String, theirs: [String]) -> Bool {
        let words = MeetingContext.keywords(mine)
        guard words.count >= 3 else { return false }
        let heard = theirs.reduce(into: Set<String>()) { $0.formUnion(MeetingContext.keywords($1)) }
        return Double(words.intersection(heard).count) / Double(words.count) >= 0.6
    }

    /// Others' parts that overlap a part spanning `start..<end`, with a little slack for chunk boundaries.
    static func overlaps(start: Double, end: Double, with other: (start: Double, end: Double)) -> Bool {
        other.start < end + 2 && other.end > start - 2
    }
}

/// Picks the parts of a meeting that fit a model's prompt when answering a question about it.
enum MeetingContext {
    /// The whole transcript when it fits; otherwise the lines that share the most words with the question,
    /// kept in spoken order, until the budget is used.
    static func select(question: String, lines: [String], budget: Int) -> [String] {
        let total = lines.reduce(0) { $0 + $1.count + 1 }
        guard total > budget else { return lines }
        let words = keywords(question)
        let scored = lines.enumerated().map { index, line in
            (index: index, score: keywords(line).intersection(words).count)
        }
        var chosen = Set<Int>()
        var used = 0
        for candidate in scored.sorted(by: { $0.score == $1.score ? $0.index < $1.index : $0.score > $1.score }) {
            let cost = lines[candidate.index].count + 1
            guard used + cost <= budget else { continue }
            chosen.insert(candidate.index)
            used += cost
        }
        return lines.indices.filter(chosen.contains).map { lines[$0] }
    }

    private static let stopWords: Set<String> = [
        "the", "and", "for", "that", "this", "with", "what", "was", "were", "did", "does", "who", "how", "when",
        "why", "are", "you", "about", "from", "have", "has", "had", "they", "them", "their", "will", "would", "can",
        "could", "should", "there", "here", "into", "said", "say", "our", "out", "any", "all", "not",
    ]

    static func keywords(_ text: String) -> Set<String> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter && !$0.isNumber })
            .map(String.init)
            .filter { $0.count > 2 && !stopWords.contains($0) })
    }

    static let instructions = """
        You answer questions about a meeting using only its notes and transcript below. "You" is the person who \
        recorded it. If the answer isn't in the meeting, say so plainly. Be brief, and quote numbers and names exactly.
        """
}

/// Call apps whose use of the microphone suggests a meeting. Browsers are included because
/// Google Meet and other web calls run in them.
enum MeetingApps {
    private static let known: [(prefix: String, name: String)] = [
        ("us.zoom.", "Zoom"),
        ("com.microsoft.teams", "Microsoft Teams"),
        ("com.cisco.webex", "Webex"),
        ("Cisco-Systems.Spark", "Webex"),
        ("com.apple.FaceTime", "FaceTime"),
        ("com.tinyspeck.slackmacgap", "Slack"),
        ("com.hnc.Discord", "Discord"),
        ("net.whatsapp.WhatsApp", "WhatsApp"),
        ("desktop.WhatsApp", "WhatsApp"),
        ("com.skype.", "Skype"),
        ("ru.keepcoder.Telegram", "Telegram"),
        ("com.google.Chrome", "Google Chrome"),
        ("com.apple.Safari", "Safari"),
        ("com.apple.WebKit", "Safari"),
        ("com.microsoft.edgemac", "Microsoft Edge"),
        ("company.thebrowser.", "Arc"),
        ("org.mozilla.firefox", "Firefox"),
        ("com.brave.Browser", "Brave"),
        ("com.vivaldi.Vivaldi", "Vivaldi"),
        ("com.operasoftware.", "Opera"),
    ]

    /// The display name of a call app, or `nil` when the bundle ID isn't one.
    static func name(bundleID: String) -> String? {
        known.first { bundleID.hasPrefix($0.prefix) }?.name
    }
}

enum MeetingLength: Int, CaseIterable, Identifiable {
    case oneHour = 1, twoHours = 2, threeHours = 3, fourHours = 4

    var id: Int { rawValue }
    var seconds: Double { Double(rawValue) * 3600 }
    var title: String { rawValue == 1 ? "1 hour" : "\(rawValue) hours" }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
