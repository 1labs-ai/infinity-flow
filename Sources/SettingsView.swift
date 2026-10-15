import SwiftData
import SwiftUI

struct SettingsView: View {
    @Environment(FlowController.self) private var controller
    @AppStorage(SettingsKey.hotkey) private var hotkey = Hotkey.fn.rawValue
    @AppStorage(SettingsKey.engine) private var engine = TranscriptionEngine.onDevice.rawValue
    @AppStorage(SettingsKey.cloudPreset) private var presetID = CloudPreset.groq.id
    @AppStorage(SettingsKey.customBaseURL) private var customBaseURL = ""
    @AppStorage(SettingsKey.customModel) private var customModel = ""
    @AppStorage(SettingsKey.cleanupMode) private var cleanupMode = CleanupMode.light.rawValue
    @AppStorage(SettingsKey.cleanupModel) private var cleanupModel = ""
    @AppStorage(SettingsKey.playSounds) private var playSounds = true
    @AppStorage(SettingsKey.restoreClipboard) private var restoreClipboard = true
    @AppStorage(SettingsKey.showInDock) private var showInDock = true
    private var _transcripts = Query<Transcript, [Transcript]>()
    private var transcripts: [Transcript] { _transcripts.wrappedValue }
    private var _meetings = Query<Meeting, [Meeting]>()
    private var meetings: [Meeting] { _meetings.wrappedValue }
    @State private var apiKey = ""
    @State private var testResult: String?
    @State private var testing = false

