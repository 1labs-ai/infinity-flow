import AVFoundation
import XCTest
@testable import InfinityFlow

final class MeetingTests: XCTestCase {

    // MARK: - Chunking

    func testChunkEndsAtAPauseOnceLongEnough() {
        var policy = ChunkPolicy()
        for _ in 0..<50 { XCTAssertFalse(policy.add(seconds: 0.1, level: 0.8)) } // 5 s of speech
        for _ in 0..<10 { XCTAssertFalse(policy.add(seconds: 0.1, level: 0.05)) } // a pause before the minimum doesn't cut
        for _ in 0..<64 { XCTAssertFalse(policy.add(seconds: 0.1, level: 0.8)) }
        XCTAssertEqual(policy.length, 12.4, accuracy: 1e-6)
        XCTAssertFalse(policy.add(seconds: 0.3, level: 0.1))
        XCTAssertTrue(policy.add(seconds: 0.3, level: 0.1), "0.6 s pause after the minimum ends the chunk")
        XCTAssertTrue(policy.hasSpeech)
    }

    func testChunkNeverPassesTheMaximum() {
        var policy = ChunkPolicy()
        var cut = false
        var steps = 0
        while !cut {
            cut = policy.add(seconds: 0.1, level: 0.9)
            steps += 1
        }
        XCTAssertEqual(steps, 300, "continuous speech is cut at 30 s")
    }

    func testSilentChunkHasNoSpeech() {
        var policy = ChunkPolicy()
        for _ in 0..<200 { _ = policy.add(seconds: 0.1, level: 0.1) }
        XCTAssertFalse(policy.hasSpeech)
        policy.reset()
        XCTAssertEqual(policy.length, 0)
    }

    /// Feeds the real chunk writer synthetic audio and reads the WAV files it produced.
    func testTrackRecorderWritesChunksAtPauses() throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let clock = MeetingClock()
        clock.start()
        let recorder = TrackRecorder(speaker: .others, folder: folder, clock: clock)
        var chunks: [MeetingChunk] = []
        recorder.onChunk = { chunks.append($0) }

