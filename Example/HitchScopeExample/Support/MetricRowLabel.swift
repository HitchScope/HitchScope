import SwiftUI

/// Home-list row for one catalog entry: icon, title, one-line summary, plus
/// a trailing badge when the metric has an A/B toggle or is reference-only.
struct MetricRowLabel: View {
    let entry: MetricCatalogEntry

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: entry.symbolName)
                .foregroundStyle(HSPalette.accent)
                .frame(width: 20)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.title)
                    .font(.system(.body, design: .default, weight: .bold))
                    .foregroundStyle(HSPalette.text)
                Text(entry.summary)
                    .font(.caption2)
                    .foregroundStyle(HSPalette.textSecondary)
            }
            Spacer()
            if entry.hasPerformanceToggle {
                badge("A/B")
            } else if !entry.isReproducible {
                badge("REFERENCE")
            }
        }
        .padding(.vertical, 2)
        .listRowBackground(HSPalette.surface)
    }

    private func badge(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(HSPalette.accent)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(HSPalette.accent, lineWidth: 1))
    }
}
