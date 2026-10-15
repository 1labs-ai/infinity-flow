import SwiftData
import SwiftUI

enum HubSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case history = "History"
    case meetings = "Meetings"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .meetings: "person.2.wave.2"
        case .settings: "gearshape"
        }
    }
}

struct HubView: View {
    @Environment(MeetingController.self) private var meetings
    @Environment(\.openWindow) private var openWindow
    @State private var section: HubSection = .home
    @AppStorage(SettingsKey.onboarded) private var onboarded = false

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(section: $section)
            Rectangle().fill(Theme.border).frame(width: 1)
            Group {
                switch section {
                case .home: HomeView(section: $section)
                case .history: HistoryView()
                case .meetings: MeetingsView()
                case .settings: SettingsView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Theme.page)
        }
        .ignoresSafeArea()
        .foregroundStyle(Theme.ink)
        .onAppear {
            AppWindows.openHub = { [openWindow] in openWindow(id: "hub") }
            if meetings.requestedMeeting != nil { section = .meetings }
        }
        .onChange(of: meetings.requestedMeeting) { if meetings.requestedMeeting != nil { section = .meetings } }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
        }
    }
}

private struct Sidebar: View {
    @Environment(MeetingController.self) private var meetings
    @Binding var section: HubSection

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "infinity")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(Theme.accent)
                Text("Infinity Flow").font(Theme.display(20, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.top, 44) // clear the window's traffic lights
            .padding(.bottom, 18)

            ForEach(HubSection.allCases) { item in
                SidebarItem(item: item, selected: section == item) { section = item }
            }
            Spacer()
            MeetingShortcut(section: $section)
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 14)
        .frame(width: 216)
        .frame(maxHeight: .infinity)
        .background(Theme.sidebar)
    }
}

private struct SidebarItem: View {
    let item: HubSection
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: item.icon).frame(width: 18)
                Text(item.rawValue)
                Spacer()
            }
            .font(.system(size: 13.5, weight: selected ? .semibold : .regular))
            .foregroundStyle(selected ? Theme.ink : Theme.muted)
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 9).fill(selected ? Theme.card : hovering ? Theme.cardHover : .clear))
            .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(selected ? Theme.border : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// Start meeting notes from anywhere in the hub; while recording, shows the timer and opens the meeting.
private struct MeetingShortcut: View {
    @Environment(MeetingController.self) private var meetings
    @Binding var section: HubSection

    var body: some View {
        if meetings.isRecording, let meeting = meetings.current {
            Button { meetings.open(meeting.uuid) } label: {
                HStack(spacing: 8) {
                    Circle().fill(meetings.phase == .paused ? Color.orange : Color.red).frame(width: 8, height: 8)
                    TimelineView(.periodic(from: .now, by: 1)) { _ in
                        Text(MeetingFormat.timestamp(meetings.clock.elapsed())).monospacedDigit()
                    }
                    Text(meetings.phase == .paused ? "Paused" : "Taking notes").foregroundStyle(Theme.muted)
                    Spacer()
                }
                .font(.system(size: 12.5, weight: .medium))
                .card(padding: 12)
            }
            .buttonStyle(.plain)
        } else {
            Button {
                meetings.start()
                section = .meetings
            } label: {
                Label("Start meeting notes", systemImage: "record.circle").frame(maxWidth: .infinity)
            }
            .buttonStyle(.ink)
            .disabled(meetings.phase != .idle)
        }
    }
}

// MARK: - Home

struct HomeView: View {
    @Environment(FlowController.self) private var controller
    @Environment(MeetingController.self) private var meetingController
    @Binding var section: HubSection
    private var _transcripts = Query<Transcript, [Transcript]>(sort: \Transcript.createdAt, order: .reverse)
    private var transcripts: [Transcript] { _transcripts.wrappedValue }
    private var _meetings = Query<Meeting, [Meeting]>(sort: \Meeting.createdAt, order: .reverse)
    private var meetings: [Meeting] { _meetings.wrappedValue }
    @AppStorage(SettingsKey.hotkey) private var hotkey = Hotkey.fn.rawValue

    init(section: Binding<HubSection>) { _section = section }

    private var words: Int { transcripts.reduce(0) { $0 + TranscriptText.wordCount($1.text) } }
    private var minutes: Double { transcripts.reduce(0) { $0 + $1.duration } / 60 }
    private var firstName: String { NSFullUserName().split(separator: " ").first.map(String.init) ?? "" }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 26) {
                PageHeader(firstName.isEmpty ? "Welcome back" : "Welcome back, \(firstName)",
                           subtitle: "Speak anywhere. Keep your words.")

                HStack(spacing: 12) {
                    StatPill(value: "\(words)", label: "words dictated", symbol: "text.word.spacing")
                    StatPill(value: "\(transcripts.count)", label: "dictations", symbol: "waveform")
                    StatPill(value: minutes < 1 ? "<1" : String(format: "%.0f", minutes), label: "minutes spoken", symbol: "clock")
                    StatPill(value: "\(meetings.count)", label: "meetings", symbol: "person.2")
                }

                if !controller.accessibilityGranted || !controller.inputMonitoringGranted || !Permissions.microphoneGranted {
                    SetupCard()
                }

                HStack(alignment: .top, spacing: 16) {
                    DictateCard(hotkey: (Hotkey(rawValue: hotkey) ?? .fn).title)
                    MeetingCard(latest: meetings.first, section: $section)
                }

                VStack(alignment: .leading, spacing: 10) {
                    SectionLabel("Recent")
                    if transcripts.isEmpty {
                        Text("Your dictations will appear here.").foregroundStyle(Theme.muted).card()
                    } else {
                        VStack(spacing: 0) {
                            ForEach(Array(transcripts.prefix(4).enumerated()), id: \.element.uuid) { index, transcript in
                                if index > 0 { Divider().overlay(Theme.border) }
                                HStack(alignment: .firstTextBaseline, spacing: 16) {
                                    Text(transcript.createdAt.formatted(date: .omitted, time: .shortened))
                                        .font(.system(size: 12)).foregroundStyle(Theme.faint).frame(width: 64, alignment: .leading)
                                    Text(transcript.isFailed ? "Couldn't transcribe" : transcript.text).lineLimit(2)
                                    Spacer()
                                }
                                .padding(.vertical, 10)
                            }
                        }
                        .card(padding: 16)
                    }
                }

                PrivacyReceipt(records: transcripts.map(\.usage) + meetings.map(\.privacyRecord)).card()
            }
            .padding(.horizontal, 40)
            .padding(.top, 44)
            .padding(.bottom, 40)
            .frame(maxWidth: 920, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }
}

