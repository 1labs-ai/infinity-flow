# Wispr Flow 1.6.1147 — core MVP feature map (for a clean-room SwiftUI replica)

Target: `/Applications/Wispr Flow.app` (`com.electron.wispr-flow`, Electron, LSMinimumSystemVersion 12.0).
This is static analysis only. The app was not run, and no user data, preferences, logs, caches or credentials were read.
No source code or image assets were copied. Only identifiers, constants, behaviour and exact English UI strings appear here.

## Evidence key
- **REA-A** `ev_834c806d7954e174f98be37740c0ad33b6adbe6fdb63aa47fbd832250fc7304d`: `analyze-javascript-application` on app.asar
  (sha256 b5880041…, 183 files, 1444 modules, coverage **partial**). Semantic analysis of `.webpack/main/index.js`,
  `renderer/status/index.js` and `renderer/overlay/index.js` was **not started** because of the result budget. Only file-level facts are retained for them.
- **REA-V** `ev_9315d50a…eacd`: `inspect-analysis-view` summary of REA-A. **REA-T** `ev_106fc01e…5d0d`: trace for seed string "accessibility" (11 matches, partial).
- REA-A identifies the windows as electron-renderer nodes `hub`, `status` (Flow Bar), `overlay`, `contextMenu`, `scratchpad`, `feature_tour`,
  `accessibility_drop`, `meeting_recorder` and `meeting_ax_inspector`, with one electron-main node (`.webpack/main/index.js`). It also records the native addons
  `panel_activation.node` and `node_sqlite3.node`.
- **SRC@n**: a plain read of the asar entry, extracted with `@electron/asar` into the scratchpad; n is the character offset in `.webpack/main/index.js` unless another file is named.
  The analyzer did not reach this code, so SRC citations are file and offset observations rather than REA graph facts.
- **STR:key**: a key from the English i18n table embedded in `renderer/overlay/index.js` (6,029 keys). All quoted UI strings are exact.
- **HLP**: identifier strings in the Swift helper `Resources/swift-helper-app-dist/Wispr Flow.app`
  (`com.electron.wispr-flow.accessibility-mac-app`, LSUIElement, links ApplicationServices/Carbon/IOKit/CoreAudio).
- Labels: **OBSERVED** (seen in the artifact), **INFERRED** (reasoned from observed facts), **UNKNOWN**.

## 1. Architecture (affects the replica's shape)
- OBSERVED: The Electron main process owns the state machine, shortcuts, tray and windows. A bundled Swift helper app owns OS integration:
  the CGEventTap keyboard and mouse capture, paste and clipboard, AX text context, mic holders and hardware info (HLP `KeyboardService`,
  `com.wispr-flow.input-event-capture.tap`, `event_tap_create`, `ClipboardMonitor`, `DelayedClipboardProvider`, `GetHardwareInfo` SRC@4493076).
- OBSERVED: The helper sends key events to JS, and JS decides on actions (SRC@5149877: "Electron and Helper do not agree on the number of keypresses").
- INFERRED: In a native replica, the event tap, the state machine and the paste logic can all live in a single process.

## 2. Hotkeys
Key codes are macOS virtual codes (SRC@~2724000): fn=63, the synthetic `doubleFn`=179, ctrl 59/62, opt 58/61, cmd 55/54, space 49, esc 53, caps 57.
Mouse buttons are 4098–4105 (middle and buttons 4–10) plus aux 65535.
- OBSERVED, default Mac shortcuts (`Be` map, SRC@~2731000; prefs default `shortcuts:d.Au` SRC@2897592):
  | Action (enum id) | Default | UI title (STR) |
  |---|---|---|
  | `ptt` | **fn** (hold) | "Push to talk" — "Hold to say something short" |
  | `popo` (hands-free) | **fn + space** | "Hands-free mode" — "Dictate hands-free by pressing this hotkey to start and stop" |
  | `lens` (command mode) | fn + ctrl | "Command Mode" — "Select text and ask Flow or Perplexity" |
  | `paste_last_text` | ctrl + cmd + V | "Paste last transcript" — "Paste the last thing you dictated" |
  | `copy_last_text` | ctrl + cmd + C | "Copy last transcript" — "Copy the last thing you dictated" |
  | `dismiss` | esc | "Cancel" — "Dismiss dictation and notifications" |
