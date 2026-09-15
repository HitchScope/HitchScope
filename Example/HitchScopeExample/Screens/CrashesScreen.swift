import SwiftUI

struct CrashesScreen: View {
    private let entry = MetricCatalog.entry(for: "crashes")

    var body: some View {
        List {
            Section {
                MetricScreenHeader(entry: entry)
            }
            .listRowBackground(HSPalette.surface)

            Section {
                TriggerRow(
                    title: "Trigger crash",
                    subtitle: "Sets fixture state, then terminates immediately - check for a new fixture after relaunching.",
                    isDestructive: true
                ) {
                    ReproducibleState.set()
                    // fatalError terminates synchronously - there's no
                    // chance to update any status text afterward.
                    fatalError("HitchScope Example: deliberate crash trigger")
                }
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
    NavigationStack { CrashesScreen() }
}
