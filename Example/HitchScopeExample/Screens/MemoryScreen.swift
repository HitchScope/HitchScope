import SwiftUI

struct MemoryScreen: View {
    private let entry = MetricCatalog.entry(for: "memory")

    @State private var lastAction = "No action taken yet."

    var body: some View {
        List {
            Section {
                MetricScreenHeader(entry: entry)
            }
            .listRowBackground(HSPalette.surface)

            Section {
                TriggerRow(
                    title: "Trigger memory exception",
                    subtitle: "Sets fixture state, then allocates until the OS jetsam-kills the process - check after relaunching.",
                    isDestructive: true
                ) {
                    ReproducibleState.set()
                    lastAction =
                        "Allocating memory until the OS terminates the app — relaunch afterward to check for a memory exception diagnostic."
                    // Off the main thread so this reads as memory pressure,
                    // not another main-thread hang - the OS jetsam-kills the
                    // process once it exceeds its memory limit.
                    DispatchQueue.global(qos: .userInitiated).async {
                        var blocks: [[UInt8]] = []
                        while true {
                            blocks.append([UInt8](repeating: 0xFF, count: 50_000_000))
                        }
                    }
                }
                TriggerRow(
                    title: "Spike peak memory (~300MB, held 2s)",
                    subtitle: "Sets fixture state, then a bounded single spike - can set today's peakMemory without risking a jetsam kill."
                ) {
                    ReproducibleState.set()
                    lastAction = "Allocating a bounded ~300MB spike, held for 2s…"
                    Workloads.runPeakMemorySpike {
                        lastAction = "Peak memory spike released."
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
    NavigationStack { MemoryScreen() }
}
