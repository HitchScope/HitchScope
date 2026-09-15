import SwiftUI

/// Shared header for every metric detail screen: long-form description,
/// a fields/units table, and a reproducibility note - rendered from the
/// catalog entry so this text lives in exactly one place (MetricCatalog).
struct MetricScreenHeader: View {
    let entry: MetricCatalogEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(entry.overview)
                .font(.callout)
                .foregroundStyle(HSPalette.text)

            VStack(alignment: .leading, spacing: 6) {
                SectionHeader(title: "Fields & units")
                ForEach(entry.fields, id: \.self) { field in
                    VStack(alignment: .leading, spacing: 1) {
                        HStack(alignment: .firstTextBaseline, spacing: 6) {
                            Text(field.name)
                                .font(.system(.caption, design: .monospaced, weight: .bold))
                                .foregroundStyle(HSPalette.text)
                            Text("(\(field.unit))")
                                .font(.caption2)
                                .foregroundStyle(HSPalette.accent)
                        }
                        Text(field.source)
                            .font(.caption2)
                            .foregroundStyle(HSPalette.textSecondary)
                    }
                }
            }

            VStack(alignment: .leading, spacing: 4) {
                SectionHeader(title: entry.isReproducible ? "How to reproduce" : "Why this isn't reproducible")
                Text(entry.reproducibilityNote)
                    .font(.caption)
                    .foregroundStyle(HSPalette.textSecondary)
            }
        }
        .padding(.vertical, 4)
    }
}
