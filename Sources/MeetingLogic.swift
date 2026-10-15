import Foundation

/// A sentence with its time from the start of a piece of audio.
struct TimedText: Codable, Equatable {
    var start: Double
    var end: Double
    var text: String
    /// Who said it, for the call track: a name the conversation revealed, or "Speaker 1", "Speaker 2"…
    var speaker: String? = nil
    /// The voice's median pitch in Hz, a cue for telling people apart.
    var pitch: Double? = nil
}

/// Works out who on the call said each line, from the conversation and voice pitch, with a language model.
/// Lines are sent in windows small enough for the model, carrying the speakers found so far.
enum SpeakerAssignment {
    static let instructions = """
        You work out who said each line of a meeting transcript made by speech recognition. "You" is the person who \
        recorded the meeting and is already labeled. The numbered lines come from one or more other people on the call; \
        label each with who said it. Use a person's name only when the conversation makes it clear: they introduce \
        themselves, someone addresses them by name and they answer, or they are named as the one doing what they \
        said. Otherwise use "Speaker 1", "Speaker 2" and so on, the same label for the same person throughout. \
        A question and its answer are different people; someone continuing their own point is the same person. \
        Voice pitch is given in Hz: values within about 25 Hz are probably the same voice, very different values are \
        different people. Before using a new "Speaker N", check whether the line's pitch matches someone you already \
        named; if it does, it is almost certainly that person speaking again. Lines may be in English, Hindi or both. Reply with one line per numbered line, in the form \
        "12: Rahul", and nothing else.
        """

    struct Line {
        let id: Int
        let isYou: Bool
        let text: String
        let pitch: Double?
    }

    /// Windows of lines for the model, each at most `budget` characters.
    static func windows(_ lines: [Line], budget: Int) -> [[Line]] {
        var windows: [[Line]] = []
        var current: [Line] = []
        var size = 0
        for line in lines {
            let cost = line.text.count + 30
            if !current.isEmpty, size + cost > budget {
                windows.append(current)
                current = []
                size = 0
            }
            current.append(line)
            size += cost
        }
        if !current.isEmpty { windows.append(current) }
        return windows
    }

    static func prompt(_ window: [Line], attendees: [String], known: [String: Double?]) -> String {
        var prompt = ""
        if !attendees.isEmpty { prompt += "Invited to the meeting: \(attendees.joined(separator: ", "))\n" }
        if !known.isEmpty {
            let list = known.keys.sorted().map { name in
                if let pitch = known[name] ?? nil { return "\(name) (about \(Int(pitch)) Hz)" }
                return name
            }
            prompt += "Speakers identified earlier in this meeting: \(list.joined(separator: ", "))\n"
        }
        prompt += "\nTranscript:\n"
        for line in window {
            if line.isYou {
                prompt += "You: \(line.text)\n"
            } else {
                let pitch = line.pitch.map { " (voice \(Int($0)) Hz)" } ?? ""
                prompt += "\(line.id)\(pitch): \(line.text)\n"
            }
        }
        return prompt
    }

    /// Merges an unnamed "Speaker N" into a named person whose voice clearly matches: median pitch within 15 Hz,
    /// and nobody else within 30 Hz. Returns the renames.
    static func mergeByVoice(_ pitches: [String: [Double]]) -> [String: String] {
        func median(_ values: [Double]) -> Double? { values.isEmpty ? nil : values.sorted()[values.count / 2] }
        let named = pitches.filter { !isPlaceholder($0.key) }.compactMapValues(median)
        var renames: [String: String] = [:]
        for (label, values) in pitches where isPlaceholder(label) {
            guard let pitch = median(values) else { continue }
            let distances = named.map { (name: $0.key, distance: abs($0.value - pitch)) }.sorted { $0.distance < $1.distance }
            guard let best = distances.first, best.distance <= 15, distances.dropFirst().allSatisfy({ $0.distance > 30 }) else { continue }
            renames[label] = best.name
        }
        return renames
    }