        let format = AVAudioFormat(standardFormatWithSampleRate: 48_000, channels: 2)!
        func buffer(amplitude: Float) -> AVAudioPCMBuffer {
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 4_800)!
            buffer.frameLength = 4_800
            for channel in 0..<2 {
                for i in 0..<4_800 { buffer.floatChannelData![channel][i] = amplitude * sin(Float(i) * 2 * .pi * 440 / 48_000) }
            }
            return buffer
        }
        for _ in 0..<130 { recorder.append(buffer(amplitude: 0.3)) } // 13 s of tone
        for _ in 0..<10 { recorder.append(buffer(amplitude: 0)) }    // 1 s of silence
        let finished = expectation(description: "finished")
        recorder.finish { finished.fulfill() }
        wait(for: [finished], timeout: 10)

        XCTAssertEqual(chunks.count, 2)
        let first = try XCTUnwrap(chunks.first)
        XCTAssertTrue(first.hasSpeech)
        XCTAssertEqual(first.speaker, .others)
        XCTAssertEqual(first.duration, 13.6, accuracy: 0.05)
        let file = try AVAudioFile(forReading: first.url)
        XCTAssertEqual(file.fileFormat.sampleRate, 16_000)
        XCTAssertEqual(file.fileFormat.channelCount, 1)
        XCTAssertEqual(Double(file.length) / 16_000, 13.6, accuracy: 0.05)
        XCTAssertFalse(chunks[1].hasSpeech, "the trailing silence isn't worth transcribing")
        XCTAssertEqual(chunks[1].url.lastPathComponent, "others-0002.wav")
        // Recovery after a crash re-reads chunk files and applies the same speech rule.
        XCTAssertTrue(try AVAudioFileInfo.hasSpeech(first.url))
        XCTAssertFalse(try AVAudioFileInfo.hasSpeech(chunks[1].url))
    }

    func testMonoMixAndChannelPick() {
        let format = AVAudioFormat(standardFormatWithSampleRate: 16_000, channels: 2)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 2)!
        buffer.frameLength = 2
        buffer.floatChannelData![0][0] = 1; buffer.floatChannelData![0][1] = 0.5
        buffer.floatChannelData![1][0] = 0; buffer.floatChannelData![1][1] = 0.5
        XCTAssertEqual(TrackRecorder.mono(buffer, channel: nil), [0.5, 0.5])
        XCTAssertEqual(TrackRecorder.mono(buffer, channel: 0), [1, 0.5])
        XCTAssertEqual(TrackRecorder.mono(buffer, channel: 5), [0, 0.5], "an out-of-range channel uses the last one")
    }

    func testClockSkipsPauses() {
        let clock = MeetingClock()
        let t0 = Date(timeIntervalSince1970: 1_000)
        clock.start(at: t0)
        clock.pause(at: t0 + 10)
        XCTAssertTrue(clock.isPaused)
        XCTAssertEqual(clock.elapsed(at: t0 + 100), 10, accuracy: 1e-9)
        clock.resume(at: t0 + 40)
        XCTAssertEqual(clock.elapsed(at: t0 + 45), 15, accuracy: 1e-9)
    }

    // MARK: - Formatting

    func testTimestampsAndDurations() {
        XCTAssertEqual(MeetingFormat.timestamp(0), "0:00")
        XCTAssertEqual(MeetingFormat.timestamp(245.9), "4:05")
        XCTAssertEqual(MeetingFormat.timestamp(3723), "1:02:03")
        XCTAssertEqual(MeetingFormat.duration(40), "40 s")
        XCTAssertEqual(MeetingFormat.duration(12 * 60 + 10), "12 min")
        XCTAssertEqual(MeetingFormat.duration(3600 + 5 * 60), "1 h 5 min")
        XCTAssertEqual(MeetingFormat.duration(7200), "2 h")
    }

    func testTurnsJoinTheSameSpeaker() {
        let lines = [
            MeetingLine(speaker: "You", start: 0, text: "Hi all."),
            MeetingLine(speaker: "You", start: 20, text: "Let's start."),
            MeetingLine(speaker: "Others", start: 31, text: "Sounds good."),
        ]
        XCTAssertEqual(MeetingFormat.transcript(lines), "[0:00] You: Hi all. Let's start.\n[0:31] Others: Sounds good.")
    }

    func testMarkdownExport() {
        var export = MeetingFormat.Export(title: "Launch sync", date: Date(timeIntervalSince1970: 0), duration: 1_800)
        export.attendees = ["Priya"]
        export.summary = "Agreed to ship on Friday."
        export.actionItems = [("Priya: update the changelog", false), ("Book the room", true)]
        export.aiNotes = "## Timeline\n- Ship Friday"
        export.userNotes = "Ask about pricing"
        export.lines = [MeetingLine(speaker: "Priya", start: 65, text: "Friday works.")]
        let markdown = MeetingFormat.markdown(export)
        XCTAssertTrue(markdown.hasPrefix("# Launch sync\n\n"))
        XCTAssertTrue(markdown.contains("30 min · with Priya"))
        XCTAssertTrue(markdown.contains("## Summary\n\nAgreed to ship on Friday."))
        XCTAssertTrue(markdown.contains("- [ ] Priya: update the changelog\n- [x] Book the room"))
        XCTAssertTrue(markdown.contains("## Notes\n\n### Timeline\n- Ship Friday"), "AI headings nest under Notes")
        XCTAssertTrue(markdown.contains("## My notes\n\nAsk about pricing"))
        XCTAssertTrue(markdown.contains("**Priya** (1:05): Friday works."))
    }

    // MARK: - Notes

    func testParsesNotesReply() {
        let reply = """
            TITLE: Q3 launch planning
            SUMMARY: The team agreed to ship on Friday.
            It needs one more review.
            NOTES:
            ## Timeline
            - Ship on Friday, 12 October
            ## Risks
            - Pricing page isn't ready
            ACTION ITEMS:
            - Priya: finish the pricing page
            - [ ] You: send the release notes
            2. Book the launch room
            - Team - meet again on Monday. - None
            """
        let notes = MeetingNotes.parse(reply)
        XCTAssertEqual(notes.title, "Q3 launch planning")
        XCTAssertEqual(notes.summary, "The team agreed to ship on Friday. It needs one more review.")
        XCTAssertEqual(notes.notes, "## Timeline\n- Ship on Friday, 12 October\n## Risks\n- Pricing page isn't ready")
        XCTAssertEqual(notes.actionItems, ["Priya: finish the pricing page", "You: send the release notes", "Book the launch room",
                                           "Team - meet again on Monday."])
    }

    func testBareDecisionsLabelBecomesAHeading() {
        let notes = MeetingNotes.parse("TITLE: Sync\nSUMMARY: Done.\nNOTES:\n## Plan\n- Ship\nDECISIONS\n- Ship Friday\nACTION ITEMS:\n- None")
        XCTAssertEqual(notes.notes, "## Plan\n- Ship\n## Decisions\n- Ship Friday")
    }

    func testMeetingLanguagePrompt() {
        XCTAssertNil(SpeechLanguage.prompt(style: nil, context: ""))
        XCTAssertEqual(SpeechLanguage.prompt(style: "Haan toh", context: "Priya will send it"), "Haan toh Priya will send it")
        let long = String(repeating: "word ", count: 200)
        let prompt = SpeechLanguage.prompt(style: "Style.", context: long, limit: 60)!
        XCTAssertLessThanOrEqual(prompt.count, 60)
        XCTAssertTrue(prompt.hasPrefix("Style. word"), "keeps whole words from the end of the context")
        XCTAssertEqual(SpeechLanguage.hinglish.whisperLanguage, nil, "mixed speech is detected, not forced")
        XCTAssertEqual(SpeechLanguage.hindi.whisperLanguage, "hi")
        XCTAssertEqual(SpeechLanguage.hindi.locale.language.languageCode?.identifier, "hi")
    }

    func testParsesBoldLabelsAndNoActionItems() {
        let notes = MeetingNotes.parse("**Title:** \"Weekly 1:1\"\n**Summary:** Caught up.\n**Action items:**\n- None.")
        XCTAssertEqual(notes.title, "Weekly 1:1")
        XCTAssertEqual(notes.summary, "Caught up.")
        XCTAssertEqual(notes.notes, "")
        XCTAssertEqual(notes.actionItems, [])
    }

    func testUnformattedReplyBecomesTheSummary() {
        let notes = MeetingNotes.parse("We talked about the roadmap.")
        XCTAssertNil(notes.title)
        XCTAssertEqual(notes.summary, "We talked about the roadmap.")
    }

    func testSplitKeepsLinesWhole() {
        let pieces = MeetingNotes.split(["aaaa", "bbbb", "cccc"], budget: 9)
        XCTAssertEqual(pieces, ["aaaa\nbbbb", "cccc"])
        XCTAssertEqual(MeetingNotes.split([String(repeating: "x", count: 20)], budget: 8), ["xxxxxxxx"], "an overlong line is cut")
        XCTAssertEqual(MeetingNotes.split([], budget: 8), [])
    }

    /// A long meeting is summarized part by part, then the parts' notes are combined in one final prompt.
    func testNotesWriterSummarizesLongMeetingsInParts() async throws {
        let model = RecordingModel(budget: 1_400)
        let lines = (0..<60).map { MeetingLine(speaker: $0 % 2 == 0 ? "You" : "Others", start: Double($0) * 10,
                                                  text: "Point number \($0) about the budget and the launch plan.") }
        let notes = try await MeetingNotesWriter(model: model).write(lines: lines, userNotes: "Remember pricing", attendees: [])
        XCTAssertGreaterThan(model.prompts.count, 2, "parts first, then the final notes")
        XCTAssertTrue(model.prompts.dropLast().allSatisfy { $0.instructions == MeetingNotes.partInstructions })
        let final = try XCTUnwrap(model.prompts.last)
        XCTAssertEqual(final.instructions, MeetingNotes.instructions(language: .english))
        XCTAssertTrue(final.prompt.contains("Remember pricing"))
        XCTAssertTrue(final.prompt.contains("Notes taken on each part"))
        XCTAssertTrue(model.prompts.allSatisfy { $0.prompt.count <= 1_400 + MeetingNotes.format.count })
        XCTAssertEqual(notes.title, "Budget review")
        XCTAssertEqual(notes.actionItems, ["Send the plan"])
    }

    func testNotesWriterUsesOnePromptForShortMeetings() async throws {
        let model = RecordingModel(budget: 7_000)
        _ = try await MeetingNotesWriter(model: model)
            .write(lines: [MeetingLine(speaker: "You", start: 0, text: "Quick sync.")], userNotes: "", attendees: ["Sam"])
        XCTAssertEqual(model.prompts.count, 1)
        XCTAssertTrue(model.prompts[0].prompt.hasPrefix("Attendees: Sam\n\nTranscript:\n\n[0:00] You: Quick sync."))
    }

    /// Real output from a test meeting: the mic heard the speakers, and Whisper wrote the English in Devanagari.
    func testEchoWrittenInAnotherScriptIsDetected() {
        let theirs = ["Good morning, let's review the Kindly Objects website launch.",
                      "मैंने homepage का design पूरा कर लिया है, बस mobile version बाकी है."]
        XCTAssertTrue(EchoFilter.isEcho("गुड मॉर्निंग, लेट्स रिव्यू दे कांडली आपचिक्ट्स वेबसाइड लाउंच", theirs: theirs))
        XCTAssertTrue(EchoFilter.isEcho("मैंने होमपेज का डिजाइन पूरा कर लिया है, बस मोबाइल वर्जन बागी है", theirs: theirs))
        XCTAssertFalse(EchoFilter.isEcho("I can share the Figma file with the developers after lunch", theirs: theirs))
    }

    /// Parts are split into timed sentences, so turns interleave in the order they were said, and echo is removed
    /// per sentence, keeping your own words from the same part.
    func testConversationOrderAndPerSentenceEcho() {
        let others = TrackLine.lines(speaker: .others, partStart: 0, partDuration: 30, text: "", timed: [
            TimedText(start: 0, end: 5, text: "Can you finish the mobile version by Thursday?"),
            TimedText(start: 12, end: 18, text: "Perfect, the budget for ads is one lakh rupees."),
        ])
        let mine = TrackLine.lines(speaker: .you, partStart: 4, partDuration: 20, text: "", timed: [
            TimedText(start: 0, end: 1.5, text: "Can you finish the mobile version by Thursday?"),
            TimedText(start: 2, end: 6, text: "Yes, I will have it ready by Thursday evening."),
        ])
        let conversation = TrackLine.conversation(others + mine)
        XCTAssertEqual(conversation.map(\.speaker), [.others, .you, .others])
        XCTAssertEqual(conversation[1].text, "Yes, I will have it ready by Thursday evening.")
        XCTAssertEqual(conversation[1].start, 6, accuracy: 1e-9)
    }

    func testPartsWithoutTimestampsAreOneLine() {
        let lines = TrackLine.lines(speaker: .you, partStart: 10, partDuration: 12, text: "Hello there", timed: nil)
        XCTAssertEqual(lines, [TrackLine(speaker: .you, start: 10, end: 22, text: "Hello there")])
        XCTAssertEqual(TrackLine.lines(speaker: .you, partStart: 0, partDuration: 5, text: "", timed: nil), [])
    }

    func testWhisperNonSpeechSentencesAreDropped() throws {
        let json = #"{"text":" Hello. Thank you.","segments":[{"start":0,"end":2,"text":" Hello.","no_speech_prob":0.01,"avg_logprob":-0.2},{"start":2,"end":4,"text":" Thank you.","no_speech_prob":0.9,"avg_logprob":-1.2}]}"#
        let response = try JSONDecoder().decode(CloudTranscriber.Response.self, from: Data(json.utf8))
        XCTAssertEqual(response.segments?.map(\.isLikelyNotSpeech), [false, true])
    }

    func testSpeakerLabelsAreParsed() {
        let reply = "1: Sarah\n**3: Priya**\n[4]: \"Rahul\".\n5: You\nnot a line\n6: Speaker 1"
        XCTAssertEqual(SpeakerAssignment.parse(reply), [1: "Sarah", 3: "Priya", 4: "Rahul", 6: "Speaker 1"])
    }

    /// Pitches measured in a real test meeting: Sarah's second turn was left as "Speaker 1".
    func testUnnamedSpeakerMergesIntoMatchingVoice() {
        let pitches = ["Sarah": [186.0], "Priya": [242.0, 246.0], "Rahul": [122.0, 124.0], "Speaker 1": [190.0]]
        XCTAssertEqual(SpeakerAssignment.mergeByVoice(pitches), ["Speaker 1": "Sarah"])
        XCTAssertEqual(SpeakerAssignment.mergeByVoice(["Amit": [120], "Ravi": [140], "Speaker 2": [130]]), [:],
                       "two named voices nearby: not sure enough to merge")
        XCTAssertTrue(SpeakerAssignment.isPlaceholder("Speaker 12"))
        XCTAssertFalse(SpeakerAssignment.isPlaceholder("Speakerphone"))
    }

    func testPitchOfASteadyVoice() {
        let rate = 16_000.0
        let samples = (0..<Int(rate)).map { Float(0.3 * sin(2 * Double.pi * 150 * Double($0) / rate)) }
        XCTAssertEqual(PitchEstimator.medianPitch(samples, sampleRate: rate) ?? 0, 150, accuracy: 4)
        XCTAssertNil(PitchEstimator.medianPitch([Float](repeating: 0, count: 16_000), sampleRate: rate), "silence has no pitch")
    }

    func testSpeakerWindowsCarryKnownVoices() {
        let lines = (1...6).map { SpeakerAssignment.Line(id: $0, isYou: $0 == 2, text: String(repeating: "x", count: 50), pitch: 150) }
        let windows = SpeakerAssignment.windows(lines, budget: 200)
        XCTAssertEqual(windows.map(\.count), [2, 2, 2])
        let prompt = SpeakerAssignment.prompt(windows[0], attendees: ["Rahul"], known: ["Sarah": 186])
        XCTAssertTrue(prompt.contains("Invited to the meeting: Rahul"))
        XCTAssertTrue(prompt.contains("Sarah (about 186 Hz)"))
        XCTAssertTrue(prompt.contains("1 (voice 150 Hz): "))
        XCTAssertTrue(prompt.contains("You: "))
    }

    func testIndiaDefaultsToHinglish() {
        XCTAssertEqual(SpeechLanguage.forRegion(.india), .hinglish)
        XCTAssertEqual(SpeechLanguage.forRegion(.unitedStates), .auto)
        XCTAssertEqual(SpeechLanguage.forRegion(nil), .auto)
    }

    func testEchoIsDetectedAcrossScripts() {
        // The same Hindi, heard from the speakers by the mic (Roman letters) and by the system audio tap (Devanagari).
        let mine = "Namaste team aaj Hum Naye page k bare Mein Baat karenge Rahul Somwar Ko website Par upload karenge"
        let theirs = ["नमस्ते टीम आज हम नए पेज कि बारे में एक बात करेंगे प्रिय टकरा करेंगे राहुल सोमवार को अपलोड करेंगे"]
        XCTAssertTrue(EchoFilter.isEcho(mine, theirs: theirs))
        XCTAssertFalse(EchoFilter.isEcho("Theek hai, main pricing page dekh leta hoon kal tak", theirs: theirs), "a reply isn't an echo")
        XCTAssertTrue(EchoFilter.soundKeys("नमस्ते").contains("nmst"))
        XCTAssertTrue(EchoFilter.soundKeys("Namaste").contains("nmst"))
    }

    func testEchoOfTheCallIsDetected() {
        let theirs = ["We should move the launch to Friday because the pricing page needs another review"]
        XCTAssertTrue(EchoFilter.isEcho("move the launch to Friday, pricing page needs review", theirs: theirs))
        XCTAssertFalse(EchoFilter.isEcho("Sounds good, I can take the pricing page", theirs: theirs), "a reply isn't an echo")
        XCTAssertFalse(EchoFilter.isEcho("Yes, Friday", theirs: theirs), "too short to judge")
        XCTAssertTrue(EchoFilter.overlaps(start: 10, end: 25, with: (24, 40)))
        XCTAssertFalse(EchoFilter.overlaps(start: 10, end: 25, with: (30, 40)))
    }

    // MARK: - Asking

    func testContextKeepsEverythingThatFits() {
        let lines = ["[0:00] You: hello", "[0:10] Others: hi"]
        XCTAssertEqual(MeetingContext.select(question: "anything", lines: lines, budget: 1_000), lines)
    }

    func testContextPicksRelevantLinesInOrder() {
        let lines = [
            "[0:00] You: Welcome everyone to the weekly meeting",
            "[0:10] Others: The marketing budget is forty thousand",
            "[0:20] You: Lunch is at noon today",
            "[0:30] Others: We should raise the budget for marketing next quarter",
        ]
        let picked = MeetingContext.select(question: "What did they say about the marketing budget?", lines: lines, budget: 130)
        XCTAssertEqual(picked, [lines[1], lines[3]])
    }

    // MARK: - Detection and calendar

    func testCallAppNames() {
        XCTAssertEqual(MeetingApps.name(bundleID: "us.zoom.xos"), "Zoom")
        XCTAssertEqual(MeetingApps.name(bundleID: "com.microsoft.teams2"), "Microsoft Teams")
        XCTAssertEqual(MeetingApps.name(bundleID: "com.google.Chrome.helper"), "Google Chrome")
        XCTAssertNil(MeetingApps.name(bundleID: "com.apple.VoiceMemos"))
    }

    func testCalendarPicksTheEventUnderWay() {
        let now = Date(timeIntervalSince1970: 100_000)
        let events = [
            CalendarCandidate(start: now - 3_600, end: now - 60),     // already over
            CalendarCandidate(start: now - 1_800, end: now + 1_800),  // under way, started 30 min ago
            CalendarCandidate(start: now + 120, end: now + 1_920),    // starts in 2 minutes
            CalendarCandidate(start: now + 3_000, end: now + 4_000),  // later
        ]
        XCTAssertEqual(CalendarCandidate.best(events, at: now), 2, "the closest start wins: people join a little early")
        XCTAssertEqual(CalendarCandidate.best(Array(events.prefix(2)), at: now), 1)
        XCTAssertNil(CalendarCandidate.best([events[0], events[3]], at: now))
    }

    func testSpeakerNames() {
        XCTAssertEqual(MeetingSpeaker.others.defaultName(attendees: ["Priya"]), "Priya")
        XCTAssertEqual(MeetingSpeaker.others.defaultName(attendees: ["Priya", "Sam"]), "Others")
        XCTAssertEqual(MeetingSpeaker.you.defaultName(attendees: ["Priya"]), "You")
    }
}

/// A language model that records its prompts and replies in the notes format.
private final class RecordingModel: LanguageModel, @unchecked Sendable {
    let promptBudget: Int
    private(set) var prompts: [(instructions: String, prompt: String)] = []

    init(budget: Int) { promptBudget = budget }

    func respond(instructions: String, prompt: String) async throws -> String {
        prompts.append((instructions, prompt))
        if instructions == MeetingNotes.partInstructions { return "- budget discussed\n- launch plan agreed" }
        return "TITLE: Budget review\nSUMMARY: Discussed the budget.\nNOTES:\n## Budget\n- Agreed\nACTION ITEMS:\n- Send the plan"
    }
}
