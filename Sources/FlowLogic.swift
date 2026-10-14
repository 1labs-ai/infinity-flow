import Foundation

/// Push-to-talk with a hands-free lock, following the observed Wispr Flow semantics:
/// - Hold the key: recording starts on press and stops (and pastes) on release after at least `debounce`.
/// - Release sooner: keep listening for a second press within `debounce`; without one, the dictation is dismissed.
/// - Second press in that window: lock into hands-free. The next press stops and pastes,
///   unless it comes within `debounce` of locking (a quick triple tap), which dismisses.
struct HoldToTalk {
    enum Action: Equatable { case start, stop, cancel, lock, none }

    private enum Phase: Equatable {
        case idle
        case holding(since: Date)
        case awaitingSecondPress(releasedAt: Date)
        case locked(since: Date)
    }

    var debounce: TimeInterval = 0.5
    private var phase: Phase = .idle

    var isActive: Bool { phase != .idle }
    var isLocked: Bool { if case .locked = phase { true } else { false } }

    mutating func keyDown(at time: Date) -> Action {
        switch phase {
        case .idle:
            phase = .holding(since: time)
            return .start
        case .holding:
            return .none // key repeat
        case .awaitingSecondPress:
            phase = .locked(since: time)
            return .lock
        case .locked(let since):
            phase = .idle
            return time.timeIntervalSince(since) < debounce ? .cancel : .stop
        }
    }

    mutating func keyUp(at time: Date) -> Action {
        guard case .holding(let since) = phase else { return .none }
        if time.timeIntervalSince(since) >= debounce {
            phase = .idle
            return .stop
        }
        phase = .awaitingSecondPress(releasedAt: time)
        return .none
    }

    /// Call after `debounce` has elapsed since a short release; dismisses if no second press came.
    mutating func timeout(at time: Date) -> Action {
        guard case .awaitingSecondPress(let releasedAt) = phase, time.timeIntervalSince(releasedAt) >= debounce else { return .none }
        phase = .idle
        return .cancel
    }

    /// Esc, or an external stop such as the session limit.
    mutating func reset() {
        phase = .idle
    }
}

enum AudioLevel {
    static let floorDecibels: Float = -50

    /// Ten bars mirrored from the centre, taller in the middle, from the most recent levels (oldest first).
    static func bars(from levels: [Float], count: Int = 10) -> [Float] {
        let half = count / 2
        let recent = Array(levels.suffix(half))
        let padded = [Float](repeating: 0, count: half - recent.count) + recent
        // The newest level drives the centre; older levels ripple outward.
        let rightHalf = padded.reversed().enumerated().map { i, level in
            level * (1 - 0.12 * Float(i))
        }
        return Array(rightHalf.reversed()) + rightHalf
    }

    /// Maps an RMS amplitude to 0...1 on a decibel scale, so quiet speech still moves the waveform.
    static func normalized(rms: Float) -> Float {
        guard rms > 0 else { return 0 }
        let db = 20 * log10(rms)
        return min(max((db - floorDecibels) / -floorDecibels, 0), 1)
    }

    static func rms(_ samples: UnsafeBufferPointer<Float>) -> Float {
        guard !samples.isEmpty else { return 0 }
        var sum: Float = 0
        for s in samples { sum += s * s }
        return (sum / Float(samples.count)).squareRoot()
    }
}

enum TranscriptText {
    /// Trims and collapses whitespace; returns nil when nothing was said.
    static func clean(_ raw: String) -> String? {
        let collapsed = raw
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
        return collapsed.isEmpty ? nil : collapsed
    }

    static func wordCount(_ text: String) -> Int {
        text.split(whereSeparator: { $0.isWhitespace }).count
    }
}

/// multipart/form-data body for the OpenAI transcription endpoint.
struct MultipartBody {
    let boundary: String
    private(set) var data = Data()

    init(boundary: String = "InfinityFlow-\(UUID().uuidString)") {
        self.boundary = boundary
    }

    var contentType: String { "multipart/form-data; boundary=\(boundary)" }

    mutating func addField(_ name: String, _ value: String) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        append("\(value)\r\n")
    }

    mutating func addFile(_ name: String, filename: String, mimeType: String, contents: Data) {
        append("--\(boundary)\r\n")
        append("Content-Disposition: form-data; name=\"\(name)\"; filename=\"\(filename)\"\r\n")
        append("Content-Type: \(mimeType)\r\n\r\n")
        data.append(contents)
        append("\r\n")
    }

    func finalized() -> Data {
        var result = data
        result.append(Data("--\(boundary)--\r\n".utf8))
        return result
    }

    private mutating func append(_ string: String) {
        data.append(Data(string.utf8))
    }
}

enum DateSection: Hashable {
    case today, yesterday, previous7Days, previous30Days, older

    var title: String {
        switch self {
        case .today: "Today"
        case .yesterday: "Yesterday"
        case .previous7Days: "Previous 7 Days"
        case .previous30Days: "Previous 30 Days"
        case .older: "Older"
        }
    }

    static func section(for date: Date, now: Date, calendar: Calendar = .current) -> DateSection {
        let days = calendar.dateComponents([.day], from: calendar.startOfDay(for: date), to: calendar.startOfDay(for: now)).day ?? 0
        switch days {
        case ...0: return .today
        case 1: return .yesterday
        case 2...7: return .previous7Days
        case 8...30: return .previous30Days
        default: return .older
        }
    }

    /// Groups items already sorted newest-first, keeping that order.
    static func group<T>(_ items: [T], date: (T) -> Date, now: Date, calendar: Calendar = .current) -> [(DateSection, [T])] {
        var result: [(DateSection, [T])] = []
        for item in items {
            let section = section(for: date(item), now: now, calendar: calendar)
            if let last = result.indices.last, result[last].0 == section {
                result[last].1.append(item)
            } else {
                result.append((section, [item]))
            }
        }
        return result
    }
}