    static func isPlaceholder(_ label: String) -> Bool {
        label.range(of: #"^Speaker \d+$"#, options: .regularExpression) != nil
    }

    /// Reads "12: Rahul" lines. Labels are trimmed of quotes and stray punctuation.
    static func parse(_ reply: String) -> [Int: String] {
        var labels: [Int: String] = [:]
        for raw in reply.components(separatedBy: .newlines) {
            let line = raw.replacingOccurrences(of: "*", with: "").trimmingCharacters(in: .whitespaces)
            guard let colon = line.firstIndex(of: ":") else { continue }
            let number = line[..<colon].trimmingCharacters(in: CharacterSet(charactersIn: "[]# ").union(.whitespaces))
            let label = line[line.index(after: colon)...].trimmingCharacters(in: CharacterSet(charactersIn: "\"'.,").union(.whitespaces))
            guard let id = Int(number), !label.isEmpty, label.count <= 40, label.lowercased() != "you" else { continue }
            labels[id] = label
        }
        return labels
    }
}

/// Estimates the pitch of a voice, to help tell the people on a call apart.
enum PitchEstimator {
    /// The median pitch (Hz) of the voiced 40 ms frames, or `nil` when there's too little voice.
    static func medianPitch(_ samples: [Float], sampleRate: Double) -> Double? {
        let frame = Int(sampleRate * 0.04)
        guard frame > 0, samples.count >= frame else { return nil }
        let minLag = Int(sampleRate / 400), maxLag = min(Int(sampleRate / 70), frame - 1)
        var pitches: [Double] = []
        var index = 0
        // About 30 frames per sentence is plenty for a median, and keeps long meetings fast.
        let hop = max(frame / 2, (samples.count - frame) / 30)
        while index + frame <= samples.count {
            let window = Array(samples[index..<(index + frame)])
            index += hop
            let energy = window.reduce(0) { $0 + $1 * $1 }
            guard energy / Float(frame) > 1e-4 else { continue } // silence
            var bestLag = 0
            var best: Float = 0
            for lag in minLag...maxLag {
                var sum: Float = 0
                for i in 0..<(frame - lag) { sum += window[i] * window[i + lag] }
                if sum > best { best = sum; bestLag = lag }
            }
            // Voiced frames repeat strongly at their period.
            if bestLag > 0, best / energy > 0.5 { pitches.append(sampleRate / Double(bestLag)) }
        }
        guard pitches.count >= 3 else { return nil }
        return pitches.sorted()[pitches.count / 2]
    }
}

/// A sentence of one track, placed on the meeting's timeline.
struct TrackLine: Equatable {
    let speaker: MeetingSpeaker
    let start: Double
    let end: Double
    let text: String
    /// The part (and audio file) it came from.
    var segment: UUID?
    /// The person on the call who said it, once speakers are identified.
    var label: String? = nil
    var pitch: Double? = nil

    /// The sentences of a transcribed part. Parts without timestamps are one line.
    static func lines(speaker: MeetingSpeaker, partStart: Double, partDuration: Double, text: String,
                      timed: [TimedText]?, segment: UUID? = nil) -> [TrackLine] {
        guard let timed, !timed.isEmpty else {
            return text.isEmpty ? [] : [TrackLine(speaker: speaker, start: partStart, end: partStart + partDuration, text: text, segment: segment)]
        }
        return timed.map {
            TrackLine(speaker: speaker, start: partStart + $0.start, end: partStart + $0.end, text: $0.text, segment: segment,
                      label: $0.speaker, pitch: $0.pitch)
        }
    }

    /// Both tracks merged into the order things were said, with echo of the call removed from your track.
    static func conversation(_ lines: [TrackLine]) -> [TrackLine] {
        EchoFilter.removeEcho(lines).sorted { $0.start == $1.start ? $0.speaker.rawValue < $1.speaker.rawValue : $0.start < $1.start }
    }
}

/// One line of a meeting transcript, with the speaker's display name.
struct MeetingLine: Equatable {
    let speaker: String
    let start: Double
    let text: String
    /// The part (and audio file) it came from.
    var segment: UUID? = nil

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

