import AppKit
import SwiftUI

/// The floating recording pill at the bottom of the screen. It never takes focus,
/// so the app you're typing into stays active.
@MainActor
final class FlowPillController {
    private let panel: NSPanel

    init(controller: FlowController) {
        panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 560, height: 64),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: true)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: FlowPillView().environment(controller))
    }

    func show() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        guard let area = screen?.visibleFrame else { return }
        let size = panel.frame.size
        panel.setFrameOrigin(NSPoint(x: area.midX - size.width / 2, y: area.minY + 20))
        panel.orderFrontRegardless()
    }

    func hide() {
        panel.orderOut(nil)
    }
}

struct FlowPillView: View {
    @Environment(FlowController.self) private var controller

    var body: some View {
        HStack(spacing: 10) {
            switch controller.state {
            case .listening:
                if controller.isLocked {
                    Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(.white.opacity(0.8))
                } else {
                    Circle().fill(Color.red).frame(width: 8, height: 8)
                }
                Waveform(bars: AudioLevel.bars(from: controller.levels))
            case .transcribing:
                ProgressDots()
                Text("Transcribing").font(.system(size: 13, weight: .medium)).foregroundStyle(.white.opacity(0.8))
            case .error(let message):
                Image(systemName: "exclamationmark.circle.fill").foregroundStyle(Color.orange)
                Text(message).font(.system(size: 13, weight: .medium)).foregroundStyle(.white).lineLimit(1)
            case .idle:
                EmptyView()
            }
        }
        .padding(.horizontal, 16)
        .frame(height: 40)
        .background(Capsule().fill(Color(red: 0.11, green: 0.09, blue: 0.08).opacity(0.94)))
        .overlay(Capsule().strokeBorder(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.35), radius: 10, y: 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeOut(duration: 0.15), value: controller.state)
    }
}

private struct Waveform: View {
    let bars: [Float]

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            ForEach(bars.indices, id: \.self) { i in
                Capsule()
                    .fill(LinearGradient(colors: [Color(red: 1, green: 0.8, blue: 0.3), Color(red: 0.98, green: 0.52, blue: 0.12)],
                                         startPoint: .top, endPoint: .bottom))
                    .frame(width: 3.5, height: 4 + CGFloat(bars[i]) * 22)
            }
        }
        .animation(.linear(duration: 0.06), value: bars)
    }
}

private struct ProgressDots: View {
    var body: some View {
        TimelineView(.animation) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: 4) {
                ForEach(0..<3) { i in
                    Circle()
                        .fill(Color(red: 1, green: 0.7, blue: 0.25))
                        .frame(width: 6, height: 6)
                        .opacity(0.35 + 0.65 * max(0, sin((t * 4) - Double(i) * 0.7)))
                }
            }
        }
    }
}
