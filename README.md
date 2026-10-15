<p align="center"><img src="docs/icon.png" width="128" height="128" alt="Infinity Flow icon"></p>

<h1 align="center">Infinity Flow</h1>

<p align="center">
  <b>Speak anywhere. Keep your words.</b><br>
  Free, open-source voice dictation for macOS: private by default, no subscription, and it never loses a word.
  <br><br>
  <a href="https://github.com/1labs-ai/infinity-flow/actions/workflows/ci.yml"><img src="https://github.com/1labs-ai/infinity-flow/actions/workflows/ci.yml/badge.svg" alt="CI"></a>
  <a href="LICENSE"><img src="https://img.shields.io/badge/license-MIT-blue.svg" alt="MIT License"></a>
  <img src="https://img.shields.io/badge/platform-macOS%2015%2B-lightgrey.svg" alt="macOS 15+">
  <a href="CONTRIBUTING.md"><img src="https://img.shields.io/badge/PRs-welcome-brightgreen.svg" alt="PRs welcome"></a>
</p>

Hold **fn**, speak, and let go: your words appear in whatever app you're typing in, whether that's Slack, Gmail, Notion,
your editor, or a terminal. Infinity Flow transcribes on your Mac by default, so it's free and private. If you want cloud
accuracy, you can bring your own API key instead of paying a subscription.

## Why Infinity Flow

We read user reviews and comments about popular AI dictation apps and built Infinity Flow around the most common complaints.

| What people complain about | What Infinity Flow does |
|---|---|
| Voice and context sent to the cloud, plus screenshot controversies | **Private by default.** Transcription runs on your Mac. No screenshots, no reading other apps, no account, no server. A privacy receipt shows exactly what left your Mac this month. |
| $12–15 a month subscriptions and weekly word limits | **No subscription.** Free and unlimited on device. For the cloud, bring your own key: Groq's free tier covers most people, and OpenAI costs about $0.003 per minute (about $2 a month for heavy use). |
| "Works when it works", lost dictations, failed pastes | **Never lose a word.** Every recording is kept until it's transcribed. Failed dictations can be retried from History. If no app accepts the paste, the text stays on your clipboard and Infinity Flow tells you. |
| AI "polish" that drops or changes words and numbers | **Your words, not the AI's.** Cleanup is Off, Light (on device), or AI polish. Numbers and names are protected, and the original is always one click away. |
| Heavy Electron apps with slow startup | **Native and light.** Swift and SwiftUI, a 2.4 MB app, and about 28 MB of memory at idle (measured on a debug build). |

## Features

- **Hold-to-talk** with fn (Globe), Right Option, or Right Command. Release to paste.
- **Hands-free:** double-tap the key to lock it on, then press once more to finish. Esc or a quick triple tap cancels.
- **Shortcuts:** ⌃⌘V pastes your last transcript, ⌃⌘C copies it. Sessions end at 20 minutes.
- **Floating pill** with a live waveform. It never takes focus from the app you're typing in.
- **Paste with confirmation:** text is pasted through ⌘V, and Infinity Flow checks that an app actually received it. Your clipboard is restored afterwards, and dictated text is marked so clipboard managers skip it.
- **Engines:** Apple on-device speech recognition, or any OpenAI-compatible provider with your own key (Groq, OpenAI, or a custom or local server such as LM Studio).
- **Cleanup:** Off, Light (removes "um", "uh" and accidental repeats on device), or AI polish (Apple Intelligence on device when available, or your own model). A guard rejects any rewrite that loses a number or changes too much.
- **History:** searchable and grouped by day. Each entry shows the app, engine and duration. Play the recording, copy the text, see the original before cleanup, transcribe again, or retry a failed dictation.
- **Recordings:** saved as WAV files on your Mac, kept forever or for 30 or 7 days. Open the folder, or delete one recording or all of them.
- **Privacy receipt** and a **monthly cost meter** for your cloud key.
- **Dock or menu bar:** shows in the Dock by default; turn that off in Settings to keep it in the menu bar only.

### Meeting notes

- **Records the whole call:** your mic and your Mac's audio as two tracks, so the notes include everyone on Zoom, Meet, Teams, FaceTime or Slack.
  Echo cancellation keeps the call out of your own track when you use speakers. No bot joins your call.
