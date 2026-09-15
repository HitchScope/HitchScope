import SwiftUI
import HitchScope

private let demoDomain = "com.hitchscope.example.demo"
private let demoExperimentDomain = "com.hitchscope.example.experiment.demo"

/// Demonstrates the raw State Reporting API on its own domain(s), separate
/// from the screen domain every metric screen auto-reports via
/// `reportsScreenState` - poking the screen domain manually here would
/// fight with that automatic reporting. Deliberately does NOT apply
/// `reportsScreenState` itself, since auto-tagging the screen that teaches
/// manual tagging would be circular.
struct StateReportingScreen: View {
    @State private var cartItems = 0
    @State private var lastAction = "No action taken yet."

    var body: some View {
        List {
            Section {
                Text(
                    "The State Reporting API lets you report what's happening in your app on any domain you declare - a screen, an A/B experiment variant, a heavy subsystem, anything. Domains are independent: each has its own current label, tracked simultaneously. Every trigger on the metric screens already sets its own fixture state first - these buttons are only for exploring the API on its own."
                )
                .font(.callout)
                .foregroundStyle(HSPalette.text)
            }
            .listRowBackground(HSPalette.surface)

            Section {
                TriggerRow(title: "Report state: home") {
                    HitchScope.reportState(demoDomain, label: "home")
                    lastAction = "Reported state \"home\" on \(demoDomain)"
                }
                TriggerRow(title: "Report state: detail") {
                    HitchScope.reportState(demoDomain, label: "detail")
                    lastAction = "Reported state \"detail\" on \(demoDomain)"
                }
                TriggerRow(title: "Clear state") {
                    HitchScope.reportState(demoDomain, label: nil)
                    lastAction = "Cleared state on \(demoDomain)"
                }
                TriggerRow(
                    title: "Report state: home (with stableMetadata)",
                    subtitle: "Stable metadata is part of the state's identity - a new userTier is a new transition"
                ) {
                    HitchScope.reportState(
                        demoDomain, label: "home", stableMetadata: ["userTier": .init("premium")])
                    lastAction = "Reported state \"home\" on \(demoDomain) with stableMetadata"
                }
                TriggerRow(
                    title: "Update cart items metadata (+1)",
                    subtitle: "cartItems=\(cartItems) - updates volatile metadata without starting a new transition"
                ) {
                    cartItems += 1
                    HitchScope.updateVolatileMetadata(demoDomain, ["cartItems": .init(cartItems)])
                    lastAction = "Updated volatile metadata cartItems=\(cartItems) on \(demoDomain)"
                }
                // A second, independent domain - demonstrates that domains
                // don't share a privileged slot; MetricKit attaches both to
                // every diagnostic/metric report at once.
                TriggerRow(title: "Report experiment: variant_b") {
                    HitchScope.reportState(demoExperimentDomain, label: "variant_b")
                    lastAction = "Reported state \"variant_b\" on \(demoExperimentDomain)"
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
        .navigationTitle("State Reporting API")
        .navigationBarTitleDisplayMode(.inline)
    }
}

#Preview {
    NavigationStack { StateReportingScreen() }
}
