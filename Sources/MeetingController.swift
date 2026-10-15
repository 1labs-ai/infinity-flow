import AppKit
import AVFoundation
import EventKit
import Observation
import SwiftData

/// Takes notes for meetings: records your mic and your Mac's audio as two tracks, transcribes them in
/// short chunks while the meeting runs, then writes a summary, notes and action items.
///
/// Nothing is lost: each chunk is saved to disk before it is transcribed, failed chunks keep their audio for a
/// retry, and a meeting interrupted by a quit or crash is picked up and finished at the next launch.
@MainActor
@Observable
final class MeetingController {
    enum Phase: Equatable { case idle, recording, paused, finishing }

    private(set) var phase: Phase = .idle
    /// The meeting being recorded.
    private(set) var current: Meeting?
    private(set) var micLevel: Float = 0
    private(set) var othersLevel: Float = 0
    /// A call app that just started using the microphone, while no meeting is being recorded.
    private(set) var detectedApp: String?
    /// A short message for the recorder panel, such as why recording stopped.
    private(set) var notice: String?
    /// The meeting the notice is about, so the panel can open it.
    private(set) var noticeMeeting: UUID?
    /// Set to ask the hub window to show a meeting.
    var requestedMeeting: UUID?
    /// Meetings whose notes are being written.
    private(set) var writingNotes: Set<UUID> = []
    let clock = MeetingClock()
    let container: ModelContainer

    @ObservationIgnored private var microphone: MeetingMicrophone?
    @ObservationIgnored private var systemAudio: SystemAudioTap?
    @ObservationIgnored private var tracks: [TrackRecorder] = []
    @ObservationIgnored private var worker: Task<Void, Never>?
    @ObservationIgnored private var ticker: Timer?
    @ObservationIgnored private var panel: MeetingPanelController?
    @ObservationIgnored private var noticeTimer: DispatchWorkItem?
    /// The call app seen during the current meeting, used to stop when the call ends.
    @ObservationIgnored private var callApp: String?
    @ObservationIgnored private var callGoneSince: Date?
    @ObservationIgnored private var callSeenSince: Date?
    @ObservationIgnored private var offeredForCall = false
    @ObservationIgnored private var warnedAboutLength = false
    @ObservationIgnored private var warnedAboutAudio = false
    /// Why the recorder can't hear a track, shown in the panel and the meeting until it is fixed.
    private(set) var audioProblem: AudioProblem?

    enum AudioProblem: Equatable {
        /// The call track is perfectly silent while another app plays audio: System Audio Recording is off.
        case cantHearCall
        /// The mic track is perfectly silent: the input is muted, disconnected or blocked.
        case cantHearMic

        var message: String {
            switch self {
            case .cantHearCall: "Infinity Flow can't hear the call. Allow it under System Audio Recording, then start again."
            case .cantHearMic: "Your microphone is silent. Check that it isn't muted and is the selected input."
            }
        }
    }
    @ObservationIgnored private var observers: [NSObjectProtocol] = []

    /// A stop this soon after starting is taken as part of the click that started the meeting.
    static let stopGuard: TimeInterval = 2
    /// After a call app stops using the mic for this long, the call is over.
    static let callEndGrace: TimeInterval = 15
    /// A call app must use the mic this long before Infinity Flow offers to take notes.
    static let callStartDelay: TimeInterval = 3

    private var defaults: UserDefaults { .standard }
    private var context: ModelContext { container.mainContext }

