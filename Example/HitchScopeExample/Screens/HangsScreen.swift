import SwiftUI

struct HangsScreen: View {
    private let entry = MetricCatalog.entry(for: "hangs")

    @State private var hangDuration: Double = 2
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
                    unfixedDescription: "Off: blocks the main thread synchronously - a real hang.",
                    fixedDescription: "On: the same work runs on a background queue instead - no hang."
                )
                .listRowBackground(HSPalette.surface)

                Picker("Hang duration", selection: $hangDuration) {
                    Text("2s").tag(2.0)
                    Text("10s").tag(10.0)
                }
                .pickerStyle(.segmented)
                .listRowBackground(HSPalette.surface)

                TriggerRow(
                    title: "Trigger hang",
                    subtitle: "Sets fixture state, then blocks (or backgrounds) for the chosen duration."
                ) {
                    ReproducibleState.set()
                    let duration = hangDuration
                    if PerformanceToggle(metricID: entry.id).isOn {
                        lastAction =
                            "Fixed: running the \(Int(duration))s stall on a background queue - main thread stays responsive."
                        DispatchQueue.global(qos: .userInitiated).async {
                            Thread.sleep(forTimeInterval: duration)
                        }
                    } else {
                        lastAction = "Blocking the main thread for \(Int(duration))s…"
                        Thread.sleep(forTimeInterval: duration)
                        lastAction =
                            "Hang triggered. Unlike crash/memory, a hang diagnostic hasn't been confirmed to arrive through this pipeline yet."
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
    NavigationStack { HangsScreen() }
}
