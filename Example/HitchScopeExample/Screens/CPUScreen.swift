import SwiftUI

struct CPUScreen: View {
    private let entry = MetricCatalog.entry(for: "cpu")

    @State private var isRunning = false
    @State private var lastAction = "No action taken yet."

    var body: some View {
        List {
            Section {
                MetricScreenHeader(entry: entry)
            }
            .listRowBackground(HSPalette.surface)

            Section {
                PerformanceToggleRow(
                    metricID: entry.id,
                    unfixedDescription: "Off: 4 unthrottled busy loops for ~60s.",
                    fixedDescription: "On: the same work at .utility QoS, yielding periodically - much less CPU pressure."
                )
                .listRowBackground(HSPalette.surface)

                TriggerRow(
                    title: isRunning ? "Running CPU workload (~60s)…" : "Run CPU-busy workload (~60s)",
                    subtitle: "Sets fixture state, then feeds cpuException if an undocumented threshold is crossed; always contributes to cpuTime/cpuInstructionsCount.",
                    isDisabled: isRunning
                ) {
                    ReproducibleState.set()
                    isRunning = true
                    let lowImpact = PerformanceToggle(metricID: entry.id).isOn
                    lastAction =
                        lowImpact
                        ? "Running the low-impact CPU workload for ~60s…"
                        : "Running 4 concurrent CPU-busy loops for ~60s…"
                    Workloads.runCPUBusyWorkload(lowImpact: lowImpact) {
                        isRunning = false
                        lastAction = "CPU workload finished."
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
        .onAppear { PerformanceToggle(metricID: entry.id).reportCurrentState() }
    }
}

#Preview {
    NavigationStack { CPUScreen() }
}
