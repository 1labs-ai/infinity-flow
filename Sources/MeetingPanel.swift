import AppKit
import SwiftUI

/// The floating meeting recorder in the top-right corner. It never takes focus from your call,
/// and you can drag it anywhere.
@MainActor
final class MeetingPanelController {
    private let panel: NSPanel
    private var placed = false

    init(meetings: MeetingController) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 360, height: 190),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.isMovableByWindowBackground = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentView = ClickThroughHostingView(rootView: MeetingPanelView().environment(meetings))
    }

    func show() {
        if !placed {
            let mouse = NSEvent.mouseLocation
            let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
            guard let area = screen?.visibleFrame else { return }
            let size = panel.frame.size
            panel.setFrameOrigin(NSPoint(x: area.maxX - size.width - 12, y: area.maxY - size.height - 8))
            placed = true
        }
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

/// Lets a click on a button work straight away, without first making the panel key.
private final class ClickThroughHostingView<Content: View>: NSHostingView<Content> {
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }
    override var mouseDownCanMoveWindow: Bool { true }
}

struct MeetingPanelView: View {
    @Environment(MeetingController.self) private var meetings

    var body: some View {
        VStack(alignment: .trailing, spacing: 6) {
            if meetings.isRecording || meetings.phase == .finishing {
                RecorderCard()
            } else if let app = meetings.detectedApp {
                DetectionCard(app: app)
            }
            if let notice = meetings.notice {
                NoticeCard(text: notice, meeting: meetings.noticeMeeting)
            }
        }
        .padding(8)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topTrailing)
        .animation(.easeOut(duration: 0.15), value: meetings.phase)
    }
}

private struct PanelBackground: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 14).fill(Color(red: 0.11, green: 0.09, blue: 0.08).opacity(0.95)))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Color.white.opacity(0.12)))
            .shadow(color: .black.opacity(0.3), radius: 8, y: 3)
            .foregroundStyle(.white)
    }
}

private struct RecorderCard: View {
    @Environment(MeetingController.self) private var meetings

    var body: some View {
        HStack(spacing: 10) {
            if meetings.phase == .paused {
                Image(systemName: "pause.circle.fill").foregroundStyle(.orange)
            } else {
                Circle().fill(Color.red).frame(width: 9, height: 9)
            }
            TimelineView(.periodic(from: .now, by: 1)) { _ in
                Text(MeetingFormat.timestamp(meetings.clock.elapsed()))
                    .font(.system(size: 13, weight: .semibold).monospacedDigit())
            }
            VStack(alignment: .leading, spacing: 3) {
                LevelBar(label: "You", level: meetings.micLevel)
                LevelBar(label: "Others", level: meetings.othersLevel)
            }
            Spacer(minLength: 4)
            if meetings.phase == .finishing {
                ProgressView().controlSize(.small)
            } else {
                PanelButton(symbol: meetings.phase == .paused ? "play.fill" : "pause.fill",
                            help: meetings.phase == .paused ? "Resume" : "Pause") {
                    meetings.phase == .paused ? meetings.resume() : meetings.pause()
                }
                PanelButton(symbol: "note.text", help: "Open notes") {
                    if let id = meetings.current?.uuid { meetings.open(id) }
                }
                PanelButton(symbol: "stop.fill", help: "Stop and write notes", tint: .red) { meetings.stop() }
            }
        }
        .frame(width: 320)
        .modifier(PanelBackground())
    }
}

private struct LevelBar: View {
    let label: String
    let level: Float

    var body: some View {
        HStack(spacing: 5) {
            Text(label).font(.system(size: 9, weight: .medium)).foregroundStyle(.white.opacity(0.6)).frame(width: 34, alignment: .leading)
            GeometryReader { proxy in
                Capsule().fill(.white.opacity(0.12))
                    .overlay(alignment: .leading) {
                        Capsule()
                            .fill(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.3), Color(red: 0.98, green: 0.52, blue: 0.12)],
                                                 startPoint: .leading, endPoint: .trailing))
                            .frame(width: max(3, proxy.size.width * CGFloat(level)))
                    }
            }
            .frame(width: 70, height: 4)
            .animation(.linear(duration: 0.08), value: level)
        }
    }
}

private struct DetectionCard: View {
    @Environment(MeetingController.self) private var meetings
    let app: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "waveform.badge.mic").font(.system(size: 16)).foregroundStyle(Color(red: 1, green: 0.7, blue: 0.25))
            VStack(alignment: .leading, spacing: 1) {
                Text("Meeting detected").font(.system(size: 13, weight: .semibold))
                Text("Take notes for your \(app) call?").font(.system(size: 11)).foregroundStyle(.white.opacity(0.7))
            }
            Spacer(minLength: 4)
            Button("Not now") { meetings.dismissDetection() }
                .buttonStyle(.plain).font(.system(size: 12)).foregroundStyle(.white.opacity(0.7))
            Button("Take notes") { meetings.start(app: app) }
                .buttonStyle(.borderedProminent).controlSize(.small).tint(Color(red: 0.98, green: 0.52, blue: 0.12))
        }
        .frame(width: 320)
        .modifier(PanelBackground())
    }
}

private struct NoticeCard: View {
    @Environment(MeetingController.self) private var meetings
    let text: String
    let meeting: UUID?

    var body: some View {
        HStack(spacing: 8) {
            Text(text).font(.system(size: 12)).lineLimit(3).fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 4)
            if let meeting {
                Button("Open") {
                    meetings.open(meeting)
                    meetings.dismissNotice()
                }
                .buttonStyle(.plain).font(.system(size: 12, weight: .semibold)).foregroundStyle(Color(red: 1, green: 0.7, blue: 0.25))
            }
            Button { meetings.dismissNotice() } label: { Image(systemName: "xmark").font(.system(size: 10, weight: .bold)) }
                .buttonStyle(.plain).foregroundStyle(.white.opacity(0.6))
        }
        .frame(width: 320)
        .modifier(PanelBackground())
    }
}

private struct PanelButton: View {
    let symbol: String
    let help: String
    var tint: Color = .white
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 26, height: 26)
                .background(Circle().fill(.white.opacity(0.12)))
                .foregroundStyle(tint)
        }
        .buttonStyle(.plain)
        .help(help)
    }
}
