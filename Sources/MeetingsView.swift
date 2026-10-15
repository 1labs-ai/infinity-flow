import SwiftData
import SwiftUI

struct MeetingsView: View {
    @Environment(MeetingController.self) private var meetings
    private var _all = Query<Meeting, [Meeting]>(sort: \Meeting.createdAt, order: .reverse)
    private var all: [Meeting] { _all.wrappedValue }
    @State private var selected: UUID?
    @State private var search = ""
    @State private var pendingDelete: Meeting?

    private var filtered: [Meeting] {
        let query = search.trimmed
        guard !query.isEmpty else { return all }
        return all.filter { meeting in
            [meeting.title, meeting.summary ?? "", meeting.aiNotes ?? "", meeting.userNotes].contains { $0.localizedCaseInsensitiveContains(query) }
                || (meeting.segments ?? []).contains { $0.text.localizedCaseInsensitiveContains(query) }
        }
    }

    var body: some View {
        Group {
            if let selected, let meeting = all.first(where: { $0.uuid == selected }) {
                MeetingDetailView(meeting: meeting) { self.selected = nil }
                    .id(meeting.uuid)
            } else {
                list
            }
        }
        .confirmationDialog("Delete meeting?", isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { meeting in
            Button("Delete meeting", role: .destructive) { meetings.delete(meeting) }
        } message: { _ in
            Text("This will permanently delete the notes, transcript and audio. This can't be undone.")
        }
        .onAppear(perform: openRequested)
        .onChange(of: meetings.requestedMeeting) { openRequested() }
    }

    private var list: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader("Meetings", subtitle: "Transcripts, summaries and action items, made on this Mac.") {
                    SearchBox(text: $search, prompt: "Search your meetings")
                }
                StartMeetingCard()
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No meetings yet" : "No results",
                                           systemImage: search.isEmpty ? "person.2.wave.2" : "magnifyingglass",
                                           description: Text(search.isEmpty ? "Notes from your meetings will show up here." : "Nothing matches “\(search)”."))
                        .padding(.top, 40)
                }
                ForEach(DateSection.group(filtered, date: \.createdAt, now: .now), id: \.0) { section, items in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(section.title)
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.uuid) { index, meeting in
                                if index > 0 { Divider().overlay(Theme.border) }
                                MeetingRow(meeting: meeting) { selected = meeting.uuid }
                                    .contextMenu {
                                        Button("Copy as Markdown") { TextInserter.write(meetings.markdown(meeting)) }
                                        Button("Delete meeting", role: .destructive) { pendingDelete = meeting }
                                    }
                            }
                        }
                        .card(padding: 6)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .padding(.bottom, 40)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func openRequested() {
        guard let id = meetings.requestedMeeting else { return }
        meetings.requestedMeeting = nil
        selected = id
    }
}

private struct StartMeetingCard: View {
    @Environment(MeetingController.self) private var meetings

