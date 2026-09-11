import SwiftUI
import HitchScope

private let domain = "com.hitchscope.example.screen"

struct ContentView: View {
    @State private var lastAction: String = "No action taken yet."

    var body: some View {
        VStack(spacing: 16) {
            Text("HitchScope Example")
                .font(.headline)
            Text("Used for exercising SDK changes against the real MetricKit/StateReporting pipeline on a device. Diagnostics (crash/hang/launch/memory) deliver immediately after an incident; metric aggregates (hitch ratio, etc.) deliver in a daily report.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 8) {
                Button("Report state: home") {
                    HitchScope.reportState(domain, label: "home")
                    lastAction = "Reported state \"home\" on \(domain)"
                }
                Button("Report state: detail") {
                    HitchScope.reportState(domain, label: "detail")
                    lastAction = "Reported state \"detail\" on \(domain)"
                }
                Button("Clear state") {
                    HitchScope.reportState(domain, label: nil)
                    lastAction = "Cleared state on \(domain)"
                }
                Button("Trigger 2s main-thread hang", role: .destructive) {
                    lastAction = "Blocking the main thread for 2s to trigger a real MetricKit hang diagnostic…"
                    // Deliberately synchronous on the main thread — this is
                    // how you produce a genuine MXHangDiagnostic on device;
                    // there's no way to fake one via the SDK's own API.
                    Thread.sleep(forTimeInterval: 2)
                    lastAction = "Hang triggered. Diagnostic report delivery is async and may take a moment."
                }
            }
            .buttonStyle(.borderedProminent)

            Text(lastAction)
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Text("Watch Console.app on your Mac, subsystem \"com.hitchscope.sdk\", to see what the SDK actually does with these.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
        }
        .padding()
    }
}

#Preview {
    ContentView()
}
