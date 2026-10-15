import SwiftData
import SwiftUI

struct MeetingsView: View {
    @Environment(MeetingController.self) private var meetings
    private var _all = Query<Meeting, [Meeting]>(sort: \Meeting.createdAt, order: .reverse)
    private var all: [Meeting] { _all.wrappedValue }
    @State private var path: [UUID] = []
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
        NavigationStack(path: $path) {
            List {
                Section { StartMeetingCard() }
                ForEach(DateSection.group(filtered, date: \.createdAt, now: .now), id: \.0) { section, items in
                    Section(section.title) {
                        ForEach(items) { meeting in
                            NavigationLink(value: meeting.uuid) { MeetingRow(meeting: meeting) }
                                .contextMenu {
                                    Button("Copy as Markdown") { TextInserter.write(meetings.markdown(meeting)) }
                                    Button("Delete meeting", role: .destructive) { pendingDelete = meeting }
                                }
                        }
                    }
                }
            }
            .overlay {
                if filtered.isEmpty {
                    if search.isEmpty {
                        ContentUnavailableView("No meetings yet", systemImage: "person.2.wave.2",
                            description: Text("Notes from your meetings will show up here."))
                            .padding(.top, 160)
                    } else {
                        ContentUnavailableView.search(text: search)
                    }
                }
            }
            .searchable(text: $search, prompt: "Search your meetings")
            .navigationTitle("Meetings")
            .navigationDestination(for: UUID.self) { id in
                if let meeting = all.first(where: { $0.uuid == id }) {
                    MeetingDetailView(meeting: meeting)
                } else {
                    ContentUnavailableView("Meeting not found", systemImage: "questionmark.folder")
                }
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

    private func openRequested() {
        guard let id = meetings.requestedMeeting else { return }
        meetings.requestedMeeting = nil
        path = [id]
    }
}

private struct StartMeetingCard: View {
    @Environment(MeetingController.self) private var meetings

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: meetings.isRecording ? "record.circle" : "person.2.wave.2.fill")
                .font(.system(size: 28))
                .foregroundStyle(meetings.isRecording ? .red : .orange)
                .symbolEffect(.pulse, isActive: meetings.phase == .recording)
            VStack(alignment: .leading, spacing: 3) {
                if meetings.isRecording, let meeting = meetings.current {
                    Text(meeting.title).font(.headline)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text("\(meetings.phase == .paused ? "Paused" : "Recording") · \(MeetingFormat.timestamp(meetings.clock.elapsed()))")
                            .monospacedDigit().foregroundStyle(.secondary)
                    }
                } else {
                    Text("Take notes for your meetings").font(.headline)
                    Text("Records your mic and your Mac's audio, transcribes as you talk, then writes a summary and action items.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Spacer()
            if meetings.isRecording, let meeting = meetings.current {
                Button("Open notes") { meetings.open(meeting.uuid) }
                Button(meetings.phase == .paused ? "Resume" : "Pause") {
                    meetings.phase == .paused ? meetings.resume() : meetings.pause()
                }
                Button("Stop") { meetings.stop() }.keyboardShortcut(".", modifiers: .command)
            } else {
                Button("Start meeting notes") { meetings.start() }
                    .buttonStyle(.borderedProminent)
                    .disabled(meetings.phase != .idle)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct MeetingRow: View {
    @Environment(MeetingController.self) private var meetings
    let meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(meeting.title).fontWeight(.medium).lineLimit(1)
            HStack(spacing: 6) {
                Text(meeting.createdAt.formatted(date: .omitted, time: .shortened))
                if meeting.duration > 0 { Text("·"); Text(MeetingFormat.duration(meeting.duration)) }
                if let app = meeting.appName { Text("·"); Text(app) }
                let open = meeting.orderedActionItems.filter { !$0.done }.count
                if open > 0 { Text("·"); Label("\(open)", systemImage: "checklist").labelStyle(.titleAndIcon) }
            }
            .font(.caption).foregroundStyle(.secondary)
            Text(statusLine).font(.callout).foregroundStyle(.secondary).lineLimit(2)
        }
        .padding(.vertical, 3)
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
    @State private var tab: MeetingTab = .summary
    @State private var confirmDelete = false
    @State private var copied: String?

    private var isLive: Bool { meeting.uuid == meetings.current?.uuid }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 10) {
                TextField("Title", text: $meeting.title)
                    .textFieldStyle(.plain)
                    .font(.system(size: 26, weight: .bold))
                Text(infoLine).font(.callout).foregroundStyle(.secondary)
                MeetingBanners(meeting: meeting)
                Picker("", selection: $tab) {
                    ForEach(MeetingTab.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .frame(maxWidth: 420)
            }
            .padding([.horizontal, .top], 28)
            .padding(.bottom, 12)
            Divider()
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
        .navigationTitle(meeting.title)
        .toolbar { toolbar }
        .onAppear { if isLive { tab = .transcript } }
        .confirmationDialog("Delete meeting?", isPresented: $confirmDelete) {
            Button("Delete meeting", role: .destructive) { meetings.delete(meeting) }
        } message: {
            Text("This will permanently delete the notes, transcript and audio. This can't be undone.")
        }
        .onDisappear { AudioPlayback.shared.stop() }
    }

    private var infoLine: String {
        var parts = [meeting.createdAt.formatted(date: .abbreviated, time: .shortened)]
        if meeting.duration > 0 { parts.append(MeetingFormat.duration(meeting.duration)) }
        if let app = meeting.appName { parts.append(app) }
        if !meeting.attendees.isEmpty { parts.append("with " + meeting.attendees.joined(separator: ", ")) }
        return parts.joined(separator: " · ")
    }

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        ToolbarItemGroup {
            if isLive {
                Button(meetings.phase == .paused ? "Resume" : "Pause") {
                    meetings.phase == .paused ? meetings.resume() : meetings.pause()
                }
                Button("Stop") { meetings.stop() }
            }
            Menu {
                Button("Copy as Markdown") { copy(meetings.markdown(meeting), "Meeting copied") }
                Button("Copy summary") {
                    copy([meeting.summary, meeting.aiNotes].compactMap { $0 }.joined(separator: "\n\n"), "Summary copied")
                }
                .disabled(meeting.summary == nil && meeting.aiNotes == nil)
                Button("Copy transcript") { copy(MeetingFormat.transcript(meeting.transcriptLines), "Transcript copied") }
                    .disabled(meeting.transcriptLines.isEmpty)
            } label: {
                Label(copied ?? "Copy", systemImage: copied == nil ? "doc.on.doc" : "checkmark")
            }
            .help("Copy")
            Menu {
                Button("Write notes again") { Task { await meetings.writeNotes(meeting) } }
                    .disabled(isLive || meetings.writingNotes.contains(meeting.uuid))
                Button("Show audio in Finder") { NSWorkspace.shared.open(meeting.folder) }
                if isLive {
                    Button("Discard this meeting", role: .destructive) { meetings.discardCurrent() }
                }
                Divider()
                Button("Delete meeting", role: .destructive) { confirmDelete = true }
                    .disabled(isLive)
            } label: {
                Label("More", systemImage: "ellipsis.circle")
            }
        }
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
        .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.5)))
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
                    Text(summary).font(.title3).textSelection(.enabled)
                } else if meeting.uuid == meetings.current?.uuid {
                    Text("The summary is written when the meeting ends. Your own notes, in My notes, are used too.")
                        .foregroundStyle(.secondary)
                } else if meeting.notesError == nil {
                    Text("Summary will appear here.").foregroundStyle(.secondary)
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("Action items").font(.headline)
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
                        Text("Notes").font(.headline)
                        MarkdownText(markdown: notes)
                    }
                }
            }
            .padding(28)
            .frame(maxWidth: 760, alignment: .leading)
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
    @State private var renaming: MeetingSpeaker?
    @State private var newName = ""

    var body: some View {
        let segments = meeting.orderedSegments.filter { !$0.isDone || !$0.text.isEmpty }
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if segments.isEmpty {
                        Text(live ? "Listening… The first lines appear after a few seconds of speech." : "No transcript yet.")
                            .foregroundStyle(.secondary)
                    }
                    ForEach(Array(segments.enumerated()), id: \.element.uuid) { index, segment in
                        SegmentRow(meeting: meeting, segment: segment,
                                   showSpeaker: index == 0 || segments[index - 1].speaker != segment.speaker) { speaker in
                            newName = meeting.name(of: speaker)
                            renaming = speaker
                        }
                        .id(segment.uuid)
                    }
                }
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
            }
            .onChange(of: segments.count) {
                if live, let last = segments.last { withAnimation { proxy.scrollTo(last.uuid, anchor: .bottom) } }
            }
        }
        .alert("Rename speaker", isPresented: Binding(get: { renaming != nil }, set: { if !$0 { renaming = nil } })) {
            TextField("Name", text: $newName)
            Button("Rename") {
                if renaming == .you { meeting.youName = newName.trimmed } else { meeting.othersName = newName.trimmed }
                renaming = nil
            }
            Button("Cancel", role: .cancel) { renaming = nil }
        } message: {
            Text(renaming == .you ? "The name used for your microphone." : "The name used for everyone else on the call.")
        }
    }
}