    private var preset: CloudPreset { CloudPreset.preset(id: presetID) }
    private var usesCloud: Bool { engine == TranscriptionEngine.cloud.rawValue }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            PageHeader("Settings", subtitle: "Dictation, meetings, engines and privacy.")
                .padding(.horizontal, 40)
                .padding(.top, 44)
            form
        }
    }

    private var form: some View {
        Form {
            Section("Dictation") {
                Picker("Hold to talk", selection: $hotkey) {
                    ForEach(Hotkey.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .onChange(of: hotkey) { controller.applySettings() }
                if hotkey == Hotkey.fn.rawValue {
                    HStack {
                        Text("Set System Settings › Keyboard › “Press 🌐 key to” to “Do Nothing”.")
                            .font(.callout).foregroundStyle(.secondary)
                        Spacer()
                        Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                    }
                }
                Toggle("Dictation and notification sounds", isOn: $playSounds)
                Toggle("Restore my clipboard after pasting", isOn: $restoreClipboard)
                Toggle("Show Infinity Flow in the Dock", isOn: $showInDock)
                    .onChange(of: showInDock) { DockIcon.apply() }
                Text("When off, Infinity Flow lives only in the menu bar (the waveform icon).")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section {
                Picker("Engine", selection: $engine) {
                    ForEach(TranscriptionEngine.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if usesCloud {
                    cloudSettings
                } else {
                    Text("Free and private. Speech is transcribed on this Mac whenever your language supports it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            } header: {
                Text("Transcription")
            } footer: {
                Text("No subscription and no account. In the cloud, audio goes straight to the provider you choose, with your key. Infinity Flow has no server.")
            }

            Section("Cleanup") {
                Picker("Cleanup", selection: $cleanupMode) {
                    ForEach(CleanupMode.allCases) { Text($0.title).tag($0.rawValue) }
                }
                .pickerStyle(.radioGroup)
                if cleanupMode == CleanupMode.ai.rawValue {
                    if EngineSettings.appleIntelligenceAvailable {
                        Label("Uses Apple Intelligence on this Mac. Text never leaves your Mac.", systemImage: "lock.shield")
                            .font(.callout).foregroundStyle(.secondary)
                    } else {
                        TextField("Chat model for your cloud key (e.g. a small, fast model)", text: $cleanupModel)
                        Text("Apple Intelligence isn't available on this Mac, so AI polish uses this model with your cloud provider and key. Leave it empty to use Light cleanup.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
                Text("Numbers, names and terms are protected: if a polish would drop a number or change too much, Infinity Flow keeps the Light version. The original is always in History.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            MeetingsSettingsSection()

            RecordingsSection()

            Section("Privacy") {
                PrivacyReceipt(records: transcripts.map(\.usage) + meetings.map(\.privacyRecord))
                Text("Infinity Flow never takes screenshots and never reads other apps' content. It only sees the name of the app you dictate into, for your History.")
                    .font(.callout).foregroundStyle(.secondary)
            }

            Section("Permissions") {
                PermissionRows()
            }
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
        .padding(.horizontal, 20)
        .frame(maxWidth: 880)
        .onAppear { apiKey = APIKeyStore.read(provider: presetID) ?? "" }
        .onChange(of: presetID) {
            apiKey = APIKeyStore.read(provider: presetID) ?? ""
            testResult = nil
        }
    }

    @ViewBuilder
    private var cloudSettings: some View {
        Picker("Provider", selection: $presetID) {
            ForEach(CloudPreset.all) { Text($0.title).tag($0.id) }
        }
        if preset == .custom {
            TextField("Server URL", text: $customBaseURL, prompt: Text("http://localhost:1234/v1"))
            TextField("Model", text: $customModel, prompt: Text("whisper-1"))
        } else {
            LabeledContent("Model", value: preset.model)
        }
        HStack {
            SecureField(preset.requiresKey ? "API key" : "API key (optional)", text: $apiKey)
                .onChange(of: apiKey) {
                    APIKeyStore.save(apiKey, provider: presetID)
                    testResult = nil
                }
            Button(testing ? "Testing…" : "Test") { Task { await test() } }
                .disabled(testing)
        }
        if let testResult {
            Text(testResult).font(.callout).foregroundStyle(testResult == "Connected" ? .green : .orange)
        }
        HStack {
            Text(preset.note).font(.callout).foregroundStyle(.secondary)
            Spacer()
            if let page = preset.keyPage { Link("Get a key", destination: page) }
        }
        CostMeter(records: transcripts.map(\.usage) + meetings.flatMap(\.usage), preset: preset)
    }

    private func test() async {
        testing = true
        let base = preset == .custom ? customBaseURL : preset.baseURL
        switch await CloudTranscriber.testConnection(baseURL: base, apiKey: apiKey) {
        case .success(let message): testResult = message
        case .failure(let error): testResult = error.localizedDescription
        }
        testing = false
    }
}

private struct MeetingsSettingsSection: View {
    @AppStorage(SettingsKey.detectMeetings) private var detectMeetings = true
    @AppStorage(SettingsKey.stopWhenCallEnds) private var stopWhenCallEnds = true
    @AppStorage(SettingsKey.meetingEchoCancellation) private var echoCancellation = true
    @AppStorage(SettingsKey.meetingLength) private var length = MeetingLength.threeHours.rawValue
    @AppStorage(SettingsKey.meetingCalendar) private var useCalendar = false
    @AppStorage(SettingsKey.cleanupModel) private var chatModel = ""
    @State private var calendarDenied = false
    @State private var usage = MeetingStore.usage()

    var body: some View {
        Section {
            Toggle("Offer to take notes when a call starts", isOn: $detectMeetings)
            Text("Infinity Flow notices when Zoom, Teams, Meet in your browser, FaceTime, Slack or another call app starts using your microphone. It never reads what's on your screen.")
                .font(.callout).foregroundStyle(.secondary)
            Toggle("Stop taking notes when the call ends", isOn: $stopWhenCallEnds)
            Toggle("Cancel echo from your speakers", isOn: $echoCancellation)
            Text("Keeps other people's voices, playing through your speakers, out of your own track. Not needed with headphones.")
                .font(.callout).foregroundStyle(.secondary)
            Picker("Stop recording after", selection: $length) {
                ForEach(MeetingLength.allCases) { Text($0.title).tag($0.rawValue) }
            }
            Toggle("Name meetings from my calendar", isOn: $useCalendar)
                .onChange(of: useCalendar) {
                    guard useCalendar, !MeetingCalendar.authorized else { return }
                    Task {
                        let granted = await MeetingCalendar.requestAccess()
                        calendarDenied = !granted
                        if !granted { useCalendar = false }
                    }
                }
            if calendarDenied {
                Text("Calendar access was denied. Allow it in System Settings › Privacy & Security › Calendars.")
                    .font(.callout).foregroundStyle(.orange)
            }
            notesModel
            HStack {
                VStack(alignment: .leading) {
                    Text("Hear other participants").fontWeight(.medium)
                    Text("Allow Infinity Flow under System Audio Recording so your notes include everyone on the call. macOS asks the first time you take notes.")
                        .font(.callout).foregroundStyle(.secondary)
                }
                Spacer()
                Button("Open Settings") { Permissions.openSystemAudioSettings() }
            }
            LabeledContent("Meeting audio on this Mac") {
                Text("\(usage.count) parts · \(ByteCountFormatter.string(fromByteCount: usage.bytes, countStyle: .file))")
            }
            Button("Open Meetings Folder") { NSWorkspace.shared.open(MeetingStore.folder) }
        } header: {
            Text("Meetings")
        } footer: {
            Text("Meetings are transcribed with the engine above, in short parts while you talk. Meeting audio follows the recordings settings below.")
        }
        .onAppear { usage = MeetingStore.usage() }
    }

    @ViewBuilder
    private var notesModel: some View {
        if EngineSettings.appleIntelligenceAvailable {
            Label("Summaries and answers use Apple Intelligence on this Mac. Text never leaves your Mac.", systemImage: "lock.shield")
                .font(.callout).foregroundStyle(.secondary)
        } else {
            TextField("Chat model for summaries (with your cloud key)", text: $chatModel, prompt: Text("e.g. llama-3.3-70b-versatile or gpt-4o-mini"))
            Text(chatModel.trimmed.isEmpty
                 ? "Apple Intelligence isn't available on this Mac. Add a chat model to get summaries, action items and answers; you'll still get a transcript without one."
                 : "The meeting transcript is sent to \(EngineSettings.preset.title) with your key to write notes. The same model is used for AI polish.")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

private struct RecordingsSection: View {
    @Environment(FlowController.self) private var controller
    @Environment(MeetingController.self) private var meetings
    @AppStorage(SettingsKey.keepRecordings) private var keepRecordings = true
    @AppStorage(SettingsKey.recordingRetention) private var retention = RecordingRetention.forever.rawValue
    @State private var usage = Store.recordingsUsage()
    @State private var confirmDeleteAll = false

    var body: some View {
        Section {
            Toggle("Save recordings of my dictations", isOn: $keepRecordings)
            Picker("Keep recordings", selection: $retention) {
                ForEach(RecordingRetention.allCases) { Text($0.title).tag($0.rawValue) }
            }
            .disabled(!keepRecordings)
            .onChange(of: retention) {
                controller.applyRecordingRetention()
                meetings.applyRetention()
                usage = Store.recordingsUsage()
            }
            LabeledContent("On this Mac") {
                Text("\(usage.count) recordings · \(ByteCountFormatter.string(fromByteCount: usage.bytes, countStyle: .file))")
            }
            HStack {
                Button("Open Recordings Folder") { NSWorkspace.shared.open(Store.recordingsFolder) }
                Spacer()
                Button("Delete All Recordings…", role: .destructive) { confirmDeleteAll = true }
                    .disabled(usage.count == 0)
            }
        } header: {
            Text("Recordings")
        } footer: {
            Text("Recordings are 16 kHz WAV files stored only on this Mac. Play them from History. Recordings of failed dictations are kept so you can retry.")
        }
        .onAppear { usage = Store.recordingsUsage() }
        .confirmationDialog("Delete all recordings?", isPresented: $confirmDeleteAll) {
            Button("Delete All Recordings", role: .destructive) {
                controller.deleteAllRecordings()
                usage = Store.recordingsUsage()
            }
        } message: {
            Text("Your transcripts stay in History. This can't be undone.")
        }
    }
}

private struct CostMeter: View {
    let records: [UsageRecord]
    let preset: CloudPreset

    var body: some View {
        let month = Usage.thisMonth(records, now: .now).filter { $0.provider == preset.id }
        let minutes = month.reduce(0) { $0 + $1.duration } / 60
        LabeledContent("This month") {
            if let cost = Usage.estimatedCost(month, preset: preset) {
                Text("\(String(format: "%.1f", minutes)) min of audio · about \(Usage.formatCost(cost))")
            } else {
                Text("\(String(format: "%.1f", minutes)) min of audio")
            }
        }
    }
}

struct PrivacyReceipt: View {
    let records: [UsageRecord]

    var body: some View {
        let summary = PrivacySummary(Usage.thisMonth(records, now: .now))
        VStack(alignment: .leading, spacing: 6) {
            Label(summary.headline, systemImage: summary.cloudCount == 0 ? "lock.shield.fill" : "icloud.and.arrow.up")
                .font(.headline)
                .foregroundStyle(summary.cloudCount == 0 ? .green : .primary)
            Text("This month: \(summary.onDeviceCount) on this Mac (\(String(format: "%.1f", summary.onDeviceMinutes)) min), \(summary.cloudCount) in the cloud (\(String(format: "%.1f", summary.cloudMinutes)) min).")
                .font(.callout).foregroundStyle(.secondary)
        }
    }
}

struct PermissionRows: View {
    @Environment(FlowController.self) private var controller
    @State private var microphone = Permissions.microphoneGranted
    @State private var speech = Permissions.speechGranted

    var body: some View {
        PermissionRow(title: "Allow Infinity Flow to use your microphone", detail: "Infinity Flow only uses the mic while you're dictating.", granted: microphone) {
            Task { microphone = await Permissions.requestMicrophone() }
        }
        PermissionRow(title: "Allow on-device speech recognition", detail: "Transcribe on this Mac, without sending audio anywhere.", granted: speech) {
            Task { speech = await Permissions.requestSpeech() }
        }
        PermissionRow(title: "Allow Infinity Flow to detect your shortcut", detail: "Input Monitoring lets Infinity Flow notice when you hold your dictation key.", granted: controller.inputMonitoringGranted,
                      request: Permissions.requestInputMonitoring) {
            Permissions.resetAndRequest("ListenEvent", request: Permissions.requestInputMonitoring)
        }
        PermissionRow(title: "Allow Infinity Flow to insert spoken words", detail: "Accessibility lets Infinity Flow put your words in the right textbox.", granted: controller.accessibilityGranted,
                      request: Permissions.requestAccessibility) {
            Permissions.resetAndRequest("Accessibility", request: Permissions.requestAccessibility)
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void
    /// For entries that look switched on in System Settings but don't apply: clear them and ask again.
    var reset: (() -> Void)?

    var body: some View {
        HStack {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                .foregroundStyle(granted ? .green : .secondary)
                .font(.title3)
            VStack(alignment: .leading) {
                Text(title).fontWeight(.medium)
                Text(detail).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !granted {
                if let reset {
                    Button("Already on? Reset", action: reset)
                        .buttonStyle(.link)
                        .help("If Infinity Flow is switched on in System Settings but this still isn't ticked, an older build's entry is in the way. This clears it so you can allow it again.")
                }
                Button("Allow", action: request).buttonStyle(.ink)
            }
        }
    }
}

struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Infinity Flow").font(Theme.display(32))
                Text("Hold a key, speak, and your words appear wherever you're typing. Free, private, and on your Mac.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 14) { PermissionRows() }
            VStack(alignment: .leading, spacing: 4) {
                Text("Hold fn and speak. Release to paste. Double-tap fn for hands-free.")
                Text("Using fn? Set System Settings › Keyboard › “Press 🌐 key to” to “Do Nothing”.")
            }
            .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }.buttonStyle(.inkSecondary)
                Spacer()
                Button("Start dictating", action: onDone).buttonStyle(.ink).keyboardShortcut(.defaultAction)
            }
        }
        .padding(36)
        .frame(width: 580)
        .background(Theme.page)
    }
}