- OBSERVED, fallback when there is no Apple Fn key. The helper logs "Found an external non-Apple keyboard. Assuming no Fn key available." (HLP, `hasAppleFnKey`).
  If PTT is still fn on such a keyboard, onboarding switches the defaults to **ctrl+opt** (PTT), **ctrl+opt+space** (hands-free), cmd+ctrl+opt (lens), with paste and copy unchanged (hub `_e`/`he`, `renderer/hub/index.js`@1494018).
- OBSERVED, onboarding suggestion: "We recommend <pill>control</pill> + <pill>space</pill>" (STR:settings_hotkey_dialog_ptt_suggestion).
  Caps Lock can be used as a single-key PTT: "Caps Lock now starts dictation instead of turning on all caps…" (STR:shortcut_widget_caps_lock_callout; HLP `capsLockHIDManager`).
- OBSERVED, validation copy (SRC@~2726000 / STR:settings_shortcut_error_*):
  - "Shortcut must contain 3 or fewer keys"
  - "Shortcut cannot contain both left and right version of the same key"
  - "This shortcut is already in use"
  - "This shortcut is not allowed: {{keyString}}"
  - A shortcut must include a modifier or a mouse button (or be an allowed standalone key).
  Hands-free and PTT overlap warning: "Warning: Your Hands-free mode shortcut is a part of a Push-to-talk shortcut. This may lead to conflicts."
- OBSERVED, timing constants (module 59725, SRC@4275266): `DICTATION_DEBOUNCE_DELAY=500` ms, `SCRATCHPAD_PTT_DELAY_MS=350`,
  `DICTATION_DURATION_TIMEOUT=20 min`, `DICTATION_DURATION_WARNING_TIMEOUT=19 min`, `RECORDING_SAMPLE_RATE=16000`, `CHUNK_DURATION_MS=40`.
- OBSERVED, hold and toggle semantics (PTT down `je`, PTT up `Ge`, hands-free `Ye`; SRC@~4330000–4345000):
  - **PTT down while idle** starts dictation (state `initializing` then `listening`).
  - **PTT up after holding ≥ 500 ms** stops, transcribes and pastes. (Copy: "It'll paste what you said when you let go".)
  - **PTT up before 500 ms**: dictation waits 500 ms for a second press, then dismisses ("PTT stopping after timeout waiting for double press").
    A press shorter than 500 ms is never transcribed (also checked again at the transcription gate SRC@4264038).
  - **Second PTT down within 500 ms of start** locks into hands-free (`isLocked`). The Flow Bar receives `POPO`, plays the `popoLock` sound and shows `active_popo`.
    Copy: "Flow starts listening when you double-tap <shortcutKeys />" and "It'll paste in what you said when you tap again".
  - **Third quick press (within 500 ms) while locked** dismisses ("Action dismiss on quick triple action press").
  - **PTT down while locked** (later) stops and pastes. PTT release while locked is ignored.
  - **Hands-free key (fn+space)**: one press starts locked. The next press stops. A second press within 500 ms dismisses ("POPO dismiss on quick double press").
  - **Shortcut upgrade**: holding fn and then adding space upgrades the PTT session to hands-free without restarting (SRC@~5153000 "Shortcut upgrade").
  - **Esc** dismisses dictation, notifications, polish and the context menu. HLP: "Suppressing escape key during dictation" means Esc is swallowed while recording.
  - Dictation is ignored until onboarding is complete. Pressing again while the previous transcript is still processing raises a notification with the title
    "Flow was processing your last transcript" and the body "If you'd like to cancel, press {{shortcut}} or click below."
  - Another key pressed while starting cancels with "Dictation cancelled" / "Another key was pressed while starting. Hold only {{shortcut}} to dictate."
  - Max length: "You have <1 minute left before you reach the 20 minute limit!" and then "Transcription session ended." / "Flow supports up to 20 minutes per session."
  - Triple-tapping PTT starts Notetaker (pref `notetakerTripleTapShortcutEnabled`). This is out of MVP scope.
