import SwiftUI

/// Deliberate per-row synchronous stalls during scrolling, gated by an A/B
/// toggle. `hitchTime` is a continuous daily ratio, not a discrete trigger,
/// so this only ever *contributes* real jank - actually scroll up and down
/// repeatedly for it to matter, don't just load the screen once.
struct ScrollHitchesScreen: View {
    private let entry = MetricCatalog.entry(for: "scrollHitches")

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
                    MetricScreenHeader(entry: entry)
                    PerformanceToggleRow(
                        metricID: entry.id,
                        unfixedDescription: "Off: every 5th row stalls the main thread for 40ms as it appears.",
                        fixedDescription: "On: no stall - scrolling should feel smooth."
                    )
                }
                .padding()
            }
            .frame(maxHeight: 260)
            .background(HSPalette.surface)

            List(0..<200, id: \.self) { i in
                Text("Row \(i)")
                    .foregroundStyle(HSPalette.text)
                    .listRowBackground(HSPalette.surface)
                    .onAppear {
                        guard i % 5 == 0, !PerformanceToggle(metricID: entry.id).isOn else { return }
                        // Deliberate synchronous stall on the main thread
                        // while scrolling - this is what real jank looks
                        // like to MetricKit.
                        Thread.sleep(forTimeInterval: 0.04)
                    }
            }
            .listStyle(.plain)
            .scrollContentBackground(.hidden)
        }
        .background(HSPalette.bg.ignoresSafeArea())
        .navigationTitle(entry.title)
        .navigationBarTitleDisplayMode(.inline)
        .reportsScreenState(entry.id)
        .onAppear {
            ReproducibleState.set()
            PerformanceToggle(metricID: entry.id).reportCurrentState()
        }
    }
}

#Preview {
    NavigationStack { ScrollHitchesScreen() }
}