    var body: some View {
        HStack(spacing: 18) {
            ZStack {
                Circle().fill(meetings.isRecording ? Color.red.opacity(0.12) : Theme.accentSoft).frame(width: 52, height: 52)
                Image(systemName: meetings.isRecording ? "record.circle" : "person.2.wave.2.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(meetings.isRecording ? .red : Theme.accent)
                    .symbolEffect(.pulse, isActive: meetings.phase == .recording)
            }
            VStack(alignment: .leading, spacing: 4) {
                if meetings.isRecording, let meeting = meetings.current {
                    Text(meeting.title).font(Theme.display(22))
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(meetings.phase == .paused ? "Paused" : "Recording") · \(MeetingFormat.timestamp(meetings.clock.elapsed()))")
                            .font(.system(size: 13)).monospacedDigit().foregroundStyle(Theme.muted)
                    }
                } else {
                    Text("Take notes for your next call").font(Theme.display(22))
                    Text("Records your mic and your Mac's audio, transcribes as you talk, then writes a summary and action items. No bot joins the call.")
                        .font(.system(size: 13)).foregroundStyle(Theme.muted).fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 12)
            if meetings.isRecording, let meeting = meetings.current {
                // Open notes takes Start's place, so a double click never lands on Stop.
                Button("Stop") { meetings.stop() }.buttonStyle(InkButtonStyle(tint: .red))
                Button(meetings.phase == .paused ? "Resume" : "Pause") {
                    meetings.phase == .paused ? meetings.resume() : meetings.pause()
                }
                .buttonStyle(.inkSecondary)
                Button("Open notes") { meetings.open(meeting.uuid) }.buttonStyle(.ink)
            } else {
                Button("Start meeting notes") { meetings.start() }
                    .buttonStyle(.ink)
                    .disabled(meetings.phase != .idle)
            }
        }
        .card(padding: 22)
    }
}

private struct MeetingRow: View {
    @Environment(MeetingController.self) private var meetings
    let meeting: Meeting
    let open: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: open) {
            HStack(alignment: .top, spacing: 16) {
                Text(meeting.createdAt.formatted(date: .omitted, time: .shortened))
                    .font(.system(size: 12)).foregroundStyle(Theme.faint)
                    .frame(width: 64, alignment: .leading).padding(.top, 2)
                VStack(alignment: .leading, spacing: 4) {
                    Text(meeting.title).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(statusLine).font(.system(size: 13)).foregroundStyle(Theme.muted).lineLimit(2)
                    HStack(spacing: 6) {
                        if meeting.duration > 0 { Text(MeetingFormat.duration(meeting.duration)) }
                        if let app = meeting.appName { Text("·"); Text(app) }
                        let open = meeting.orderedActionItems.filter { !$0.done }.count
                        if open > 0 { Text("·"); Text("\(open) action item\(open == 1 ? "" : "s")") }
                    }
                    .font(.system(size: 11.5)).foregroundStyle(Theme.faint)
                }
                Spacer()
                Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)).foregroundStyle(Theme.faint)
                    .opacity(hovering ? 1 : 0).padding(.top, 4)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 12)
            .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Theme.cardHover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }

    private var statusLine: String {
        if meeting.uuid == meetings.current?.uuid { return "Recording…" }
        if meetings.writingNotes.contains(meeting.uuid) { return "Writing notes…" }
        if meeting.meetingStatus == .processing { return "Transcribing…" }
        return meeting.summary ?? meeting.notesError ?? "No summary yet"
    }
}

// MARK: - Detail

enum MeetingTab: String, CaseIterable, Identifiable {
    case summary = "Summary", transcript = "Transcript", notes = "My notes", ask = "Ask"
    var id: String { rawValue }
}

struct MeetingDetailView: View {
    @Environment(MeetingController.self) private var meetings
    @Bindable var meeting: Meeting
    let back: () -> Void
    @State private var tab: MeetingTab = .summary
    @State private var confirmDelete = false
    @State private var copied: String?