    init(container: ModelContainer = Store.container) {
        self.container = container
        defaults.register(defaults: [
            SettingsKey.detectMeetings: true,
            SettingsKey.stopWhenCallEnds: true,
            SettingsKey.meetingEchoCancellation: true,
            SettingsKey.meetingLength: MeetingLength.threeHours.rawValue,
            SettingsKey.meetingCalendar: false,
            SettingsKey.meetingEngine: TranscriptionEngine.cloud.rawValue,
            SettingsKey.speechLanguage: SpeechLanguage.auto.rawValue,
            SettingsKey.notesLanguage: NotesLanguage.english.rawValue,
        ])
        panel = MeetingPanelController(meetings: self)
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stop(reason: "Notes stopped when your Mac went to sleep.") }
        })
        observers.append(NotificationCenter.default.addObserver(forName: NSApplication.willTerminateNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.stopForQuit() }
        })
        ticker = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        recover()
        applyRetention()
    }

    var isRecording: Bool { phase == .recording || phase == .paused }

    // MARK: - Recording

    /// Starts taking notes. `app` is the call app that was detected, if any.
    func start(app: String? = nil) {
        guard phase == .idle else { return }
        detectedApp = nil
        guard Permissions.microphoneGranted else {
            Task {
                if await Permissions.requestMicrophone() { start(app: app) } else {
                    show(notice: "Infinity Flow needs microphone access to take meeting notes.")
                }
            }
            return
        }
        let meeting = Meeting(title: app.map { "\($0) meeting" } ?? "Meeting")
        try? FileManager.default.createDirectory(at: meeting.folder, withIntermediateDirectories: true)
        if defaults.bool(forKey: SettingsKey.meetingCalendar), let event = MeetingCalendar.currentEvent() {
            meeting.title = event.title
            meeting.calendarTitle = event.title
            meeting.attendees = event.attendees
        }
        meeting.appName = app
        context.insert(meeting)
        try? context.save()

        clock.start()
        let id = meeting.uuid
        let mine = TrackRecorder(speaker: .you, folder: meeting.folder, clock: clock)
        let theirs = TrackRecorder(speaker: .others, folder: meeting.folder, clock: clock)
        for track in [mine, theirs] {
            track.onChunk = { chunk in
                DispatchQueue.main.async { MainActor.assumeIsolated { self.add(chunk, to: id) } }
            }
        }
        mine.onLevel = { level in DispatchQueue.main.async { MainActor.assumeIsolated { self.micLevel = level } } }
        theirs.onLevel = { level in DispatchQueue.main.async { MainActor.assumeIsolated { self.othersLevel = level } } }

        let microphone = MeetingMicrophone()
        microphone.onBuffer = { mine.append($0, channel: 0) }
        do {
            try microphone.start(echoCancellation: defaults.bool(forKey: SettingsKey.meetingEchoCancellation))
        } catch {
            context.delete(meeting)
            try? context.save()
            try? FileManager.default.removeItem(at: meeting.folder)
            show(notice: "Couldn't start the microphone: \(error.localizedDescription)")
            return
        }
        let systemAudio = SystemAudioTap()
        systemAudio.onBuffer = { theirs.append($0) }
        var warning: String?
        do {
            try systemAudio.start()
            self.systemAudio = systemAudio
        } catch {
            warning = "Only your microphone is being recorded. \(error.localizedDescription)"
        }

        self.microphone = microphone
        tracks = [mine, theirs]
        current = meeting
        callApp = app
        callGoneSince = nil
        warnedAboutLength = false
        warnedAboutAudio = false
        audioProblem = nil
        phase = .recording
        notice = nil
        if let warning { show(notice: warning, duration: 8) }
        panel?.show()
        play("Tink")
    }

    func pause() {
        guard phase == .recording else { return }
        clock.pause()
        tracks.forEach { $0.pause() }
        phase = .paused
    }

    func resume() {
        guard phase == .paused else { return }
        clock.resume()
        tracks.forEach { $0.resume() }
        phase = .recording
    }

    /// Stops recording, transcribes what's left and writes the notes. `reason` is shown when the stop wasn't yours.
    func stop(reason: String? = nil) {
        guard isRecording, let meeting = current else { return }
        // Start turns into Stop under the pointer; the end of the same click must not end the meeting.
        if reason == nil, clock.elapsed() < Self.stopGuard { return }
        phase = .finishing
        microphone?.stop()
        systemAudio?.stop()
        meeting.duration = clock.elapsed()
        meeting.endedAt = .now
        meeting.status = MeetingStatus.processing.rawValue
        try? context.save()
        play("Pop")

        let group = DispatchGroup()
        for track in tracks {
            group.enter()
            track.finish { group.leave() }
        }
        // Chunks are delivered to the main queue before `leave`, so they are all added by the time this runs.
        group.notify(queue: .main) {
            MainActor.assumeIsolated {
                self.microphone = nil
                self.systemAudio = nil
                self.tracks = []
                self.current = nil
                self.micLevel = 0
                self.othersLevel = 0
                self.phase = .idle
                self.show(notice: reason ?? "Meeting saved. Writing your notes…", meeting: meeting.uuid, duration: 6)
                self.finishIfReady(meeting)
                self.runQueue()
            }
        }
    }

    /// On quit, closes the chunk files so the next launch can transcribe them.
    private func stopForQuit() {
        guard isRecording, let meeting = current else { return }
        microphone?.stop()
        systemAudio?.stop()
        meeting.duration = clock.elapsed()
        meeting.endedAt = .now
        try? context.save()
        let done = DispatchSemaphore(value: 0)
        for track in tracks {
            track.onChunk = nil
            track.finish { done.signal() }
        }
        for _ in tracks { _ = done.wait(timeout: .now() + 2) }
    }

    /// Discards a meeting started by mistake, with its audio.
    func discardCurrent() {
        guard isRecording, let meeting = current else { return }
        microphone?.stop()
        systemAudio?.stop()
        for track in tracks { track.onChunk = nil; track.finish {} }
        microphone = nil
        systemAudio = nil
        tracks = []
        current = nil
        phase = .idle
        delete(meeting)
        panel?.hide()
    }

    private func add(_ chunk: MeetingChunk, to id: UUID) {
        guard let meeting = meeting(id) else {
            try? FileManager.default.removeItem(at: chunk.url)
            return
        }
        guard chunk.hasSpeech else {
            try? FileManager.default.removeItem(at: chunk.url)
            return
        }
        if chunk.speaker == .others { meeting.heardOthers = true }
        let segment = MeetingSegment(speaker: chunk.speaker, start: chunk.start, duration: chunk.duration,
                                     audioFileName: chunk.url.lastPathComponent)
        context.insert(segment)
        segment.meeting = meeting
        try? context.save()
        runQueue()
    }

    // MARK: - Transcription queue

    /// Transcribes pending chunks one at a time, oldest meeting first, in spoken order.
    private func runQueue() {
        guard worker == nil else { return }
        worker = Task {
            while let segment = nextPending() {
                await transcribe(segment)
            }
            worker = nil
            for meeting in allMeetings() where meeting.meetingStatus == .processing { finishIfReady(meeting) }
        }
    }

    private func nextPending() -> MeetingSegment? {
        allMeetings()
            .sorted { $0.createdAt < $1.createdAt }
            .lazy
            .compactMap { $0.orderedSegments.first(where: \.isPending) }
            .first
    }

    private func transcribe(_ segment: MeetingSegment) async {
        guard let url = segment.audioURL, FileManager.default.fileExists(atPath: url.path) else {
            segment.status = "failed"
            segment.errorMessage = "The audio for this part is no longer available."
            try? context.save()
            return
        }
        do {
            let heard = try await EngineSettings.transcribeMeeting(url, context: context(before: segment))
            segment.text = heard.text.isEmpty || EngineSettings.cleanupMode == .off ? heard.text : LightCleanup.clean(heard.text)
            segment.provider = heard.provider
            segment.status = "done"
            segment.errorMessage = nil
            if !defaults.bool(forKey: SettingsKey.keepRecordings) {
                try? FileManager.default.removeItem(at: url)
                segment.audioFileName = nil
            }
        } catch {
            segment.status = "failed"
            segment.errorMessage = error.localizedDescription
        }
        try? context.save()
    }

    /// The transcript just before a part, from the same speaker, to keep names and script consistent.
    private func context(before segment: MeetingSegment) -> String {
        let earlier = (segment.meeting?.orderedSegments ?? [])
            .filter { $0.isDone && $0.speaker == segment.speaker && $0.start < segment.start && !$0.text.isEmpty }
        return earlier.suffix(3).map(\.text).joined(separator: " ")
    }

    /// Writes notes once a stopped meeting has no chunks left to transcribe.
    private func finishIfReady(_ meeting: Meeting) {
        guard meeting.meetingStatus == .processing, meeting.uuid != current?.uuid,
              !(meeting.segments ?? []).contains(where: \.isPending) else { return }
        Task { await writeNotes(meeting) }
    }

    /// Transcribes failed parts again, then rewrites the notes.
    func retryFailed(_ meeting: Meeting) {
        for segment in meeting.segments ?? [] where segment.isFailed {
            segment.status = "pending"
            segment.errorMessage = nil
        }
        if meeting.meetingStatus == .done { meeting.status = MeetingStatus.processing.rawValue }
        try? context.save()
        runQueue()
    }

    // MARK: - Notes

    /// Writes (or rewrites) the summary, notes and action items with Apple Intelligence or your chat model.
    func writeNotes(_ meeting: Meeting) async {
        guard !writingNotes.contains(meeting.uuid) else { return }
        defer {
            meeting.status = MeetingStatus.done.rawValue
            try? context.save()
        }
        removeEcho(in: meeting)
        let lines = meeting.transcriptLines
        guard !lines.isEmpty || !meeting.userNotes.trimmed.isEmpty else {
            meeting.notesError = (meeting.segments ?? []).contains(where: \.isFailed)
                ? "Some parts couldn't be transcribed. Retry them to get notes."
                : "No speech was recorded in this meeting."
            return
        }
        guard let model = EngineSettings.meetingModel() else {
            meeting.notesError = Self.noModelMessage
            return
        }
        writingNotes.insert(meeting.uuid)
        defer { writingNotes.remove(meeting.uuid) }
        meeting.notesError = nil
        do {
            let notes = try await MeetingNotesWriter(model: model, language: notesLanguage)
                .write(lines: lines, userNotes: meeting.userNotes, attendees: meeting.attendees)
            if meeting.calendarTitle == nil, let title = notes.title { meeting.title = title }
            meeting.summary = notes.summary.isEmpty ? nil : notes.summary
            meeting.aiNotes = notes.notes.isEmpty ? nil : notes.notes
            replaceActionItems(of: meeting, with: notes.actionItems)
            if !NSApp.isActive { show(notice: "Your notes for “\(meeting.title)” are ready.", meeting: meeting.uuid, duration: 8) }
        } catch {
            meeting.notesError = "Couldn't write notes: \(error.localizedDescription)"
        }
    }

    /// Drops "You" parts that only repeat the call, heard through the speakers. The audio is kept.
    private func removeEcho(in meeting: Meeting) {
        let done = (meeting.segments ?? []).filter { $0.isDone && !$0.text.isEmpty }
        let theirs = done.filter { $0.meetingSpeaker == .others }
        for mine in done where mine.meetingSpeaker == .you {
            let overlapping = theirs.filter {
                EchoFilter.overlaps(start: mine.start, end: mine.start + mine.duration, with: ($0.start, $0.start + $0.duration))
            }
            if EchoFilter.isEcho(mine.text, theirs: overlapping.map(\.text)) { mine.text = "" }
        }
    }

    static let noModelMessage = "Add a cloud key in Settings to get a summary, action items and answers (Groq's free tier works), or use a Mac with Apple Intelligence."

    private var notesLanguage: NotesLanguage {
        NotesLanguage(rawValue: defaults.string(forKey: SettingsKey.notesLanguage) ?? "") ?? .english
    }

    /// Keeps finished items, and replaces the open ones with the new list.
    private func replaceActionItems(of meeting: Meeting, with items: [String]) {
        let existing = meeting.actionItems ?? []
        for item in existing where !item.done { context.delete(item) }
        let kept = existing.filter(\.done)
        let doneTexts = Set(kept.map { $0.text.lowercased() })
        var order = (kept.map(\.order).max() ?? -1) + 1
        for text in items where !doneTexts.contains(text.lowercased()) {
            let item = MeetingActionItem(text: text, order: order)
            order += 1
            context.insert(item)
            item.meeting = meeting
        }
    }

    func addActionItem(_ text: String, to meeting: Meeting) {
        let text = text.trimmed
        guard !text.isEmpty else { return }
        let item = MeetingActionItem(text: text, order: ((meeting.actionItems ?? []).map(\.order).max() ?? -1) + 1)
        context.insert(item)
        item.meeting = meeting
        try? context.save()
    }

    func delete(_ item: MeetingActionItem) {
        context.delete(item)
        try? context.save()
    }

    /// Answers a question about one meeting from its notes and transcript.
    func ask(_ question: String, about meeting: Meeting) async throws -> String {
        guard let model = EngineSettings.meetingModel(timeout: 120) else { throw FlowError.api(Self.noModelMessage) }
        var head = "Meeting: \(meeting.title), \(meeting.createdAt.formatted(date: .abbreviated, time: .shortened))\n"
        if !meeting.attendees.isEmpty { head += "Attendees: \(meeting.attendees.joined(separator: ", "))\n" }
        if let summary = meeting.summary { head += "Summary: \(summary)\n" }
        let items = meeting.orderedActionItems.map { "- \($0.text)\($0.done ? " (done)" : "")" }
        if !items.isEmpty { head += "Action items:\n\(items.joined(separator: "\n"))\n" }
        if !meeting.userNotes.trimmed.isEmpty { head += "My notes:\n\(meeting.userNotes.trimmed)\n" }
        head = String(head.prefix(model.promptBudget / 3))
        let budget = max(model.promptBudget - head.count - question.count - 200, 500)
        let transcript = MeetingContext.select(question: question, lines: MeetingFormat.turns(meeting.transcriptLines).map(\.formatted), budget: budget)
        let prompt = head + "\nTranscript:\n" + transcript.joined(separator: "\n") + "\n\nQuestion: \(question)"
        return try await model.respond(instructions: MeetingContext.instructions, prompt: prompt).trimmed
    }

    // MARK: - Managing meetings

    func delete(_ meeting: Meeting) {
        AudioPlayback.shared.stop()
        try? FileManager.default.removeItem(at: meeting.folder)
        context.delete(meeting)
        try? context.save()
    }

    func markdown(_ meeting: Meeting) -> String {
        MeetingFormat.markdown(.init(
            title: meeting.title, date: meeting.createdAt, duration: meeting.duration, attendees: meeting.attendees,
            summary: meeting.summary, actionItems: meeting.orderedActionItems.map { ($0.text, $0.done) },
            aiNotes: meeting.aiNotes, userNotes: meeting.userNotes, lines: meeting.transcriptLines))
    }

    /// Opens the hub on a meeting.
    func open(_ id: UUID) {
        requestedMeeting = id
        AppWindows.showHub()
    }

    func dismissDetection() {
        detectedApp = nil
        if phase == .idle, notice == nil { panel?.hide() }
    }

    func dismissNotice() {
        notice = nil
        noticeMeeting = nil
        if phase == .idle, detectedApp == nil { panel?.hide() }
    }

    /// Deletes meeting audio past the recordings retention period. Chunks still waiting or failed are kept.
    func applyRetention(now: Date = .now) {
        let retention = RecordingRetention(rawValue: defaults.integer(forKey: SettingsKey.recordingRetention)) ?? .forever
        for meeting in allMeetings() where meeting.meetingStatus == .done && retention.isExpired(meeting.createdAt, now: now) {
            for segment in meeting.segments ?? [] where segment.isDone && segment.audioFileName != nil {
                if let url = segment.audioURL { try? FileManager.default.removeItem(at: url) }
                segment.audioFileName = nil
            }
        }
        try? context.save()
    }

    // MARK: - Recovery

    /// Finishes meetings interrupted by a quit or crash: adds chunk files that were never queued,
    /// transcribes what's pending and writes the notes.
    private func recover() {
        for meeting in allMeetings() where meeting.meetingStatus != .done {
            let segments = meeting.segments ?? []
            let known = Set(segments.compactMap(\.audioFileName))
            let files = ((try? FileManager.default.contentsOfDirectory(at: meeting.folder, includingPropertiesForKeys: nil)) ?? [])
                .filter { $0.pathExtension == "wav" && !known.contains($0.lastPathComponent) }
                .sorted { $0.lastPathComponent < $1.lastPathComponent }
            for file in files {
                guard let speaker = MeetingSpeaker(rawValue: String(file.lastPathComponent.prefix { $0 != "-" })),
                      let audio = try? AVAudioFileInfo.duration(of: file), audio > 0.5,
                      (try? AVAudioFileInfo.hasSpeech(file)) == true else {
                    try? FileManager.default.removeItem(at: file)
                    continue
                }
                // The start time wasn't saved; place it after the speaker's previous chunk.
                let previous = (meeting.segments ?? []).filter { $0.meetingSpeaker == speaker }.map { $0.start + $0.duration }.max() ?? 0
                let segment = MeetingSegment(speaker: speaker, start: previous, duration: audio, audioFileName: file.lastPathComponent)
                context.insert(segment)
                segment.meeting = meeting
                if speaker == .others { meeting.heardOthers = true }
            }
            if meeting.meetingStatus == .recording {
                meeting.status = MeetingStatus.processing.rawValue
                let end = (meeting.segments ?? []).map { $0.start + $0.duration }.max() ?? 0
                meeting.duration = max(meeting.duration, end)
                meeting.endedAt = meeting.endedAt ?? meeting.createdAt.addingTimeInterval(meeting.duration)
            }
        }
        try? context.save()
        runQueue()
    }

    // MARK: - Call detection and limits

    private func tick() {
        let now = Date()
        let watching = isRecording ? (callApp == nil || defaults.bool(forKey: SettingsKey.stopWhenCallEnds))
                                   : phase == .idle && defaults.bool(forKey: SettingsKey.detectMeetings)
        let call = watching ? AudioObjects.appsUsingMicrophone().lazy.compactMap(MeetingApps.name(bundleID:)).first : nil

        switch phase {
        case .idle:
            guard defaults.bool(forKey: SettingsKey.detectMeetings), let call else {
                callSeenSince = nil
                offeredForCall = false
                if detectedApp != nil { dismissDetection() }
                return
            }
            let since = callSeenSince ?? now
            callSeenSince = since
            if !offeredForCall, now.timeIntervalSince(since) >= Self.callStartDelay {
                offeredForCall = true
                detectedApp = call
                panel?.show()
                DispatchQueue.main.asyncAfter(deadline: .now() + 30) { [weak self] in
                    if self?.detectedApp == call { self?.dismissDetection() }
                }
            }
        case .recording, .paused:
            offeredForCall = true // don't offer again for the call being recorded
            if let call {
                callApp = callApp ?? call
                callGoneSince = nil
            } else if callApp != nil, defaults.bool(forKey: SettingsKey.stopWhenCallEnds) {
                let since = callGoneSince ?? now
                callGoneSince = since
                if now.timeIntervalSince(since) >= Self.callEndGrace {
                    stop(reason: "The call ended, so Infinity Flow stopped taking notes.")
                    return
                }
            }
            checkAudio()
            let limit = (MeetingLength(rawValue: defaults.integer(forKey: SettingsKey.meetingLength)) ?? .threeHours)
            let elapsed = clock.elapsed()
            if elapsed >= limit.seconds {
                stop(reason: "Notes stopped at the \(limit.title) limit. You can change it in Settings › Meetings.")
            } else if elapsed >= limit.seconds - 60, !warnedAboutLength {
                warnedAboutLength = true
                show(notice: "Notes stop in 1 minute, at the \(limit.title) limit.", duration: 10)
            }
        case .finishing:
            break
        }
    }

    /// Notices a track that hears nothing at all, which means a muted device or a missing permission.
    private func checkAudio() {
        guard phase == .recording, tracks.count == 2 else { return }
        let problem: AudioProblem?
        if tracks[1].digitalSilence >= 6, AudioObjects.otherAppsPlayingAudio() {
            problem = .cantHearCall
        } else if tracks[0].digitalSilence >= 8 {
            problem = .cantHearMic
        } else {
            problem = nil
        }
        if problem != audioProblem {
            audioProblem = problem
            if let problem, !warnedAboutAudio {
                warnedAboutAudio = true
                show(notice: problem.message, duration: 12)
            }
        }
    }

    // MARK: - Helpers

    private func meeting(_ id: UUID) -> Meeting? {
        allMeetings().first { $0.uuid == id }
    }

    private func allMeetings() -> [Meeting] {
        (try? context.fetch(FetchDescriptor<Meeting>())) ?? []
    }

    private func show(notice message: String, meeting: UUID? = nil, duration: TimeInterval = 5) {
        notice = message
        noticeMeeting = meeting
        panel?.show()
        noticeTimer?.cancel()
        let timer = DispatchWorkItem { [weak self] in self?.dismissNotice() }
        noticeTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + duration, execute: timer)
    }

    private func play(_ name: String) {
        guard defaults.bool(forKey: SettingsKey.playSounds) else { return }
        NSSound(named: NSSound.Name(name))?.play()
    }
}