- OBSERVED: "Secure input is blocking keyboard shortcuts" (HLP). The tap also suppresses events for matched shortcuts (HLP "Suppressing event. Cur keys down:").
- INFERRED: Wispr suppresses fn at the event tap. The app has no string guiding the user to change the System Settings "Press 🌐 key to" option
  (no `AppleFnUsageType` and no "globe" string anywhere). **UNKNOWN**: whether the emoji picker or Dictation conflict is handled explicitly.

## 3. Flow Bar (recording pill), window `status`
- OBSERVED, window (SRC@6819466, `CQ`/`H`): a transparent, frameless, non-resizable, non-movable window, `type: "panel"` on macOS.
  Its title is "Flow Status Indicator". It is always on top at the `"screen-saver"` level, visible on all Spaces and over fullscreen apps.
  It is `skipTaskbar`, `hiddenInMissionControl`, has no shadow, is not focusable, uses `setIgnoreMouseEvents(true,{forward:true})`,
  and passes clicks through based on per-pixel alpha (log "lastAlphaCheck … alpha … threshold").
  On macOS 27, `panel_activation.node` `preventActivation` stops the panel from activating.
- OBSERVED, placement (module 58601, SRC@~6815000): the default dock edge is `statusDockEdge:"bottom"` (SRC@2902742).
  For the bottom edge, the window is 440×320 px, horizontally centred, with its bottom on the work-area bottom.
  For the left or right edge, the window is 490 px wide, up to 1144 px tall and vertically centred. The bar is drag-to-dock between left, right and bottom.
  Copy: "You can now move the Flow Bar!" / "Click and drag on the Flow Bar to move it to the left, right, or bottom of your screen."
  Hint: "Click and drag the Flow Bar to move it!". It opens on the display nearest the cursor.
- INFERRED: the visible pill is much smaller than the host window. Its CSS sizes are hashed CSS-module classes, so the exact pill px size is **UNKNOWN**.
- OBSERVED, visual states (enum `fw`, `renderer/status/index.js`@2483): `hidden`, `resting`, `context-menu`, `initializing`, `ready`,
  `active_ptt`, `active_popo`, `processing`, `polish_processing`, `polish_completed_action`, `polish_completed_na`, `polish_failed`,
  `auto_cleanup_completed`, `hotkey_reminder`, `instruct_completed`, `error`.
- OBSERVED, mapping from dictation status to bar state (status@~425000): listening→listening, stopping/processing/retrying→processing,
  initializing→initializing, error→error (resets after 500 ms), idle and dismissed→the rest state (`resting` or `hidden`).
  `ready`/`context-menu` show a mic icon. `processing` shows a processing animation.
  "Cleaned up!" with "See what's changed" auto-hides after 7 s for the first 3 diffs and after 5 s afterwards. The hotkey reminder hides after 5 s.
- OBSERVED, waveform (status@336878): `barCount` is 10 by default, symmetric from the centre, with a "bulge" coefficient. Meeting mode uses 5 bars.
  Onboarding copy: "Do you see purple bars while you speak?". The pulsar nudge colours are #7232A6 and #B282FF.
- OBSERVED, controls while hands-free: tooltips "Finish and paste" (stop) and "Cancel" (X). A word count tooltip reads "{{count, number}} words".
- OBSERVED, right-click menu (window `contextMenu`; code order in contextMenu@173571, so the order is INFERRED):
  "Hide for 1 hour", "Mute reminder for 12 hours", "Configure reminder", "Settings", "Microphone" (submenu; "Show other devices ({{count}})"),
  "Formatting options", "Transcript history", "Paste last transcript". "Languages" is also defined.
- OBSERVED, sounds (status@~406000; files in `Resources/assets/sounds`): the sound keys are `start`, `stop`, `popoLock`, `paste`,
  `notificationSuccess`, `notificationError`, `notificationAlert` and `achievement`. Sound sets are `default`, v1–v12, t1, notifv1 and notifv2
  (pref `selectedSoundFolder:null` = default). The paste sound plays on paste and the popoLock sound plays on entering hands-free.
  All sounds are gated by `enableSounds` (default true) and the setting "Dictation and notification sounds".
  The exact trigger points for the start and stop sounds are **UNKNOWN**; their call sites were not located.