private struct DictateCard: View {
    let hotkey: String

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 6) {
                Text("Hold").foregroundStyle(Theme.muted)
                Text(hotkey)
                    .font(.system(size: 13, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .background(RoundedRectangle(cornerRadius: 6).fill(Theme.accentSoft))
                    .foregroundStyle(Theme.accent)
                Text("and speak").foregroundStyle(Theme.muted)
            }
            .font(.system(size: 13))
            Text("Your words appear wherever you're typing.").font(Theme.display(22))
            Text("Release to paste. Double-tap for hands-free and press again to finish. ⌃⌘V pastes your last transcript.")
                .font(.system(size: 13)).foregroundStyle(Theme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
        .card(padding: 22)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct MeetingCard: View {
    @Environment(MeetingController.self) private var meetings
    let latest: Meeting?
    @Binding var section: HubSection

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("Meeting notes", systemImage: "person.2.wave.2").font(.system(size: 13)).foregroundStyle(Theme.muted)
            if meetings.isRecording {
                Text("Taking notes now").font(Theme.display(22))
                Button("Open live notes") { if let id = meetings.current?.uuid { meetings.open(id) } }.buttonStyle(.ink)
            } else {
                Text("Transcripts, summaries and action items for every call.").font(Theme.display(22))
                    .fixedSize(horizontal: false, vertical: true)
                HStack {
                    Button("Start meeting notes") {
                        meetings.start()
                        section = .meetings
                    }
                    .buttonStyle(.ink)
                    .disabled(meetings.phase != .idle)
                    if let latest {
                        Button("Last: \(latest.title)") { meetings.open(latest.uuid) }
                            .buttonStyle(.inkSecondary).lineLimit(1)
                    }
                }
            }
        }
        .card(padding: 22)
        .frame(maxHeight: .infinity, alignment: .top)
    }
}

private struct SetupCard: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(Theme.accent)
            Text("Finish setup so Infinity Flow can hear you and paste for you.")
            Spacer()
            Button("Finish setup") { onboarded = false }.buttonStyle(.ink)
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.accentSoft))
    }
}

// MARK: - History

