import SwiftData
import SwiftUI

enum HubSection: String, CaseIterable, Identifiable {
    case home = "Home"
    case history = "History"
    case settings = "Settings"

    var id: String { rawValue }

    var icon: String {
        switch self {
        case .home: "house"
        case .history: "clock.arrow.circlepath"
        case .settings: "gearshape"
        }
    }
}

struct HubView: View {
    @State private var section: HubSection? = .home
    @AppStorage(SettingsKey.onboarded) private var onboarded = false

    var body: some View {
        NavigationSplitView {
            List(HubSection.allCases, selection: $section) { item in
                Label(item.rawValue, systemImage: item.icon).tag(item)
            }
            .navigationSplitViewColumnWidth(min: 170, ideal: 190)
        } detail: {
            switch section ?? .home {
            case .home: HomeView()
            case .history: HistoryView()
            case .settings: SettingsView()
            }
        }
        .sheet(isPresented: Binding(get: { !onboarded }, set: { if !$0 { onboarded = true } })) {
            OnboardingView { onboarded = true }
        }
    }
}

struct HomeView: View {
    @Environment(FlowController.self) private var controller
    @Query private var transcripts: [Transcript]
    @AppStorage(SettingsKey.hotkey) private var hotkey = Hotkey.fn.rawValue

    private var words: Int { transcripts.reduce(0) { $0 + TranscriptText.wordCount($1.text) } }
    private var minutes: Double { transcripts.reduce(0) { $0 + $1.duration } / 60 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 28) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Hold \((Hotkey(rawValue: hotkey) ?? .fn).title) and speak.")
                        .font(.system(size: 34, weight: .bold))
                    Text("Release to paste into any app. Double-tap for hands-free, and press again to finish.")
                        .font(.title3).foregroundStyle(.secondary)
                }
                HStack(spacing: 16) {
                    Stat(value: "\(words)", label: "Words dictated")
                    Stat(value: "\(transcripts.count)", label: "Dictations")
                    Stat(value: minutes < 1 ? "<1" : String(format: "%.0f", minutes), label: "Minutes spoken")
                }
                if !controller.accessibilityGranted || !Permissions.microphoneGranted {
                    SetupCard()
                }
            }
            .padding(40)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct Stat: View {
    let value: String
    let label: String

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value).font(.system(size: 30, weight: .bold)).monospacedDigit()
            Text(label).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(.quaternary.opacity(0.5)))
    }
}

private struct SetupCard: View {
    @AppStorage(SettingsKey.onboarded) private var onboarded = false

    var body: some View {
        HStack {
            Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
            Text("Finish setup so Infinity Flow can hear you and paste for you.")
            Spacer()
            Button("Finish Setup") { onboarded = false }
        }
        .padding(16)
        .background(RoundedRectangle(cornerRadius: 12).fill(Color.orange.opacity(0.12)))
    }
}

struct HistoryView: View {
    @Environment(\.modelContext) private var context
    @Query(sort: \Transcript.createdAt, order: .reverse) private var transcripts: [Transcript]
    @State private var search = ""
    @State private var pendingDelete: Transcript?

    private var filtered: [Transcript] {
        let query = search.trimmingCharacters(in: .whitespaces)
        return query.isEmpty ? transcripts : transcripts.filter { $0.text.localizedCaseInsensitiveContains(query) }
    }

    var body: some View {
        List {
            ForEach(DateSection.group(filtered, date: \.createdAt, now: .now), id: \.0) { section, items in
                Section(section.title) {
                    ForEach(items) { transcript in
                        TranscriptRow(transcript: transcript)
                            .contextMenu {
                                Button("Copy transcript") { copy(transcript.text) }
                                Button("Delete transcript", role: .destructive) { pendingDelete = transcript }
                            }
                    }
                }
            }
        }
        .overlay {
            if filtered.isEmpty {
                if search.isEmpty {
                    ContentUnavailableView("No dictations yet", systemImage: "waveform",
                        description: Text("Once you dictate across different apps, your entire dictation history will appear here."))
                } else {
                    ContentUnavailableView.search(text: search)
                }
            }
        }
        .confirmationDialog("Are you sure you want to delete this transcript?",
                            isPresented: Binding(get: { pendingDelete != nil }, set: { if !$0 { pendingDelete = nil } }),
                            presenting: pendingDelete) { transcript in
            Button("Yes, delete it", role: .destructive) { context.delete(transcript) }
        } message: { _ in
            Text("Once deleted it cannot be recovered.")
        }
        .searchable(text: $search, prompt: "Search past transcripts")
        .navigationTitle("History")
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}

private struct TranscriptRow: View {
    let transcript: Transcript

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(transcript.text).textSelection(.enabled)
            HStack(spacing: 8) {
                Text(transcript.createdAt.formatted(date: .omitted, time: .shortened))
                if let app = transcript.appName { Text("·"); Text(app) }
                Text("·")
                Text(transcript.engineTitle)
            }
            .font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }
}
