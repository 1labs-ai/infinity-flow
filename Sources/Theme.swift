import AppKit
import SwiftUI

/// The hub's look: warm paper surfaces, a serif display face for headings, and soft bordered cards.
enum Theme {
    static let page = Color(light: 0xF7F4EE, dark: 0x1B1917)
    static let sidebar = Color(light: 0xEFEBE3, dark: 0x151312)
    static let card = Color(light: 0xFFFFFF, dark: 0x252220)
    static let cardHover = Color(light: 0xF4F1EB, dark: 0x2E2A27)
    static let border = Color(light: 0x000000, dark: 0xFFFFFF, lightAlpha: 0.08, darkAlpha: 0.09)
    static let ink = Color(light: 0x1D1A17, dark: 0xF4EFE7)
    static let muted = Color(light: 0x6F675E, dark: 0xA39A90)
    static let faint = Color(light: 0x9C948A, dark: 0x7A7269)
    static let accent = Color(red: 0.95, green: 0.48, blue: 0.10)
    static let accentSoft = Color(light: 0xFCE9D6, dark: 0x3A2918)

    static func display(_ size: CGFloat, weight: Font.Weight = .regular) -> Font {
        .system(size: size, weight: weight, design: .serif)
    }
}

extension Color {
    /// A color that follows the system appearance.
    init(light: UInt32, dark: UInt32, lightAlpha: CGFloat = 1, darkAlpha: CGFloat = 1) {
        self.init(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let hex = isDark ? dark : light
            return NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                           blue: CGFloat(hex & 0xFF) / 255, alpha: isDark ? darkAlpha : lightAlpha)
        })
    }
}

struct CardStyle: ViewModifier {
    var padding: CGFloat = 20

    func body(content: Content) -> some View {
        content
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 16).fill(Theme.card))
            .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(Theme.border))
    }
}

extension View {
    func card(padding: CGFloat = 20) -> some View { modifier(CardStyle(padding: padding)) }
}

/// A page title in the display face, with an optional subtitle and trailing controls.
struct PageHeader<Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: () -> Trailing

    init(_ title: String, subtitle: String? = nil, @ViewBuilder trailing: @escaping () -> Trailing = { EmptyView() }) {
        self.title = title
        self.subtitle = subtitle
        self.trailing = trailing
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text(title).font(Theme.display(34)).foregroundStyle(Theme.ink)
                if let subtitle {
                    Text(subtitle).font(.system(size: 14)).foregroundStyle(Theme.muted)
                }
            }
            Spacer(minLength: 12)
            trailing()
        }
    }
}

/// A small uppercase label above a group, like "TODAY".
struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold))
            .kerning(0.8)
            .foregroundStyle(Theme.faint)
    }
}

/// Dark ink button (light text) for the main action; bordered for secondary ones.
struct InkButtonStyle: ButtonStyle {
    var prominent = true
    var tint: Color?

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .foregroundStyle(prominent ? Theme.page : (tint ?? Theme.ink))
            .background(
                Capsule().fill(prominent ? (tint ?? Theme.ink) : Theme.card)
            )
            .overlay(Capsule().strokeBorder(prominent ? Color.clear : Theme.border))
            .opacity(configuration.isPressed ? 0.75 : 1)
            .contentShape(Capsule())
    }
}

extension ButtonStyle where Self == InkButtonStyle {
    static var ink: InkButtonStyle { InkButtonStyle() }
    static var inkSecondary: InkButtonStyle { InkButtonStyle(prominent: false) }
}

/// A rounded search box used in page headers.
struct SearchBox: View {
    @Binding var text: String
    let prompt: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.faint)
            TextField(prompt, text: $text).textFieldStyle(.plain)
            if !text.isEmpty {
                Button { text = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.faint)
            }
        }
        .font(.system(size: 13))
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .frame(width: 240)
        .background(Capsule().fill(Theme.card))
        .overlay(Capsule().strokeBorder(Theme.border))
    }
}

/// A compact stat: big number over a label.
struct StatPill: View {
    let value: String
    let label: String
    let symbol: String

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: symbol)
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.accent)
                .frame(width: 32, height: 32)
                .background(Circle().fill(Theme.accentSoft))
            VStack(alignment: .leading, spacing: 1) {
                Text(value).font(.system(size: 18, weight: .semibold)).monospacedDigit().foregroundStyle(Theme.ink)
                Text(label).font(.system(size: 12)).foregroundStyle(Theme.muted).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 14).fill(Theme.card))
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Theme.border))
    }
}

/// Underlined tabs, used in the meeting view.
struct UnderlineTabs<Tab: Hashable & Identifiable & RawRepresentable<String>>: View {
    let tabs: [Tab]
    @Binding var selection: Tab

    var body: some View {
        HStack(spacing: 22) {
            ForEach(tabs) { tab in
                Button { selection = tab } label: {
                    VStack(spacing: 7) {
                        Text(tab.rawValue)
                            .font(.system(size: 13, weight: selection == tab ? .semibold : .regular))
                            .foregroundStyle(selection == tab ? Theme.ink : Theme.muted)
                        Rectangle().fill(selection == tab ? Theme.ink : .clear).frame(height: 2)
                    }
                    .fixedSize()
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }
}