    private var isLive: Bool { meeting.uuid == meetings.current?.uuid }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Button(action: back) { Label("Meetings", systemImage: "chevron.left") }
                        .buttonStyle(.plain).font(.system(size: 13)).foregroundStyle(Theme.muted)
                    Spacer()
                    actions
                }
                TextField("Title", text: $meeting.title)
                    .textFieldStyle(.plain)
                    .font(Theme.display(32))
                Text(infoLine).font(.system(size: 13)).foregroundStyle(Theme.muted)
                MeetingBanners(meeting: meeting)
                UnderlineTabs(tabs: MeetingTab.allCases, selection: $tab).padding(.top, 6)
            }
            .padding(.horizontal, 40)
            .padding(.top, 40)
            Divider().overlay(Theme.border)
            Group {
                switch tab {
                case .summary: SummaryTab(meeting: meeting)
                case .transcript: TranscriptTab(meeting: meeting, live: isLive)
                case .notes: MyNotesTab(meeting: meeting)
                case .ask: AskTab(meeting: meeting)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .onAppear { if isLive { tab = .transcript } }
        .confirmationDialog("Delete meeting?", isPresented: $confirmDelete) {
            Button("Delete meeting", role: .destructive) {
                meetings.delete(meeting)
                back()
            }
        } message: {
            Text("This will permanently delete the notes, transcript and audio. This can't be undone.")
        }
        .onDisappear { AudioPlayback.shared.stop() }
    }

    private var infoLine: String {
        var parts = [meeting.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if meeting.duration > 0 { parts.append(MeetingFormat.duration(meeting.duration)) }
        if let app = meeting.appName { parts.append(app) }
        let members = meeting.members
        if !members.isEmpty { parts.append("with " + members.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    private var actions: some View {
        HStack(spacing: 8) {
            if isLive {
                Button(meetings.phase == .paused ? "Resume" : "Pause") {
                    meetings.phase == .paused ? meetings.resume() : meetings.pause()
                }
                .buttonStyle(.inkSecondary)
                Button("Stop") { meetings.stop() }.buttonStyle(InkButtonStyle(tint: .red))
            }
            Menu {
                Button("Copy as Markdown") { copy(meetings.markdown(meeting), "Copied") }
                Button("Copy summary") {
                    copy([meeting.summary, meeting.aiNotes].compactMap { $0 }.joined(separator: "\n\n"), "Copied")
                }
                .disabled(meeting.summary == nil && meeting.aiNotes == nil)
                Button("Copy transcript") { copy(MeetingFormat.transcript(meeting.transcriptLines), "Copied") }
                    .disabled(meeting.transcriptLines.isEmpty)
            } label: {
                Label(copied ?? "Copy", systemImage: copied == nil ? "doc.on.doc" : "checkmark")
            }
            .menuStyle(.borderlessButton)
            .fixedSize()
            Menu {
                Button("Write notes again") { Task { await meetings.writeNotes(meeting) } }
                    .disabled(isLive || meetings.writingNotes.contains(meeting.uuid))
                Button("Show audio in Finder") { NSWorkspace.shared.open(meeting.folder) }
                if isLive {
                    Button("Discard this meeting", role: .destructive) {
                        meetings.discardCurrent()
                        back()
                    }
                }
                Divider()
                Button("Delete meeting", role: .destructive) { confirmDelete = true }
                    .disabled(isLive)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .foregroundStyle(Theme.muted)
    }

    private func copy(_ text: String, _ message: String) {
        TextInserter.write(text)
        copied = message
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { copied = nil }
    }
}

/// Status and problems for a meeting: live, transcribing, writing notes, failed parts, missing system audio.
private struct MeetingBanners: View {
    @Environment(MeetingController.self) private var meetings
    let meeting: Meeting

    var body: some View {
        let failed = (meeting.segments ?? []).filter(\.isFailed).count
        let pending = (meeting.segments ?? []).filter(\.isPending).count
        VStack(alignment: .leading, spacing: 6) {
            if meeting.uuid == meetings.current?.uuid {
                Banner(symbol: "record.circle", tint: .red,
                       text: meetings.phase == .paused ? "Paused. Resume when you're ready." : "Taking notes. The transcript fills in as you talk.")
            } else if meetings.writingNotes.contains(meeting.uuid) {
                Banner(symbol: "sparkles", tint: .orange, text: "Writing your notes…", progress: true)
            } else if meeting.meetingStatus == .processing {
                Banner(symbol: "waveform", tint: .orange, text: "Transcribing \(pending) part\(pending == 1 ? "" : "s")…", progress: true)
            }
            if failed > 0 {
                Banner(symbol: "exclamationmark.triangle.fill", tint: .orange,
                       text: "\(failed) part\(failed == 1 ? "" : "s") couldn't be transcribed. The audio is saved.") {
                    Button("Retry") { meetings.retryFailed(meeting) }
                }
            }
            if let error = meeting.notesError, meeting.meetingStatus == .done {
                Banner(symbol: "info.circle.fill", tint: .secondary, text: error) {
                    Button("Try again") { Task { await meetings.writeNotes(meeting) } }
                }
            }
            if !meeting.heardOthers, meeting.meetingStatus == .done, meeting.duration > 60 {
                Banner(symbol: "speaker.slash.fill", tint: .secondary,
                       text: "No audio from other participants was captured. Allow Infinity Flow under System Audio Recording, then restart it.") {
                    Button("Open Settings") { Permissions.openSystemAudioSettings() }
                }
            }
        }
    }
}

private struct Banner<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let text: String
    var progress = false
    @ViewBuilder var accessory: () -> Accessory

    init(symbol: String, tint: Color, text: String, progress: Bool = false,
         @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }) {
        self.symbol = symbol
        self.tint = tint
        self.text = text
        self.progress = progress
        self.accessory = accessory
    }

    var body: some View {
        HStack(spacing: 8) {
            if progress { ProgressView().controlSize(.small) } else { Image(systemName: symbol).foregroundStyle(tint) }
            Text(text).font(.callout).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 8)
            accessory()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 10).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(Theme.border))
    }
}

// MARK: - Summary

private struct SummaryTab: View {
    @Environment(MeetingController.self) private var meetings
    let meeting: Meeting
    @State private var newItem = ""

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if let summary = meeting.summary {
                    Text(summary).font(Theme.display(20)).textSelection(.enabled)
                } else if meeting.uuid == meetings.current?.uuid {
                    Text("The summary is written when the meeting ends. Your own notes, in My notes, are used too.")
                        .foregroundStyle(.secondary)
                } else if meeting.notesError == nil {
                    Text("Summary will appear here.").foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    SectionLabel("Action items")
                    ForEach(meeting.orderedActionItems) { item in
                        ActionItemRow(item: item)
                    }
                    HStack {
                        Image(systemName: "plus").foregroundStyle(.secondary)
                        TextField("Add action item", text: $newItem)
                            .textFieldStyle(.plain)
                            .onSubmit {
                                meetings.addActionItem(newItem, to: meeting)
                                newItem = ""
                            }
                    }
                }

                if let notes = meeting.aiNotes {
                    VStack(alignment: .leading, spacing: 8) {
                        SectionLabel("Notes")
                        MarkdownText(markdown: notes)
                    }
                }
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 28)
            .frame(maxWidth: 840, alignment: .leading)
        }
    }
}