/// Writes meeting notes with a language model. Long meetings are summarized part by part first, so they fit
/// the model's window (Apple Intelligence's is small).
struct MeetingNotesWriter {
    let model: LanguageModel
    var language: NotesLanguage = .english

    func write(lines: [MeetingLine], userNotes: String, attendees: [String]) async throws -> MeetingNotes {
        var header = attendees.isEmpty ? "" : "Attendees: \(attendees.joined(separator: ", "))\n\n"
        if !userNotes.trimmed.isEmpty { header += "My own notes from the meeting:\n\(userNotes.trimmed)\n\n" }
        header = String(header.prefix(model.promptBudget / 4))
        let budget = max(model.promptBudget - header.count - MeetingNotes.format.count - 200, 1_000)

        var material = MeetingNotes.split(MeetingFormat.turns(lines).map(\.formatted), budget: budget)
        var label = "Transcript"
        while material.count > 1 {
            var partNotes: [String] = []
            for (index, part) in material.enumerated() {
                let reply = try await model.respond(instructions: MeetingNotes.partInstructions,
                                                    prompt: "Part \(index + 1) of \(material.count):\n\n\(part)")
                partNotes.append("Part \(index + 1):\n\(reply.trimmed)")
            }
            let next = MeetingNotes.split(partNotes.joined(separator: "\n").components(separatedBy: "\n"), budget: budget)
            // Part notes that don't shrink would loop forever; keep what fits.
            material = next.count < material.count ? next : [next.joined(separator: "\n").prefix(budget).description]
            label = "Notes taken on each part of the meeting, in order"
        }
        let body = material.first ?? ""
        let reply = try await model.respond(instructions: MeetingNotes.instructions(language: language),
                                            prompt: header + "\(label):\n\n\(body)\n\n\(MeetingNotes.format)")
        return MeetingNotes.parse(reply)
    }
}

