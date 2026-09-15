import SwiftUI

struct NetworkScreen: View {
    private let entry = MetricCatalog.entry(for: "network")

    @State private var lastAction = "No action taken yet."

    var body: some View {
        List {
            Section {
                MetricScreenHeader(entry: entry)
            }
            .listRowBackground(HSPalette.surface)

            Section {
                TriggerRow(
                    title: "Run network workload (GET ~5MB + POST ~2MB)",
                    subtitle: "Sets fixture state, then a real round-trip against httpbin.org."
                ) {
                    ReproducibleState.set()
                    lastAction = "Running a real network GET + POST against httpbin.org…"
                    Workloads.runNetworkWorkload {
                        lastAction = "Network workload finished."
                    }
                }
                Text(lastAction)
                    .font(.caption2)
                    .foregroundStyle(HSPalette.textSecondary)
                    .listRowBackground(HSPalette.surface)
            } header: {
                SectionHeader(title: "Try it")
            }
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
    NavigationStack { NetworkScreen() }
}