- OBSERVED: "Show Flow Bar at all times" (`hideFlowBarPermanently:false` by default) and "Hidden for one hour".
  "Make Flow Bar and Notepad invisible while screen sharing" uses `setContentProtection`.

## 4. Text insertion and clipboard
- OBSERVED: JS sends `PasteText{text, htmlText?, pasteId, captureKeystrokeTrace, logAttributes}` to the helper and receives
  `PasteOutcome{pasteId, success, reason, timeElapsedMs}` (schema SRC@2517447).
- OBSERVED, helper paste path (HLP):
  1. Save the current pasteboard types ("Saved pasteboard types:").
  2. Write the text, either immediately ("Using original immediate clipboard setting") or with **delayed rendering** through `NSPasteboardItemDataProvider`
     ("Set up delayed clipboard rendering for text length:"). The item is marked `org.nspasteboard.ConcealedType`.
  3. Post the paste keystroke ("Performed paste operation").
     If no element is focused: "No valid element to focus, performing paste after app activation". Further fallbacks: "…using fallback element" and "…as last resort".
  4. Failure detection: "Started timer to detect failed pastes". If no app requests the delayed data → "Delayed clipboard timeout -- failed paste likely".
     Data requested → "Failed Timeout timer cancelled - paste succeeded".
  5. Restore: "Scheduling clipboard restoration in **500ms**", then "Clipboard contents restored and cleared".
     Restoration is skipped when `shouldRestore` is false or when the pasteboard "holds content that cannot be restored".
     The remote flag `disable-clipboard-restore` exists.
- INFERRED: the paste keystroke is a synthesized ⌘V CGEvent; there are `SimulateKeyPress` and "paste chord posted" requests. Insertion through AX `AXValue` is used
  only by the meeting-consent-chat path ("direct AXValue set did not stick, falling back to clipboard paste"). For dictation, insertion is clipboard plus paste.
- OBSERVED, failure UX: "Click a textbox and use {{shortcut}} to paste" (paste_failed_title) and
  "Flow can't paste right now. Text saved to clipboard" (polish). During onboarding: "Click on a textbox first and then dictate".
- OBSERVED: before dictation, the app reads AX context (focused textbox text and nearby words) for spelling. This is the setting "Context awareness":
  "Allow Flow to use limited, relevant text content from the app you're dictating in to spell names correctly and better understand you."

## 5. Transcript history (Hub → Home)
- OBSERVED, columns (migrations `Resources/migrations/*history*.js`): `transcriptEntityId`, `asrText`, `formattedText`, `editedText`, `pastedText`,
  `timestamp`, `audio`, `status`, `app`, `url`, `duration`, `numWords`, `language`/`detectedLanguage`, `isArchived`, `hasRevertedAI`, `micDevice`,
  `speechDuration` and `timezoneOffsetMinutes`, plus diagnostic fields. Storage is local SQLite (`node_sqlite3.node`, REA-A native-addon).
- OBSERVED, UI (STR:hub_history_*):
  - Rows are grouped by day ("Yesterday", …) and show a time with am/pm and the text.
  - Search: "Search past transcripts".
  - Row actions: "Copy transcript", "Play audio"/"Pause audio", "Send feedback".
  - Row menu: "Retry transcript", "Undo AI edit"/"Redo AI edit", "Delete transcript", "Extract audio".
  - Delete confirmation: "Are you sure you want to delete this transcript?" / "Once deleted it cannot be recovered" / "Yes, delete it".
  - Empty state: "No dictations yet" / "Once you dictate across different apps, your entire dictation history will appear here."
  - Dismissed row: "This transcription was dismissed." with the "Recover" link.
  - Silent audio: "Audio is silent.". Audio is kept for 14 days ("…no longer available (older than 14 days)").
  - Toasts: "Transcript copied", "Transcript deleted", "You can also paste your last transcript with {{shortcut}}".
- OBSERVED: retention setting "Local data storage", with the options "Store data locally" / "Auto-delete local data every 24hrs" / "Never store data locally".
  When history is off: "History disabled".

## 6. Menu bar (tray) and dock
- OBSERVED (SRC@6257842): a template icon from `assets/tray/TrayIconMac@2x.png` with the tooltip "Wispr Flow".
  The status item's preferred position is seeded to 40 (`NSStatusItem Preferred Position Item-0`).
  The title can show the next meeting and a countdown; this belongs to Notetaker and is out of MVP scope.