struct HistoryView: View {
    @Environment(FlowController.self) private var controller
    private var _transcripts = Query<Transcript, [Transcript]>(sort: \Transcript.createdAt, order: .reverse)
    private var transcripts: [Transcript] { _transcripts.wrappedValue }
    @State private var search = ""
    @State private var pendingDelete: Transcript?

    private var filtered: [Transcript] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? transcripts : transcripts.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                PageHeader("History", subtitle: "Everything you've dictated, kept on this Mac.") {
                    SearchBox(text: $search, prompt: "Search past transcripts")
                }
                if filtered.isEmpty {
                    ContentUnavailableView(search.isEmpty ? "No dictations yet" : "No results",
                                           systemImage: search.isEmpty ? "waveform" : "magnifyingglass",
                                           description: Text(search.isEmpty
                                                ? "Once you dictate across different apps, your entire dictation history will appear here."
                                                : "Nothing matches “\(search)”."))
                        .padding(.top, 60)
                }
                ForEach(DateSection.group(filtered, date: \.createdAt, now: .now), id: \.0) { section, items in
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(section.title)
                        VStack(spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.uuid) { index, transcript in
                                if index > 0 { Divider().overlay(Theme.border) }
                                TranscriptRow(transcript: transcript, onDelete: { pendingDelete = transcript })
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
        .confirmationDialog("Are you sure you want to delete this transcript?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { transcript in
            Button("Yes, delete it", role: .destructive) { controller.delete(transcript) }
        } message: { _ in
            Text("The text and its recording will be deleted. Once deleted it cannot be recovered.")
        }
        .onDisappear { AudioPlayback.shared.stop() }
    }
}

private struct TranscriptRow: View {
    @Environment(FlowController.self) private var controller
    let transcript: Transcript
    let onDelete: () -> Void
    @State private var showOriginal = false
    @State private var retrying = false
    @State private var hovering = false

    private var playback: AudioPlayback { .shared }
    private var hasAudio: Bool { transcript.audioURL.map { FileManager.default.fileExists(atPath: $0.path) } ?? false }

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(transcript.createdAt.formatted(date: .omitted, time: .shortened))
                .font(.system(size: 12))
                .foregroundStyle(Theme.faint)
                .frame(width: 64, alignment: .leading)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 6) {
                if transcript.isFailed {
                    Label("Couldn't transcribe: \(transcript.errorMessage ?? "unknown error")", systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(Theme.accent)
                } else {
                    Text(showOriginal ? (transcript.rawText ?? transcript.text) : transcript.text)
                        .font(.system(size: 14))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
                HStack(spacing: 6) {
                    if let app = transcript.appName { Text(app); Text("·") }
                    Text(transcript.engineTitle)
                    if transcript.duration > 0 { Text("·"); Text(Duration.seconds(transcript.duration).formatted(.time(pattern: .minuteSecond))) }
                    if transcript.rawText != nil {
                        Button(showOriginal ? "Show cleaned" : "Show original") { showOriginal.toggle() }
                            .buttonStyle(.link)
                    }
                }
                .font(.system(size: 11.5)).foregroundStyle(Theme.faint)
            }
            Spacer(minLength: 8)
            HStack(spacing: 2) {
                if transcript.isFailed {
                    Button(retrying ? "Retrying…" : "Retry") { retry() }.buttonStyle(.inkSecondary).disabled(retrying || !hasAudio)
                }
                if hasAudio {
                    let playing = playback.playingID == transcript.uuid
                    rowButton(playing ? "stop.fill" : "play.fill", help: playing ? "Pause audio" : "Play audio") {
                        playback.toggle(transcript)
                    }
                }
                if !transcript.isFailed {
                    rowButton("doc.on.doc", help: "Copy transcript") { TextInserter.write(transcript.text) }
                }
                Menu {
                    if hasAudio, let url = transcript.audioURL {
                        Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
                        Button("Transcribe again") { retry() }
                        Button("Delete audio") { controller.deleteAudio(transcript) }
                        Divider()
                    }
                    Button("Delete transcript", role: .destructive, action: onDelete)
                } label: {
                    Image(systemName: "ellipsis")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("More")
            }
            .foregroundStyle(Theme.muted)
            .opacity(hovering || playback.playingID == transcript.uuid || transcript.isFailed ? 1 : 0)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 10).fill(hovering ? Theme.cardHover : .clear))
        .onHover { hovering = $0 }
    }

    private func rowButton(_ symbol: String, help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 26, height: 22)
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    private func retry() {
        retrying = true
        Task {
            await controller.retry(transcript)
            retrying = false
        }
    }
}