/// Matches a meeting to the calendar event happening now, for its title and attendees. Off by default.
enum MeetingCalendar {
    static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }

    static func requestAccess() async -> Bool {
        (try? await EKEventStore().requestFullAccessToEvents()) ?? false
    }

    static func currentEvent(at date: Date = .now) -> (title: String, attendees: [String])? {
        guard authorized else { return nil }
        let store = EKEventStore()
        let predicate = store.predicateForEvents(withStart: date.addingTimeInterval(-4 * 3600), end: date.addingTimeInterval(3600), calendars: nil)
        let events = store.events(matching: predicate).filter { !$0.isAllDay }
        let candidates = events.map { CalendarCandidate(start: $0.startDate, end: $0.endDate) }
        guard let index = CalendarCandidate.best(candidates, at: date) else { return nil }
        let event = events[index]
        let attendees = (event.attendees ?? []).filter { !$0.isCurrentUser }.compactMap { $0.name?.trimmed }.filter { !$0.isEmpty }
        return ((event.title ?? "Meeting").trimmed, attendees)
    }
}

/// Picks the event a meeting starting at a given time belongs to.
struct CalendarCandidate: Equatable {
    let start: Date
    let end: Date

    /// The event under way (or starting within 10 minutes) whose start is closest to `date`.
    static func best(_ events: [CalendarCandidate], at date: Date) -> Int? {
        events.indices
            .filter { events[$0].start <= date.addingTimeInterval(600) && events[$0].end > date }
            .min { abs(events[$0].start.timeIntervalSince(date)) < abs(events[$1].start.timeIntervalSince(date)) }
    }
}

