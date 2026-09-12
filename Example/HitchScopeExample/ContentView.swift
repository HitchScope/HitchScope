import SwiftUI
import HitchScope
import OSLog

private let domain = "com.hitchscope.example.screen"

/// Reads back the SDK's own `os_log` output (subsystem "com.hitchscope.sdk")
/// from this process's log store, so the SDK's diagnostic/metric/flush
/// activity is visible on-device without needing Console.app on a Mac.
/// `.currentProcessIdentifier` scope needs no special entitlement.
private func fetchSDKLogLines() -> [String] {
    guard let store = try? OSLogStore(scope: .currentProcessIdentifier) else { return [] }
    let position = store.position(timeIntervalSinceEnd: -600)
    guard let entries = try? store.getEntries(at: position) else { return [] }

    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss"

    return entries.compactMap { entry -> String? in
        guard let logEntry = entry as? OSLogEntryLog, logEntry.subsystem == "com.hitchscope.sdk"
        else { return nil }
        let level = logEntry.level == .error ? "ERROR" : "INFO"
        return "\(formatter.string(from: entry.date)) [\(level)] \(logEntry.composedMessage)"
    }
}

struct ContentView: View {
    @State private var lastAction: String = "No action taken yet."
    @State private var logLines: [String] = []

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

            HStack {
                Text("SDK log (com.hitchscope.sdk)")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Refresh") { logLines = fetchSDKLogLines() }
                    .font(.caption2)
            }
            .padding(.horizontal)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.contains("[ERROR]") ? .red : .primary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                    .padding(.horizontal)
                }
                .onChange(of: logLines.count) {
                    guard let last = logLines.indices.last else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .frame(maxHeight: .infinity)
            .background(.black.opacity(0.05))
        }
        .padding()
        .onAppear { logLines = fetchSDKLogLines() }
        // The log store doesn't push updates, so poll while this view is
        // visible rather than trying to observe it — simplest option for a
        // dev-only debug view.
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            logLines = fetchSDKLogLines()
        }
    }
}

#Preview {
    ContentView()
}
