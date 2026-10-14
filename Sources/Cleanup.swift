import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

enum CleanupMode: String, CaseIterable, Identifiable {
    case off, light, ai

    var id: String { rawValue }

    var title: String {
        switch self {
        case .off: "Off: exactly what you said"
        case .light: "Light: remove filler words (on this Mac)"
        case .ai: "AI polish: grammar and clarity"
        }
    }
}

/// Rule-based cleanup that runs on this Mac: drops filler sounds and accidental repeats,
/// and tidies spacing. It never rewrites words.
enum LightCleanup {
    private static let filler = try! NSRegularExpression(
        pattern: #"(?i)(?<![\w'])(?:u+m+|u+h+m*|e+r+m+|e+r+|a+h+|h+m+|m+h*m+)(?![\w'])[,.]?\s*"#)
    private static let repeated = try! NSRegularExpression(pattern: #"(?i)\b(\w+)(?:\s+\1\b)+"#)
    /// Doubled words that are often intentional ("had had", "that that").
    private static let allowedRepeats: Set<String> = ["had", "that", "is", "very", "so", "really", "no", "bye", "ha"]

    static func clean(_ text: String) -> String {
        var result = replace(filler, in: text, with: "")
        result = collapseRepeats(result)
        result = result
            .replacingOccurrences(of: #"\s+([,.!?;:])"#, with: "$1", options: .regularExpression)
            .replacingOccurrences(of: #"([,;:])(?=[^\s\d])"#, with: "$1 ", options: .regularExpression)
            .replacingOccurrences(of: #"\s{2,}"#, with: " ", options: .regularExpression)
            .replacingOccurrences(of: #"^[\s,.;:]+"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        return capitalizingSentences(result)
    }

    private static func collapseRepeats(_ text: String) -> String {
        let ns = text as NSString
        var result = text
        for match in repeated.matches(in: text, range: NSRange(location: 0, length: ns.length)).reversed() {
            let word = ns.substring(with: match.range(at: 1))
            guard !allowedRepeats.contains(word.lowercased()), let range = Range(match.range, in: result) else { continue }
            result.replaceSubrange(range, with: word)
        }
        return result
    }

    /// Capitalizes the first letter of the text and of each sentence.
    private static func capitalizingSentences(_ text: String) -> String {
        var output = ""
        var capitalizeNext = true
        for character in text {
            if capitalizeNext, character.isLetter {
                output += character.uppercased()
                capitalizeNext = false
            } else {
                output.append(character)
                if ".!?".contains(character) { capitalizeNext = true }
                else if !character.isWhitespace { capitalizeNext = false }
            }
        }
        return output
    }

    private static func replace(_ regex: NSRegularExpression, in text: String, with template: String) -> String {
        regex.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
    }
}

/// Rejects AI rewrites that lose numbers or change the length too much, so polish can't change what you meant.
enum CleanupGuard {
    private static let number = try! NSRegularExpression(pattern: #"\d+(?:[.,]\d+)*"#)

    static func numbers(in text: String) -> [String] {
        let ns = text as NSString
        return number.matches(in: text, range: NSRange(location: 0, length: ns.length)).map { ns.substring(with: $0.range) }
    }

    static func isSafe(original: String, cleaned: String) -> Bool {
        let trimmed = cleaned.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return false }
        let ratio = Double(trimmed.count) / Double(max(original.count, 1))
        guard ratio >= 0.4, ratio <= 1.6 else { return false }
        return numbers(in: original).allSatisfy { trimmed.contains($0) }
    }

    static let instructions = """
        You clean up dictated text. Remove filler words, false starts and accidental repeats, and fix grammar, \
        punctuation and capitalization. Keep the speaker's own words, tone and meaning. Never change numbers, \
        names, product names or technical terms, and never add new information. Reply with only the cleaned text.
        """
}

protocol TextCleaner {
    func clean(_ text: String) async throws -> String
}

#if canImport(FoundationModels)
/// Apple's on-device language model (Apple Intelligence). Text never leaves the Mac.
@available(macOS 26.0, *)
struct AppleIntelligenceCleaner: TextCleaner {
    static var isAvailable: Bool { SystemLanguageModel.default.availability == .available }

    func clean(_ text: String) async throws -> String {
        let session = LanguageModelSession(instructions: CleanupGuard.instructions)
        return try await session.respond(to: text).content
    }
}
#endif

/// Any OpenAI-compatible chat model, called with the user's own key.
struct CloudChatCleaner: TextCleaner {
    let baseURL: String
    let model: String
    let apiKey: String?
    var session: URLSession = .shared

    func clean(_ text: String) async throws -> String {
        guard let url = CloudPreset.endpoint(base: baseURL, path: "/chat/completions") else {
            throw FlowError.api("Set a server URL in Settings.")
        }
        struct Message: Codable { let role: String; let content: String }
        struct Request: Encodable { let model: String; let messages: [Message]; let temperature: Double }
        struct Response: Decodable { struct Choice: Decodable { let message: Message }; let choices: [Choice] }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        if let apiKey, !apiKey.isEmpty { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.timeoutInterval = 30
        request.httpBody = try JSONEncoder().encode(Request(
            model: model,
            messages: [Message(role: "system", content: CleanupGuard.instructions), Message(role: "user", content: text)],
            temperature: 0))
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else {
            throw FlowError.api("AI polish failed (HTTP \((response as? HTTPURLResponse)?.statusCode ?? 0)).")
        }
        return try JSONDecoder().decode(Response.self, from: data).choices.first?.message.content ?? ""
    }
}
