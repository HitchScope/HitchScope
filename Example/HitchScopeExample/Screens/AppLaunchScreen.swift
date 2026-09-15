import SwiftUI

struct AppLaunchScreen: View {
    private let entry = MetricCatalog.entry(for: "appLaunch")

    @State private var slowLaunchArmed = SlowLaunchFlag.isArmed
    @State private var lastAction = "No action taken yet."

    var body: some View {
        List {
            Section {
                MetricScreenHeader(entry: entry)
            }
            .listRowBackground(HSPalette.surface)

            Section {
                TriggerRow(
                    title: slowLaunchArmed
                        ? "Armed — force-quit and relaunch now" : "Arm slow next launch (~3s stall)",
                    subtitle: "appLaunch fires for an unusually slow launch, not something a mid-session tap can produce.",
                    isDisabled: slowLaunchArmed
                ) {
                    SlowLaunchFlag.arm()
                    slowLaunchArmed = true
                    lastAction = "Armed a ~3s stall for the next app launch. Force-quit via the App Switcher, then relaunch."
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
    NavigationStack { AppLaunchScreen() }
}