enum AVAudioFileInfo {
    static func duration(of url: URL) throws -> Double {
        let file = try AVAudioFile(forReading: url)
        return Double(file.length) / file.processingFormat.sampleRate
    }

    /// Whether a recovered chunk holds speech, using the same rule as live chunks. Silence sent to Whisper
    /// tends to come back as invented text.
    static func hasSpeech(_ url: URL) throws -> Bool {
        let file = try AVAudioFile(forReading: url)
        let window = AVAudioFrameCount(file.processingFormat.sampleRate / 10)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: window) else { return false }
        var policy = ChunkPolicy(minimum: .infinity, maximum: .infinity)
        while file.framePosition < file.length {
            try file.read(into: buffer, frameCount: window)
            guard let samples = buffer.floatChannelData?[0], buffer.frameLength > 0 else { break }
            let level = AudioLevel.normalized(rms: AudioLevel.rms(UnsafeBufferPointer(start: samples, count: Int(buffer.frameLength))))
            _ = policy.add(seconds: Double(buffer.frameLength) / file.processingFormat.sampleRate, level: level)
            if policy.hasSpeech { return true }
        }
        return false
    }
}

/// Opens the hub window from places outside SwiftUI scenes, such as the floating panels.
@MainActor
enum AppWindows {
    /// Captured from a SwiftUI view's `openWindow`, for when the hub window has been closed.
    static var openHub: (() -> Void)?

    static func showHub() {
        if let window = NSApp.windows.first(where: { $0.identifier?.rawValue.hasPrefix("hub") == true }) {
            window.makeKeyAndOrderFront(nil)
        } else {
            openHub?()
        }
        NSApp.activate()
    }
}