    static func instructions(language: NotesLanguage) -> String {
        """
        You are an expert meeting note-taker. You get a transcript made by speech recognition. "You" is the person \
        who recorded the meeting; "Others" (or a name) is everyone else on the call. People may speak English, Hindi \
        or a mix of both (Hinglish), in Devanagari or Roman letters. The transcript has recognition errors: work out \
        what was meant from context, and never copy an obviously misheard word into the notes. \
        Be accurate and specific: keep every decision, number, date, name, product and owner that was said, and \
        never invent any. The transcript is in the order things were said; use it to tell who answered what. \
        Only call someone by a name or role (such as "the manager") if the transcript says it; otherwise use "You" \
        or "Others". An owner of a task is whoever agreed to do it or was asked by name. Leave out small talk. \
        \(language.instruction)
        """
    }

    static let format = """
        Reply in exactly this format, with no other text:
        TITLE: a specific title naming what the meeting was about, at most 8 words
        SUMMARY: two or three sentences: the purpose of the meeting, the main outcomes and what happens next
        NOTES:
        ## A short topic heading
        - a key point, with the specifics (numbers, dates, names)
        (one heading per topic discussed, in the order discussed)
        ## Decisions
        - each decision that was made (leave this heading out if there were none)
        ACTION ITEMS:
        - Owner: the task, by when (if a deadline was said). Use "You" for the person who recorded.
        (include tasks people agreed to or were asked to do; write "- None" only if there were truly none)
        """

