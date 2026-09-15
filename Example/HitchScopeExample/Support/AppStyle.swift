import SwiftUI

/// Dark-first tokens lifted directly from hitchscope-dashboard's
/// globals.css, so every screen in the Example app reads as the same
/// product as the dashboard/website rather than a generic system-styled
/// debug tool. Shared across the home list and every metric detail screen.
enum HSPalette {
    static let bg = Color(hex: 0x13_12_11)
    static let surface = Color(hex: 0x1c_1a_19)
    static let text = Color(hex: 0xf3_f2_f2)
    static let textSecondary = text.opacity(0.6)
    static let accent = Color(hex: 0xff_56_3c)
    static let divider = text.opacity(0.24)
}

extension Color {
    init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(HSPalette.accent)
            .tracking(1)
    }
}

/// One tappable row, styled flat (no native bordered-button chrome) to match
/// the dashboard's sharp-cornered, single-accent look. Reused across every
/// screen's trigger button(s) instead of repeating this styling at each call site.
struct TriggerRow: View {
    let title: String
    var subtitle: String? = nil
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .default, weight: .bold))
                    .foregroundStyle(
                        isDisabled
                            ? HSPalette.textSecondary
                            : (isDestructive ? HSPalette.accent : HSPalette.text))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(HSPalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .listRowBackground(HSPalette.surface)
    }
}