- OBSERVED, menu template order (SRC@~6255000):
  1. [Notetaker section: "Join meeting", "Now"/"Today"/"Tomorrow", "Past notes", "See all past notes"… — non-MVP]
  2. "Start Notetaker" (when enabled)
  3. "Open Wispr Flow"
  4. —
  5. Update item: "Check for updates..." / "Checking for updates..." / "Update downloading..." / "Update ready, restart now?" / "Error updating, please restart"
  6. —
  7. "Paste last transcript" (disabled when there is no last transcript; accelerator = the user shortcut).
     Below it is a disabled preview of the last transcript (25 chars plus "...", 270-char tooltip).
  8. —
  9. "Shortcuts"
  10. "Microphone" ▸ (checkbox per device)
  11. "Languages" ▸ (checkbox per language)
  12. —
  13. "Help center"
  14. "Talk to support" (⌘/)
  15. "Share feedback"
  16. —
  17. role `quit` (⌘Q)
- OBSERVED: the dock menu contains "Open Notetaker" and "Open Wispr Flow". "Show app in dock" is a setting (`hideAppInDock:false`).
  The helper is LSUIElement.

## 7. Onboarding and permissions
- OBSERVED, page enum in order (SRC@2649992; INFERRED to be the flow order, since some pages are A/B variants):
  login → welcome-basic/welcome-team → about-yourself → spend-time-typing → work-environment → social-proof/testimonials → introduction → privacy →
  **permissions** → **microphone-test** → language → **shortcut** → tiy-intro → try-it-yourself (variants: Slack/Gmail/Notion/WhatsApp) →
  time-savings… → personalize-* → team/referral → flow-pro.
  The progress sections are "Sign up", "Permissions", "Set up", "Learn", "Personalize", "Get started".
- OBSERVED, permissions screen copy (STR:permissions_*):
  - Header: "Give Flow permissions on your computer". When done: "Thanks for trusting us, we value your privacy".
  - Microphone:
    - Title: "Allow Flow to use your microphone"
    - Description: "Flow will only access the mic when you are actively using it"
    - Help text: "Flow will play a sound and show an animation when the mic is active"
    - Success: "Flow can now use your microphone"
  - Accessibility:
    - Title: "Allow Flow to insert spoken words"
    - Description: "This lets Flow put your spoken words in the right textbox"
    - Help text: "Flow uses this to gather context based on the application you're using, and to access your clipboard temporarily to paste text."
    - Success: "Flow can now paste text anywhere"
  - Buttons: "Allow", "Open Settings".
  - Accessibility drag guide:
    - "Drag this icon into the Accessibility list"
    - "Click Allow to open System Settings, then drop the icon into the list."
    - "Drop it into the Accessibility list above, then make sure Wispr Flow is turned on."
  - Errors: "Some permissions are not yet granted. Please grant all permissions to continue." / "Permission request timed out. Please try again or restart the app."
- OBSERVED, mechanism (SRC@6357516): the microphone uses `systemPreferences.askForMediaAccess("microphone")`.
  Info.plist NSMicrophoneUsageDescription: "Allow Wispr Flow microphone access to transcribe your speech."
  Accessibility sends the helper request `RequestAccessibilityPermission`, plus a floating draggable-icon window (`accessibility_drop`, flag `accessibility-drag-guidance`).
  On macOS 26+ a helper app `FlowPermissionGuide.app` (`com.electron.wispr-flow.permission-guide`, min OS 26.0) is used.
- OBSERVED, revoked banners:
  - "Microphone Permission Required" / "Flow needs microphone access to work." / "Grant Permission"
  - "Accessibility Permission Required" / "Flow needs accessibility access to work properly." / "Open Settings"
- OBSERVED, mic test:
  - "Test your microphone" / "We recommend built-in or wired microphones.<br />Bluetooth devices are less reliable." / "Do you see purple bars while you speak?"
  - Errors: "Microphone access required", "No microphone detected", "Microphone is in use", "Selected microphone unavailable".
