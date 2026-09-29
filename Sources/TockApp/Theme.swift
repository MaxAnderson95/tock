import AppKit
import SwiftUI

// Ink on blue-black. Ink is the normal state; ember means a code is about to expire; mint confirms a copy.
enum Palette {
    static let ground = dynamic(light: 0xeef1f6, dark: 0x0f131b)
    static let panel = dynamic(light: 0xfafbfd, dark: 0x151b26)
    static let raised = dynamic(light: 0xffffff, dark: 0x1c2331)
    static let pill = dynamic(light: 0xffffff, dark: 0x2b3448)
    static let ink = dynamic(light: 0x121826, dark: 0xe7ebf3)
    static let dust = dynamic(light: 0x5b6577, dark: 0x8b95a8)
    static let line = dynamic(light: 0x121826, dark: 0xe7ebf3, alpha: 0.1)
    static let spent = dynamic(light: 0x121826, dark: 0xe7ebf3, alpha: 0.15)
    static let wash = dynamic(light: 0x121826, dark: 0xe7ebf3, alpha: 0.05)
    static let ember = dynamic(light: 0xd23f1a, dark: 0xff6e4a)
    static let mint = dynamic(light: 0x1f7a52, dark: 0x5fd49a)

    /// Monogram tints in list order, so neighboring services never share a color and six services use all six.
    static let tints = [
        dynamic(light: 0x3d6fd9, dark: 0x7aa2ff), dynamic(light: 0xc2651c, dark: 0xffa061),
        dynamic(light: 0x1f7a52, dark: 0x5fd49a), dynamic(light: 0x7b4fd6, dark: 0xb39bff),
        dynamic(light: 0xc2407e, dark: 0xff8fc4), dynamic(light: 0x9a7b0a, dark: 0xf2d25c),
    ]

    /// The tint for the service at `position` in the full, unfiltered list, so filtering does not recolor rows.
    static func tint(at position: Int) -> Color { tints[position % tints.count] }

    private static func dynamic(light: Int, dark: Int, alpha: CGFloat = 1) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
            return NSColor(srgbRed: CGFloat(hex >> 16) / 255, green: CGFloat((hex >> 8) & 255) / 255, blue: CGFloat(hex & 255) / 255, alpha: alpha)
        })
    }
}

extension Font {
    static func readout(_ size: CGFloat, weight: Font.Weight = .semibold) -> Font {
        .system(size: size, weight: weight).width(.expanded).monospacedDigit()
    }
}

/// The issuer's first letter on a soft tint.
struct Monogram: View {
    let issuer: String
    let tint: Color
    var size: CGFloat = 30
    var body: some View {
        Text(issuer.first.map { String($0).uppercased() } ?? "?")
            .font(.system(size: size * 0.46, weight: .bold, design: .rounded))
            .foregroundStyle(tint)
            .frame(width: size, height: size)
            .background(tint.opacity(0.14), in: RoundedRectangle(cornerRadius: size * 0.3))
            .accessibilityHidden(true)
    }
}

/// The share of the current code's lifetime left, drawn as a closing ring with the seconds inside.
struct CountdownRing: View {
    let remaining: TimeInterval
    let period: Int
    var size: CGFloat = 24
    var body: some View {
        let urgent = remaining <= 5
        ZStack {
            Circle().stroke(Palette.spent, lineWidth: 2.25)
            Circle().trim(from: 0, to: remaining / Double(period))
                .stroke(urgent ? Palette.ember : Palette.ink, style: StrokeStyle(lineWidth: 2.25, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text("\(Int(remaining.rounded(.up)))")
                .font(.system(size: size * (period >= 100 ? 0.3 : 0.38), weight: .bold).monospacedDigit())
                .foregroundStyle(urgent ? Palette.ember : Palette.dust)
        }
        .frame(width: size, height: size)
        .accessibilityElement()
        .accessibilityLabel("\(Int(remaining.rounded(.up))) seconds left")
    }
}

extension View {
    /// A dimmed prompt drawn over an empty field. SwiftUI prompts on macOS take the ink foreground and read as typed text.
    func placeholder(_ text: String, shown: Bool) -> some View {
        overlay(alignment: .leading) {
            if shown { Text(text).foregroundStyle(Palette.dust.opacity(0.75)).lineLimit(1).allowsHitTesting(false) }
        }
    }
}

/// Splits a code in half so it reads like "123 456".
func grouped(_ code: String) -> String {
    let split = code.index(code.startIndex, offsetBy: code.count / 2)
    return "\(code[..<split]) \(code[split...])"
}

/// Presses shrink slightly and spring back.
struct PressableStyle: ButtonStyle {
    var pressedScale: CGFloat = 0.95
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? pressedScale : 1)
            .animation(.spring(duration: 0.22, bounce: 0.45), value: configuration.isPressed)
    }
}

