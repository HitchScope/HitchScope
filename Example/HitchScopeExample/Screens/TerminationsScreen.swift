import SwiftUI

struct TerminationsScreen: View {
    private let entry = MetricCatalog.entry(for: "terminations")

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
    NavigationStack { TerminationsScreen() }
}
