import SwiftUI

struct DiskWritesScreen: View {
    private let entry = MetricCatalog.entry(for: "diskWrites")

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
                    unfixedDescription: "Off: a tight loop of 1MB chunk writes for ~60s.",
                    fixedDescription: "On: larger, throttled writes over the same duration - far fewer, less bursty syscalls."
                )
                .listRowBackground(HSPalette.surface)

                TriggerRow(
                    title: isRunning ? "Running disk-write workload (~60s)…" : "Run disk-write workload (~60s)",
                    subtitle: "Sets fixture state, then feeds diskWriteException if an undocumented threshold is crossed - not guaranteed.",
                    isDisabled: isRunning
                ) {
                    ReproducibleState.set()
                    isRunning = true
                    let throttled = PerformanceToggle(metricID: entry.id).isOn
                    lastAction = "Writing to a scratch file for ~60s…"
                    Workloads.runDiskWriteWorkload(throttled: throttled) {
                        isRunning = false
                        lastAction = "Disk-write workload finished, scratch file removed."
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
    NavigationStack { DiskWritesScreen() }
}