struct QuietButtonStyle: ButtonStyle {
    var prominent = false
    var destructive = false
    @Environment(\.isEnabled) private var enabled
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 12, weight: .semibold))
            .padding(.horizontal, 12).frame(minHeight: 26)
            .foregroundStyle(prominent ? Palette.ground : destructive ? Palette.ember : Palette.ink)
            .background(prominent ? AnyShapeStyle(Palette.ink) : AnyShapeStyle(configuration.isPressed ? Palette.spent : Palette.wash), in: Capsule())
            .overlay { if !prominent { Capsule().strokeBorder(Palette.line) } }
            .opacity(enabled ? (configuration.isPressed && prominent ? 0.85 : 1) : 0.4)
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.22, bounce: 0.45), value: configuration.isPressed)
            .contentShape(Capsule())
    }
}

struct IconButton: View {
    let symbol: String
    let label: String
    let action: () -> Void
    @State private var hovering = false
    var body: some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 12, weight: .semibold))
                .frame(width: 26, height: 26)
                .background(hovering ? Palette.spent : Palette.wash, in: Circle())
                .contentShape(Circle())
                .animation(.easeOut(duration: 0.15), value: hovering)
        }.buttonStyle(PressableStyle()).help(label).accessibilityLabel(label).onHover { hovering = $0 }
    }
}

/// A switch in Tock's palette whose thumb springs across.
struct TockSwitch: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: 10) {
            configuration.label
            Spacer(minLength: 0)
            Capsule().fill(configuration.isOn ? Palette.mint : Palette.spent)
                .frame(width: 36, height: 21)
                .overlay(alignment: configuration.isOn ? .trailing : .leading) {
                    Circle().fill(.white).shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
                        .frame(width: 17, height: 17).padding(2)
                }
                .animation(.spring(duration: 0.32, bounce: 0.35), value: configuration.isOn)
                .contentShape(Capsule())
                .onTapGesture { configuration.isOn.toggle() }
        }
        .accessibilityRepresentation { Toggle(isOn: configuration.$isOn) { configuration.label } }
    }
}

/// A slim field in the panel style, used by the settings forms.
struct PanelField<Field: View>: View {
    let label: String
    @ViewBuilder let field: Field
    var body: some View {
        HStack(spacing: 12) {
            Text(label).font(.system(size: 12, weight: .medium)).foregroundStyle(Palette.dust).frame(width: 84, alignment: .leading)
            field
                .textFieldStyle(.plain)
                .padding(.horizontal, 10).frame(height: 30)
                .background(Palette.raised, in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(Palette.line))
        }
    }
}

struct Panel<Content: View>: View {
    let title: String
    var footer: String? = nil
    @ViewBuilder let content: Content
    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            Text(title).font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.dust).padding(.leading, 4)
            VStack(alignment: .leading, spacing: 0) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Palette.panel, in: RoundedRectangle(cornerRadius: 14))
                .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(Palette.line))
            if let footer {
                Text(footer).font(.system(size: 11)).foregroundStyle(Palette.dust).padding(.horizontal, 4).fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
