import SwiftUI
import HitchScope
import OSLog

private let domain = "com.hitchscope.example.screen"
private let experimentDomain = "com.hitchscope.example.experiment.checkout_redesign"

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

/// Same path `MetricKitBridge` writes captured fixtures to (duplicated, not
/// shared as SDK API - this capture mechanism is temporary scaffolding, see
/// the MetricKit fixture-test-harness plan).
private let fixturesDirectory =
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("HitchScopeFixtures", isDirectory: true)

private func fetchCapturedFixtureURLs() -> [URL] {
    (try? FileManager.default.contentsOfDirectory(
        at: fixturesDirectory, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles])) ?? []
}

struct ContentView: View {
    @State private var lastAction: String = "No action taken yet."
    @State private var logLines: [String] = []
    @State private var capturedFixtureURLs: [URL] = []
    @State private var cartItems: Int = 0
    @State private var hangDuration: Double = 2
    @State private var slowLaunchArmed: Bool = SlowLaunchFlag.isArmed
    @State private var isRunningCPUWorkload = false
    @State private var isRunningDiskWorkload = false
    @State private var showingGPUBusy = false
    @State private var showingScrollJank = false

    private func refreshLogLines() {
        Task.detached {
            let lines = fetchSDKLogLines()
            let fixtureURLs = fetchCapturedFixtureURLs()
            await MainActor.run {
                logLines = lines
                capturedFixtureURLs = fixtureURLs
            }
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            Text("HitchScope Example")
                .font(.headline)
            Text("Used for exercising SDK changes against the real MetricKit/StateReporting pipeline on a device. In testing, crash/memory diagnostics have shown up within under a minute of relaunching; a hang diagnostic hasn't been confirmed to arrive yet. Metric aggregates (hitch ratio, etc.) deliver in a daily report.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            VStack(spacing: 4) {
                Text(
                    capturedFixtureURLs.isEmpty
                        ? "No fixtures captured yet"
                        : "Captured fixtures: \(capturedFixtureURLs.count)"
                )
                .font(.caption2)
                .foregroundStyle(capturedFixtureURLs.isEmpty ? Color.gray : Color.green)
                if !capturedFixtureURLs.isEmpty {
                    ShareLink(items: capturedFixtureURLs) {
                        Label("Share fixtures", systemImage: "square.and.arrow.up")
                    }
                    .font(.caption2)
                }
            }
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
            }
            .buttonStyle(.borderedProminent)

            // Domains are independent - this one tracks an A/B experiment
            // variant, simultaneously with whatever's active on `domain`
            // above. Neither is privileged; MetricKit attaches both to
            // every diagnostic/metric report at once.
            VStack(spacing: 8) {
                Button("Report experiment: variant_b") {
                    HitchScope.reportState(experimentDomain, label: "variant_b")
                    lastAction = "Reported state \"variant_b\" on \(experimentDomain)"
                }
                Button("Report state: home (with stableMetadata)") {
                    // Stable metadata is part of the state's identity, not
                    // just extra context - a different userTier here is a
                    // new transition even though the label is still "home".
                    HitchScope.reportState(
                        domain, label: "home", stableMetadata: ["userTier": .init("premium")])
                    lastAction = "Reported state \"home\" on \(domain) with stableMetadata"
                }
                Button("Update cart items metadata (+1)") {
                    // Updates volatile metadata on whatever state is
                    // currently active on `domain`, without starting a new
                    // transition - calling reportState again here instead
                    // would no-op if the label/stableMetadata didn't also
                    // change, silently dropping this update.
                    cartItems += 1
                    HitchScope.updateVolatileMetadata(domain, ["cartItems": .init(cartItems)])
                    lastAction = "Updated volatile metadata cartItems=\(cartItems) on \(domain)"
                }
            }
            .buttonStyle(.borderedProminent)

            VStack(spacing: 8) {
                // A 2s hang has never actually produced a real hang
                // diagnostic in testing (unlike crash/memory, confirmed
                // within a minute) - offering a longer duration too, since
                // Apple's own hang-severity buckets go well past 2s.
                Picker("Hang duration", selection: $hangDuration) {
                    Text("2s").tag(2.0)
                    Text("10s").tag(10.0)
                }
                .pickerStyle(.segmented)
                Button("Trigger main-thread hang", role: .destructive) {
                    let duration = hangDuration
                    lastAction =
                        "Blocking the main thread for \(Int(duration))s to trigger a real MetricKit hang diagnostic…"
                    // Deliberately synchronous on the main thread — this is
                    // how you produce a genuine MXHangDiagnostic on device;
                    // there's no way to fake one via the SDK's own API.
                    Thread.sleep(forTimeInterval: duration)
                    lastAction =
                        "Hang triggered. Unlike crash/memory (confirmed within a minute of relaunching in testing), a hang diagnostic hasn't been confirmed to arrive through this pipeline yet - no known timing to expect."
                }
            }
            .buttonStyle(.borderedProminent)

            VStack(spacing: 8) {
                Text(
                    "appLaunch fires for an unusually slow launch - can't be triggered mid-session. Arm this, then force-quit and relaunch the app."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                Button(slowLaunchArmed ? "Armed — force-quit and relaunch now" : "Arm slow next launch (~3s stall)") {
                    SlowLaunchFlag.arm()
                    slowLaunchArmed = true
                    lastAction = "Armed a ~3s stall for the next app launch. Force-quit via the App Switcher, then relaunch."
                }
                .disabled(slowLaunchArmed)
            }
            .buttonStyle(.borderedProminent)

            VStack(spacing: 8) {
                Text(
                    "cpuException/diskWriteException fire only if an undocumented Apple threshold is crossed - not guaranteed. cpuTime/cpuInstructionsCount always get real contributed work either way."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                Button(isRunningCPUWorkload ? "Running CPU workload (~60s)…" : "Run CPU-busy workload (~60s)") {
                    isRunningCPUWorkload = true
                    lastAction = "Running 4 concurrent CPU-busy loops for ~60s…"
                    Workloads.runCPUBusyWorkload {
                        isRunningCPUWorkload = false
                        lastAction = "CPU-busy workload finished."
                    }
                }
                .disabled(isRunningCPUWorkload)
                Button(
                    isRunningDiskWorkload ? "Running disk-write workload (~60s)…" : "Run disk-write workload (~60s)"
                ) {
                    isRunningDiskWorkload = true
                    lastAction = "Writing to a scratch file for ~60s…"
                    Workloads.runDiskWriteWorkload {
                        isRunningDiskWorkload = false
                        lastAction = "Disk-write workload finished, scratch file removed."
                    }
                }
                .disabled(isRunningDiskWorkload)
            }
            .buttonStyle(.borderedProminent)

            VStack(spacing: 8) {
                Button("Spike peak memory (~300MB, held 2s)") {
                    lastAction = "Allocating a bounded ~300MB spike, held for 2s…"
                    Workloads.runPeakMemorySpike {
                        lastAction = "Peak memory spike released."
                    }
                }
                Button("Run network workload (GET ~5MB + POST ~2MB)") {
                    lastAction = "Running a real network GET + POST against httpbin.org…"
                    Workloads.runNetworkWorkload {
                        lastAction = "Network workload finished."
                    }
                }
            }
            .buttonStyle(.borderedProminent)

            VStack(spacing: 8) {
                Text(
                    "gpuTime/hitchTime are continuous daily aggregates - stay on these screens and interact for a couple minutes each for the data to matter."
                )
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                Button("GPU Busy") { showingGPUBusy = true }
                Button("Scroll Jank") { showingScrollJank = true }
            }
            .buttonStyle(.borderedProminent)

            VStack(spacing: 8) {
                Text("These terminate the app immediately — the diagnostic only shows up after you relaunch, not before.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                Button("Trigger crash", role: .destructive) {
                    // fatalError terminates synchronously - lastAction would
                    // never get a chance to render, so the warning above is
                    // static instead of a status update like the other buttons.
                    fatalError("HitchScope Example: deliberate crash trigger")
                }
                Button("Trigger memory exception", role: .destructive) {
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
                Button("Refresh") { refreshLogLines() }
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
        .onAppear { refreshLogLines() }
        // The log store doesn't push updates, so poll while this view is
        // visible rather than trying to observe it — simplest option for a
        // dev-only debug view. fetchSDKLogLines() does real OSLogStore I/O,
        // so it's dispatched off the main thread — running it inline here
        // every 1.5s was stalling the UI the whole time this view is up,
        // independent of the hang button.
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            refreshLogLines()
        }
        .sheet(isPresented: $showingGPUBusy) { GPUBusyView() }
        .sheet(isPresented: $showingScrollJank) { ScrollJankView() }
    }
}

#Preview {
    ContentView()
}