private struct ActionItemRow: View {
    @Environment(MeetingController.self) private var meetings
    @Bindable var item: MeetingActionItem
    @State private var hovering = false

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Toggle(isOn: $item.done) { EmptyView() }
                .toggleStyle(.checkbox)
            TextField("Action item", text: $item.text, axis: .vertical)
                .textFieldStyle(.plain)
                .strikethrough(item.done)
                .foregroundStyle(item.done ? .secondary : .primary)
            Button { meetings.delete(item) } label: { Image(systemName: "xmark.circle.fill") }
                .buttonStyle(.borderless)
                .foregroundStyle(.secondary)
                .opacity(hovering ? 1 : 0)
                .help("Delete action item")
        }
        .onHover { hovering = $0 }
    }
}

/// Renders the small Markdown subset the notes use: "#" headings, "-" bullets and inline styles.
struct MarkdownText: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(markdown.components(separatedBy: .newlines).enumerated()), id: \.offset) { _, line in
                row(line)
            }
        }
        .textSelection(.enabled)
    }

    @ViewBuilder
    private func row(_ line: String) -> some View {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        if trimmed.hasPrefix("#") {
            Text(inline(String(trimmed.drop { $0 == "#" }).trimmed)).font(.headline).padding(.top, 6)
        } else if trimmed.hasPrefix("- ") || trimmed.hasPrefix("* ") || trimmed.hasPrefix("• ") {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Text("•").foregroundStyle(.secondary)
                Text(inline(String(trimmed.dropFirst(2))))
            }
            .padding(.leading, line.prefix { $0 == " " }.count >= 2 ? 18 : 0)
        } else if !trimmed.isEmpty {
            Text(inline(trimmed))
        }
    }

    private func inline(_ text: String) -> AttributedString {
        (try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text)
    }
}

// MARK: - Transcript

private struct TranscriptTab: View {
    @Environment(MeetingController.self) private var meetings
    let meeting: Meeting
    let live: Bool
    /// The display name being renamed: You, a person on the call, or Others.
    @State private var renaming: String?
    @State private var newName = ""

    var body: some View {
        let turns = MeetingFormat.turns(meeting.transcriptLines)
        let waiting = meeting.orderedSegments.filter { !$0.isDone }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    if turns.isEmpty && waiting.isEmpty {
                        Text(live ? "Listening… The first lines appear after a few seconds of speech." : "No transcript yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(turns.enumerated()), id: \.offset) { index, turn in
                        TurnRow(meeting: meeting, turn: turn) { name in
                            newName = name
                            renaming = name
                        }
                        .id(index)
                    }
                    ForEach(waiting) { segment in
                        WaitingRow(meeting: meeting, segment: segment)
                    }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxWidth: 840, alignment: .leading)
            }
            .onChange(of: turns.count) {
                if live, turns.count > 0 { withAnimation { proxy.scrollTo(turns.count - 1, anchor: .bottom) } }
            }
        }
        .alert("Rename speaker", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if let renaming {
                    if renaming == meeting.name(of: .you) {
                        meeting.youName = newName.trimmed
                    } else if meeting.members.contains(renaming) {
                        meeting.rename(speaker: renaming, to: newName)
                    } else {
                        meeting.othersName = newName.trimmed
                    }
                }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text(renaming == meeting.name(of: .you) ? "The name used for your microphone." : "Everywhere this person speaks in the meeting.")
        }
    }
}

/// One speaker's turn: their consecutive sentences, with the time it started.
private struct TurnRow: View {
    let meeting: Meeting
    let turn: MeetingLine
    let rename: (String) -> Void
    @State private var hovering = false