- OBSERVED, shortcut test:
  - "Test your dictation shortcut" / "Hold <shortcutKeys /> while you speak. Flow Dictation turns your voice to text"
  - "We recommend the [fn] key at the bottom left of the keyboard."
  - "Does the button turn purple while pressing it?" / "Press the key on your keyboard!"
  - "Or use" / "Use {{shortcut}} instead"
- OBSERVED, try-it-yourself: "Flow starts listening <br /> when you hold <shortcutKeys />" / "Give it a try!".
  Final screen: "Go try Flow in another app" (steps "Go to any app", "Click on a textbox").
- **UNKNOWN / not observed**: any Globe/Fn-key System Settings setup step. No such copy exists in the English table.

## 8. Settings relevant to the MVP (exact labels)
- OBSERVED, sidebar (STR:settings_sidebar_page_*): "General", "System", "Data and Privacy", "Experimental", plus non-MVP pages (Account, Team, Plans and Billing, Notetaker, Connectors, MCP…).
- OBSERVED, General: "Shortcuts" ("Hold [key] and speak."; dialog "Choose your preferred shortcuts for using Flow."), "Microphone" ("Built-in mic (recommended)",
  "Edit Ranking", "Forget device"), "Languages" ("Auto-detect (99 languages)", "Dictation languages", "Please select at least one language or turn on auto-detect"),
  and "App Language".
- OBSERVED, System (hub@1258007 order): "Launch app at login" (default on), "Show Flow Bar at all times", "Dictation reminder", "Show app in dock",
  "Auto-add to dictionary" ("Adds corrected words automatically"), "Email auto signature", "Creator mode",
  "Smart Formatting" ("Automatically formats your dictation."), "Dictation and notification sounds", "Mute all audio while dictating"
  (mac default off; "Pause music while dictating" is under Experimental), "Restart tutorial", and "Reset app".
- OBSERVED, Data and Privacy: "Context awareness", "Local data storage", "Dictation cloud storage", "Improve the model for everyone", "Data Sharing".
- OBSERVED, Experimental: "Press Enter command" ("Automatically press enter when you say 'press enter' at the end of a dictation"), "Command Mode", "Stacked messages".

## 9. Transcription pipeline (behaviour only)
- OBSERVED: **cloud ASR**. Hosts include `api.wisprflow.ai` and a Baseten model chain (`*.api.baseten.co`), and the code refers to Baseten chunk sizing.
  Transports are `grpc`, `voice_actions_realtime`, `http_race` and `http_fallback` (SRC@4285978). `HTTP_FALLBACK_MAX_AUDIO_DURATION_MS=30000`.
  Audio is captured at 16 kHz, Opus-encoded in 40 ms chunks (`incrementalOpusEncoder.worker.js`, `recorderWorklet.js`) and streamed during recording.
  No local ASR engine was found (0 hits for whisper.cpp/ggml/onnx; REA-A has no ASR native addon).
- OBSERVED, offline copy: "Is your internet connected?" / "Your audio will be saved for retry if the transcription fails." Failed transcripts can be retried from History.
- OBSERVED: the request carries app context (app name, bundle ID, URL, app type such as messaging/email/AI/terminal/IDE from bundle-ID lists in module 59725) and AX nearby text.
  The server returns ASR text plus formatted text. History keeps both `asrText` and `formattedText`, and "Undo AI edit" reverts to the raw text.
- OBSERVED, post-processing levels ("Auto Cleanup", STR:hub_cleanup_level_*):
  - None: "Transcribes exactly what you said, including mistakes"
  - Light: "Cleans up filler words and grammar"
  - Medium: "Edits for clarity and conciseness"
  - High: "Rewrites for brevity and polish"
  Style presets are "Caps + Punctuation" (formal), "Caps + Less punctuation" (casual) and "No Caps + Less punctuation" (very casual), applied per context
  (personal messages, work messages, email, other). Personal dictionary and snippets exist. Marketing copy: "Flow removes filler words and auto-punctuates".
- OBSERVED, empty and low-audio handling: "We couldn't hear you" / "We didn't pick up any speech from your {{micLabel}} microphone",
  "Is your microphone muted?" and "We didn't hear you clearly.".
- INFERRED: formatting and filler removal happen server-side (an LLM formatting step), because no client-side formatter rules were found. A replica needs its own choice here, such as local ASR plus optional LLM cleanup.

