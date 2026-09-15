import SwiftUI

struct OtherMetricsScreen: View {
    private let entry = MetricCatalog.entry(for: "otherMetrics")

    var body: some View {
        List {
            Section {
                MetricScreenHeader(entry: entry)
            }
            .listRowBackground(HSPalette.surface)
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(HSPalette.bg)
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .reportsScreenState(entry.id)
    }
}

#Preview {
    NavigationStack { OtherMetricsScreen() }
}