    private var speaker: MeetingSpeaker { turn.speaker == meeting.name(of: .you) ? .you : .others }
    private var segment: MeetingSegment? { (meeting.segments ?? []).first { $0.uuid == turn.segment } }
    private var playback: AudioPlayback { .shared }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Menu(turn.speaker) {
                    Button("Rename speaker…") { rename(turn.speaker) }
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .fontWeight(.semibold)
                .foregroundStyle(speaker == .you ? Color.orange : SpeakerColor.color(for: turn.speaker))
                Text(MeetingFormat.timestamp(turn.start)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                if let segment, let url = segment.audioURL, FileManager.default.fileExists(atPath: url.path) {
                    let playing = playback.playingID == segment.uuid
                    Button { playback.toggle(id: segment.uuid, url: url) } label: {
                        Image(systemName: playing ? "stop.fill" : "play.fill").font(.caption)
                    }
                    .buttonStyle(.borderless)
                    .help(playing ? "Stop audio" : "Play this part")
                    .opacity(hovering || playing ? 1 : 0)
                }
            }
            Text(turn.text).textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
        }
        .onHover { hovering = $0 }
    }
}

/// A steady color per person on the call, so turns are easy to follow.
enum SpeakerColor {
    private static let palette: [Color] = [.blue, .green, .purple, .teal, .pink, .indigo, .mint, .cyan]

    static func color(for name: String) -> Color {
        palette[Int(name.unicodeScalars.reduce(UInt32(0)) { $0 &* 31 &+ $1.value } % UInt32(palette.count))]
    }
}

/// A part still being transcribed, or one that failed.
private struct WaitingRow: View {
    let meeting: Meeting
    let segment: MeetingSegment

    var body: some View {
        HStack(spacing: 8) {
            Text(meeting.name(of: segment.meetingSpeaker)).fontWeight(.semibold).foregroundStyle(.secondary)
            Text(MeetingFormat.timestamp(segment.start)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if segment.isFailed {
                Label("Couldn't transcribe: \(segment.errorMessage ?? "unknown error")", systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
            } else {
                Label("Transcribing…", systemImage: "waveform").foregroundStyle(.secondary)
            }
        }
    }
}

// MARK: - My notes

private struct MyNotesTab: View {
    @Bindable var meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Take your own notes here. They're added to the AI notes when the meeting ends.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
            TextEditor(text: $meeting.userNotes)
                .font(.body)
                .scrollContentBackground(.hidden)
                .font(.system(size: 14))
                .padding(14)
                .background(RoundedRectangle(cornerRadius: 12).fill(Theme.card))
                .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(Theme.border))
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
    }
}

// MARK: - Ask

private struct AskTab: View {
    @Environment(MeetingController.self) private var meetings
    let meeting: Meeting
    @State private var question = ""
    @State private var exchanges: [(question: String, answer: String)] = []
    @State private var asking = false

    private let suggestions = ["What were the action items?", "What did we decide?", "Summarize what Others said"]

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    if exchanges.isEmpty {
                        Text("Ask anything about this meeting.").font(Theme.display(22)).foregroundStyle(Theme.muted)
                        HStack {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { ask(suggestion) }.buttonStyle(.inkSecondary).disabled(asking)
                            }
                        }
                    }
                    ForEach(Array(exchanges.enumerated()), id: \.offset) { _, exchange in
                        VStack(alignment: .leading, spacing: 6) {
                            Text(exchange.question).fontWeight(.semibold)
                            MarkdownText(markdown: exchange.answer)
                        }
                    }
                    if asking { ProgressView().controlSize(.small) }
                }
                .padding(.horizontal, 40)
                .padding(.vertical, 28)
                .frame(maxWidth: 840, alignment: .leading)
            }
            Divider()
            HStack {
                TextField("Ask about this meeting", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { ask(question) }
                Button("Ask") { ask(question) }.buttonStyle(.ink).disabled(asking || question.trimmed.isEmpty)
            }
            .padding(.horizontal, 40)
            .padding(.vertical, 16)
        }
    }

    private func ask(_ text: String) {
        let text = text.trimmed
        guard !text.isEmpty, !asking else { return }
        question = ""
        asking = true
        Task {
            let answer: String
            do {
                answer = try await meetings.ask(text, about: meeting)
            } catch {
                answer = error.localizedDescription
            }
            exchanges.append((text, answer))
            asking = false
        }
    }
}