## 10. Meeting notes ("Notetaker")
Sources for this section: the Sequelize migrations shipped as plain files in `Resources/migrations/` (**MIG:**name), and exact English strings
from plain reads of `renderer/meeting_recorder/index.js` and `renderer/hub/index.js` (**STR**). Nothing was executed and no user data was read.
- OBSERVED, data model: a `Meetings` table (MIG:20260410120000-create-meetings-table) later gains `summary`, `notes` (editor JSON for your own notes),
  `speakerMap` (`{ people, assignments }`), `participantNames`, `calendarEventExternalId`, `endedAt`, `recordedMs` and refine/upload state
  (MIG:20260702120000-add-meetings-notes-summary, 20260702120000-add-meetings-speaker-map, 20260616120000-add-meetings-ended-at, 20260915120000-add-meetings-recorded-ms).
  Action items live in a `Todos` table with an optional `meetingId` and `open` status (MIG:20260605120000-create-todos-table).
  "Ask about a meeting" chats are stored in `NotetakerChats` / `NotetakerChatMessages` (MIG:20260715120000-create-notetaker-chat-tables).
  Calendar events are cached with reminder state (MIG:20260427120000-create-calendar-events-table), and meetings can be filed into shared `Folders`.
- OBSERVED, capture: the mic and the Mac's audio are captured separately ("Meeting mic capture active", "Meeting system capture active",
  "Capture meeting audio for accurate transcripts", "Allow Wispr Flow under System Audio Recording in System Settings",
  "Notetaker uses this to transcribe the other participants in your meetings"). It needs macOS 13 or later ("Notetaker needs macOS 13 or later to record meetings").
- OBSERVED, while recording: a live transcript ("Show live transcript", "Live transcripts"), your own notes ("Take your own notes here"),
  pause and resume ("Stop Notetaker for the current recording? You can resume it later."), and discard ("Discard this meeting?", "MeetingStartedByMistake").
- OBSERVED, starting and stopping: call detection ("Meeting detected", "Transcribe this meeting with Wispr?",
  "Notetaker asks if you want to start a note when you join a call"), "Start Notetaker when a meeting begins", "Stop Notetaker when a call ends",
  a maximum length ("Notetaker stops automatically at this length, with a warning shortly before"), check-ins ("Meeting still going?"),
  and sleep handling ("Notetaker stopped when your Mac went to sleep").
- OBSERVED, afterwards: "Meeting complete! Your summary will be ready shortly", summary sections and action items ("Action items", "Add action item"),
  speaker naming ("Assign speaker names", "Speaker labels"), "Ask anything about this meeting", "Copy meeting to Markdown", "Copy summary",
  "Copy transcript", "Rerun meeting?" ("This will replace the transcript and summary using the saved audio."), "Delete meeting?",
  transcript retention ("Notetaker transcript retention"), and search ("Search your meetings").
- OBSERVED, server side: summaries come from the backend (`POST /api/v1/calendar/meetings/{id}/post-meeting`, MIG:20260510120000-add-summary-columns),
  and the refined transcript arrives through a Soniox webhook (MIG:20260512120000-add-meetings-refinement-columns). Calendar comes from Google or Outlook
  through Wispr's servers.
- Infinity Flow's version (clean-room, local): two tracks (mic with echo cancellation, system audio through a Core Audio process tap) cut into chunks at
  pauses and transcribed while you talk with the engine chosen in Settings; "You" and "Others" as speakers, renamable; notes, summary, action items and
  answers from Apple Intelligence on the Mac or a chat model with your own key; call detection from which apps are using the microphone (Core Audio
  process list, no screen reading); optional titles from the macOS calendar (EventKit). Not built: server sync, shared folders, Google/Outlook
  integrations, per-person speaker diarization, and meeting reminders.

## 11. Open gaps
- UNKNOWN: exact pill pixel size, corner radius and colours (hashed CSS), the start/stop sound trigger sites, the exact paste keystroke API (CGEvent vs AppleScript),
  the failed-paste timeout value, the Globe-key conflict handling, and the full Flow Bar menu order.
- Coverage limits: REA-A did not run semantic analysis on main, status or overlay, so their behaviour comes from plain reads of the extracted bundle. Nothing was executed.
