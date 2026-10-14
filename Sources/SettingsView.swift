import SwiftUI

struct SettingsView: View {
    @Environment(FlowController.self) private var controller
    @AppStorage(SettingsKey.hotkey) private var hotkey = Hotkey.fn.rawValue
    @AppStorage(SettingsKey.engine) private var engine = TranscriptionEngine.onDevice.rawValue
    @AppStorage(SettingsKey.playSounds) private var playSounds = true
    @AppStorage(SettingsKey.restoreClipboard) private var restoreClipboard = true
    @State private var apiKey = APIKeyStore.read() ?? ""

    var body: some View {
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
            }
            Section("Transcription") {
                Picker("Engine", selection: $engine) {
                    ForEach(TranscriptionEngine.allCases) { Text($0.title).tag($0.rawValue) }
                }
                if engine == TranscriptionEngine.openAI.rawValue {
                    SecureField("OpenAI API key", text: $apiKey)
                        .onSubmit { APIKeyStore.save(apiKey) }
                        .onChange(of: apiKey) { APIKeyStore.save(apiKey) }
                    Text("Audio is sent to OpenAI for transcription. The key is stored in your keychain.")
                        .font(.callout).foregroundStyle(.secondary)
                } else {
                    Text("Speech is transcribed on this Mac when the language supports it.")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            Section("Permissions") {
                PermissionRows()
            }
        }
        .formStyle(.grouped)
        .navigationTitle("Settings")
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
        PermissionRow(title: "Allow Infinity Flow to insert spoken words", detail: "This lets Infinity Flow detect your shortcut and put your words in the right textbox.", granted: controller.accessibilityGranted) {
            Permissions.requestAccessibility()
        }
    }
}

private struct PermissionRow: View {
    let title: String
    let detail: String
    let granted: Bool
    let request: () -> Void

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
            if !granted { Button("Allow", action: request) }
        }
    }
}

struct OnboardingView: View {
    let onDone: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Welcome to Infinity Flow").font(.system(size: 28, weight: .bold))
                Text("Hold a key, speak, and your words appear wherever you're typing.")
                    .foregroundStyle(.secondary)
            }
            VStack(spacing: 14) { PermissionRows() }
            VStack(alignment: .leading, spacing: 4) {
                Text("Hold fn and speak. Release to paste. Double-tap fn for hands-free.")
                Text("Using fn? Set System Settings › Keyboard › “Press 🌐 key to” to “Do Nothing”.")
            }
                .font(.callout).foregroundStyle(.secondary)
            HStack {
                Button("Open Keyboard Settings") { Permissions.openKeyboardSettings() }
                Spacer()
                Button("Start Dictating", action: onDone).keyboardShortcut(.defaultAction)
            }
        }
        .padding(32)
        .frame(width: 560)
    }
}