    static let partInstructions = """
        You take detailed notes on one part of a longer meeting. The transcript comes from speech recognition and may \
        be in English, Hindi or Hinglish with recognition errors; work out what was meant. List the topics, key \
        points, decisions, numbers, dates and tasks with owners as short bullet points, in English. Use only what \
        was said.
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
            } else if section == .notes, ["DECISIONS", "DECISIONS:"].contains(upper) {
                notes.append("## Decisions")
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
    /// True when most of `mine`'s words were said by others in overlapping parts. Words are compared by sound,
    /// so the same Hindi heard as Devanagari on one track and Roman letters on the other still matches.
    static func isEcho(_ mine: String, theirs: [String]) -> Bool {
        let words = soundKeys(mine)
        guard words.count >= 3 else { return false }
        let heard = theirs.reduce(into: Set<String>()) { $0.formUnion(soundKeys($1)) }
        let matched = words.filter { word in heard.contains(word) || heard.contains { sounded(word, like: $0) } }
        return Double(matched.count) / Double(words.count) >= 0.5
    }

    /// Near matches: the same word transliterated slightly differently ("hmpj"/"hmpg", "dsjn"/"djn").
    private static func sounded(_ a: String, like b: String) -> Bool {
        guard a.count >= 4, b.count >= 4, abs(a.count - b.count) <= 1 else { return false }
        return editDistance(Array(a), Array(b)) <= 1
    }

    private static func editDistance(_ a: [Character], _ b: [Character]) -> Int {
        var previous = Array(0...b.count)
        for (i, x) in a.enumerated() {
            var current = [i + 1]
            for (j, y) in b.enumerated() {
                current.append(min(previous[j + 1] + 1, current[j] + 1, previous[j] + (x == y ? 0 : 1)))
            }
            previous = current
        }
        return previous[b.count]
    }

    /// A rough sound key per word: Latin letters, no accents, no vowels, letters that transliteration swaps
    /// merged (g/j/z, c/k/q, w/v), no doubled letters ("नमस्ते" and "Namaste" both become "nmst").
    static func soundKeys(_ text: String) -> Set<String> {
        let latin = (text.applyingTransform(.toLatin, reverse: false) ?? text)
            .applyingTransform(.stripDiacritics, reverse: false)?.lowercased() ?? text.lowercased()
        return Set(latin.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).compactMap { word -> String? in
            var key = ""
            for raw in word where !"aeiouyh'".contains(raw) {
                let character: Character = switch raw {
                case "g", "z": "j"
                case "c", "q": "k"
                case "w": "v"
                default: raw
                }
                if key.last != character { key.append(character) }
            }
            return key.count >= 2 ? key : nil
        })
    }

    /// Drops your sentences that only repeat a sentence others said at the same time. Done per sentence, so your own
    /// words in the same part are kept.
    static func removeEcho(_ lines: [TrackLine]) -> [TrackLine] {
        let theirs = lines.filter { $0.speaker == .others }
        return lines.filter { line in
            guard line.speaker == .you else { return true }
            let overlapping = theirs.filter { overlaps(start: line.start, end: line.end, with: ($0.start, $0.end)) }
            guard !overlapping.isEmpty, coverage(of: line, by: overlapping) >= 0.5 else { return true }
            return !isEcho(line.text, theirs: overlapping.map(\.text))
        }
    }

    /// How much of a line's time others were speaking. An echo plays at the same moment; a reply comes after.
    static func coverage(of line: TrackLine, by others: [TrackLine]) -> Double {
        let length = line.end - line.start
        guard length > 0 else { return 1 }
        let covered = others.reduce(0.0) { total, other in
            total + max(0, min(line.end, other.end + 1) - max(line.start, other.start - 1))
        }
        return min(covered / length, 1)
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
        You answer questions about a meeting using its notes and transcript below. "You" is the person who recorded it. \
        The transcript comes from speech recognition and may mix English and Hindi (Hinglish) with recognition errors; \
        work out what was meant. Answer in the same language as the question (Hindi, Hinglish or English). Be specific \
        and brief, quote numbers, dates and names exactly, and say who said what when it matters. If the meeting \
        doesn't answer the question, say so plainly instead of guessing. Never give people names or roles the \
        transcript doesn't give them.
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

/// The language people speak in meetings, which steers transcription.
enum SpeechLanguage: String, CaseIterable, Identifiable {
    case auto, english, hindi, hinglish

    var id: String { rawValue }

    /// In India, meetings switch between Hindi and English mid-sentence. Whisper's detection picks one language per
    /// part and translates the other, so mixed speech is the better default there.
    static var forThisMac: SpeechLanguage { forRegion(Locale.current.region) }

    static func forRegion(_ region: Locale.Region?) -> SpeechLanguage {
        region == .india ? .hinglish : .auto
    }

    var title: String {
        switch self {
        case .auto: "Detect automatically"
        case .english: "English"
        case .hindi: "Hindi (हिन्दी)"
        case .hinglish: "Hinglish (Hindi and English mixed, in Roman letters)"
        }
    }

    /// The language code sent to Whisper. Mixed speech is left to detection, so English words aren't translated.
    var whisperLanguage: String? {
        switch self {
        case .english: "en"
        case .hindi: "hi"
        case .auto, .hinglish: nil
        }
    }

    /// An example in the wanted style. Whisper continues in the script and style of its prompt, which keeps
    /// Hinglish in Roman letters and Hindi in Devanagari.
    var stylePrompt: String? {
        switch self {
        case .hinglish: "Haan, toh aaj ki meeting mein hum landing page aur launch plan discuss karenge. Okay, next steps kya hain?"
        case .hindi: "नमस्ते, आज की मीटिंग में हम लॉन्च प्लान और अगले कदमों पर बात करेंगे।"
        case .auto, .english: nil
        }
    }

    /// Apple's recognizer hears one language at a time.
    var locale: Locale {
        switch self {
        case .hindi, .hinglish: Locale(identifier: "hi-IN")
        case .english: Locale.current.language.languageCode == .english ? Locale.current : Locale(identifier: "en-US")
        case .auto: Locale.current
        }
    }

    /// The prompt for one part: the style example, then the end of the transcript so far, within Whisper's limit.
    static func prompt(style: String?, context: String, limit: Int = 400) -> String? {
        let room = limit - (style.map { $0.count + 1 } ?? 0)
        let tail = room > 0 ? String(context.suffix(room)) : ""
        let trimmedTail = tail.count < context.count ? String(tail.drop { !$0.isWhitespace }).trimmed : tail.trimmed
        let parts = [style, trimmedTail.isEmpty ? nil : trimmedTail].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// The language meeting notes are written in.
enum NotesLanguage: String, CaseIterable, Identifiable {
    case english, meeting

    var id: String { rawValue }

    var title: String {
        switch self {
        case .english: "English"
        case .meeting: "The language of the meeting"
        }
    }

    var instruction: String {
        switch self {
        case .english: "Write everything in clear English, translating what was said in Hindi or any other language."
        case .meeting: "Write in the main language of the meeting (for Hinglish, in Roman letters)."
        }
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