private struct SegmentRow: View {
    @Environment(MeetingController.self) private var meetings
    let meeting: Meeting
    let segment: MeetingSegment
    let showSpeaker: Bool
    let rename: (MeetingSpeaker) -> Void
    @State private var hovering = false

    private var playback: AudioPlayback { .shared }
    private var hasAudio: Bool { segment.audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if showSpeaker {
                HStack(spacing: 8) {
                    Menu(meeting.name(of: segment.meetingSpeaker)) {
                        Button("Rename speaker…") { rename(segment.meetingSpeaker) }
                    }
                    .menuStyle(.borderlessButton)
                    .menuIndicator(.hidden)
                    .fixedSize()
                    .fontWeight(.semibold)
                    .foregroundStyle(segment.meetingSpeaker == .you ? Color.orange : Color.accentColor)
                    Text(MeetingFormat.timestamp(segment.start)).font(.caption).foregroundStyle(.secondary).monospacedDigit()
                }
            }
            HStack(alignment: .top, spacing: 8) {
                Group {
                    if segment.isFailed {
                        Label("Couldn't transcribe: \(segment.errorMessage ?? "unknown error")", systemImage: "exclamationmark.triangle.fill")
                            .foregroundStyle(.orange)
                    } else if segment.isPending {
                        Label("Transcribing…", systemImage: "waveform").foregroundStyle(.secondary)
                    } else {
                        Text(segment.text).textSelection(.enabled)
                    }
                }
                Spacer(minLength: 8)
                if hasAudio {
                    let playing = playback.playingID == segment.uuid
                    Button { playback.toggle(id: segment.uuid, url: segment.audioURL) } label: {
                        Image(systemName: playing ? "stop.fill" : "play.fill").frame(width: 22, height: 18)
                    }
                    .buttonStyle(.borderless)
                    .help(playing ? "Stop audio" : "Play this part")
                    .opacity(hovering || playing ? 1 : 0)
                }
            }
        }
        .onHover { hovering = $0 }
    }
}

// MARK: - My notes

private struct MyNotesTab: View {
    @Bindable var meeting: Meeting

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Take your own notes here. They're added to the AI notes when the meeting ends.")
                .font(.callout).foregroundStyle(.secondary)
            TextEditor(text: $meeting.userNotes)
                .font(.body)
                .scrollContentBackground(.hidden)
                .padding(8)
                .background(RoundedRectangle(cornerRadius: 10).fill(.quaternary.opacity(0.4)))
        }
        .padding(28)
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
                        Text("Ask anything about this meeting.").font(.title3).foregroundStyle(.secondary)
                        HStack {
                            ForEach(suggestions, id: \.self) { suggestion in
                                Button(suggestion) { ask(suggestion) }.disabled(asking)
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
                .padding(28)
                .frame(maxWidth: 760, alignment: .leading)
            }
            Divider()
            HStack {
                TextField("Ask about this meeting", text: $question)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { ask(question) }
                Button("Ask") { ask(question) }.disabled(asking || question.trimmed.isEmpty)
            }
            .padding(16)
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