- **Live transcript:** speech is cut into short parts at natural pauses and transcribed while you talk, with the engine you chose.
  Speakers are "You" and "Others" (or the attendee's name); rename them in the transcript. Play any part back.
- **Notes when it ends:** a title, a one-line summary, topic notes and a checklist of action items, written by Apple Intelligence on your Mac
  or a chat model with your own key. Your own notes from the My notes tab are included. Long meetings are summarized part by part.
- **Ask anything about a meeting:** "What did we decide?" answers come from that meeting's notes and transcript.
- **Starts and stops for you:** offers to take notes when a call app starts using the mic, stops when the call ends, at a length limit
  (with a warning), or when your Mac sleeps. Pause, resume or discard from the floating recorder or the menu bar.
- **Never loses a meeting:** every part is saved before it is transcribed, failed parts can be retried, and a meeting cut short by a quit or crash
  is finished at the next launch.
- **Copy as Markdown**, search across all meetings, and optional titles and attendees from your macOS calendar.

## Bring your own key

| Provider | Model | Price (Oct 2026, check the provider's site) |
|---|---|---|
| On this Mac | Apple Speech | Free |
| [Groq](https://console.groq.com/keys) | `whisper-large-v3-turbo` | Free tier, then about $0.04 per hour of audio (10 s minimum per request) |
| [OpenAI](https://platform.openai.com/api-keys) | `gpt-4o-mini-transcribe` | About $0.003 per minute |
| Custom | Any OpenAI-compatible `/audio/transcriptions` server | Your own (local servers are free) |

Keys are stored in your macOS keychain, and audio goes straight from your Mac to the provider you choose. Cloud uploads
are WAV files, so very long dictations (over about 12 minutes) may exceed some providers' 25 MB upload limit. Use the
on-device engine for those.

## Requirements

- macOS 15+ and Xcode 16+ (Apple Intelligence polish needs macOS 26 on a supported Mac)
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

## Build and run

```bash
xcodegen generate
xcodebuild -project InfinityFlow.xcodeproj -scheme InfinityFlow -derivedDataPath build test
```

For daily use, build with your own Apple Development certificate, so that macOS keeps the Accessibility permission when
you rebuild (ad-hoc builds lose it every time):

```bash
SIGN_IDENTITY="Apple Development: Your Name (XXXXXXXXXX)" TEAM_ID=ABCDE12345 ./scripts/run.sh
```

On first launch, allow **Microphone**, **Speech Recognition**, and **Accessibility**. The first time you take meeting notes, macOS asks to
allow **System Audio Recording** so the notes include the other people on the call. If you use fn, set
System Settings › Keyboard › "Press 🌐 key to" to "Do Nothing". If Accessibility is switched on but Infinity Flow still
asks for it, run `tccutil reset Accessibility com.oneinfinitylabs.InfinityFlow` and allow it again.

## Layout

| Path | Contents |
|---|---|
| `Sources/FlowController.swift` | The dictation loop: hotkey → record → transcribe → clean up → paste → History |
| `Sources/FlowLogic.swift` | Hold-to-talk state machine, audio levels, multipart body, date groups |
| `Sources/Providers.swift` | Cloud presets, cost estimate, privacy receipt |
| `Sources/Cleanup.swift` | Light cleanup, the number guard, Apple Intelligence and cloud polish |
| `Sources/Transcription.swift` | Apple on-device and OpenAI-compatible transcribers |
| `Sources/TextInserter.swift` | Paste with confirmation, clipboard restore |
| `Sources/HotkeyMonitor.swift` | Event tap for the hold-to-talk key, plus Esc/⌃⌘V/⌃⌘C |
| `Sources/AudioRecorder.swift`, `AudioPlayback.swift` | 16 kHz WAV capture with live levels; playback from History |
| `Sources/FlowPill.swift` | Floating, non-activating recording pill |
| `Sources/HubView.swift`, `SettingsView.swift` | Home, History, Settings and onboarding |
| `Sources/MeetingController.swift` | Meeting notes: recording, the transcription queue, AI notes, questions, call detection, recovery |
| `Sources/MeetingAudio.swift` | Mic and system-audio capture, and the chunk writer |
| `Sources/MeetingLogic.swift` | Chunking rules, notes parsing, Markdown export, context for questions |
| `Sources/MeetingModels.swift`, `MeetingsView.swift`, `MeetingPanel.swift` | Meeting storage, the Meetings screen and the floating recorder |
| `Tests/` | Unit tests for the logic |
| `docs/feature-map.md` | Behavior map of the app we modeled, from static analysis |
| `docs/marketing.md` | Positioning and launch copy |

## Roadmap

Personal dictionary and voice snippets, a choice of microphone, a draggable pill, compressed uploads for long cloud
dictations, and per-app styles. See the [open issues](https://github.com/1labs-ai/infinity-flow/issues) to pick one up.

## Contributing

Contributions of every size are welcome. Read [CONTRIBUTING.md](CONTRIBUTING.md), then look for issues labeled
[`good first issue`](https://github.com/1labs-ai/infinity-flow/labels/good%20first%20issue). Please follow our
[Code of Conduct](CODE_OF_CONDUCT.md), and report security issues as described in [SECURITY.md](SECURITY.md).

## License

[MIT](LICENSE) © One Infinity Labs, Inc. and contributors.

Infinity Flow's behavior is modeled on a static analysis of Wispr Flow made with [REA](https://github.com/morluto/rea)
(see [docs/feature-map.md](docs/feature-map.md)). No Wispr code or assets are included, and Infinity Flow uses its own
transcription. It is an independent project and is not affiliated with, endorsed by, or sponsored by the makers of Wispr Flow.
