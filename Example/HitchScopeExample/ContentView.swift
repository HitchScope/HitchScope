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

/// Dark-first tokens lifted directly from hitchscope-dashboard's
/// globals.css, so the Example app reads as the same product as the
/// dashboard/website rather than a generic system-styled debug tool.
private enum HSPalette {
    static let bg = Color(hex: 0x13_12_11)
    static let surface = Color(hex: 0x1c_1a_19)
    static let text = Color(hex: 0xf3_f2_f2)
    static let textSecondary = text.opacity(0.6)
    static let accent = Color(hex: 0xff_56_3c)
    static let divider = text.opacity(0.24)
}

extension Color {
    fileprivate init(hex: UInt32) {
        self.init(
            red: Double((hex >> 16) & 0xFF) / 255,
            green: Double((hex >> 8) & 0xFF) / 255,
            blue: Double(hex & 0xFF) / 255)
    }
}

private struct SectionHeader: View {
    let title: String

    var body: some View {
        Text(title.uppercased())
            .font(.system(.caption2, design: .monospaced, weight: .bold))
            .foregroundStyle(HSPalette.accent)
            .tracking(1)
    }
}

/// One tappable row, styled flat (no native bordered-button chrome) to match
/// the dashboard's sharp-cornered, single-accent look. Reused across ~15
/// near-identical triggers instead of repeating this styling at each call site.
private struct TriggerRow: View {
    let title: String
    var subtitle: String? = nil
    var isDestructive: Bool = false
    var isDisabled: Bool = false
    let action: () -> Void

    var body: some View {
        Button(role: isDestructive ? .destructive : nil, action: action) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(.body, design: .default, weight: .bold))
                    .foregroundStyle(
                        isDisabled
                            ? HSPalette.textSecondary
                            : (isDestructive ? HSPalette.accent : HSPalette.text))
                if let subtitle {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundStyle(HSPalette.textSecondary)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
        .listRowBackground(HSPalette.surface)
    }
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

    /// Fixed values (a label the State & Metadata buttons never use, and a
    /// constant cartItems rather than that section's ever-incrementing
    /// counter) so every problem trigger below always starts from the exact
    /// same state/metadata, regardless of what was tapped before it - no
    /// need to guess which State & Metadata button to tap first.
    private func setReproducibleState() {
        HitchScope.reportState(domain, label: "checkout", stableMetadata: ["userTier": .init("premium")])
        HitchScope.updateVolatileMetadata(domain, ["cartItems": .init(3)])
        HitchScope.reportState(experimentDomain, label: "variant_b")
    }

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
        NavigationStack {
            VStack(spacing: 0) {
                Text(
                    "Used for exercising SDK changes against the real MetricKit/StateReporting pipeline on a device. Diagnostics (crash/memory/hang/appLaunch/cpuException/diskWriteException) are discrete incidents; metrics are continuous daily aggregates that only show up in tomorrow's report."
                )
                .font(.caption)
                .foregroundStyle(HSPalette.textSecondary)
                .multilineTextAlignment(.leading)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(HSPalette.surface)

                List {
                    Section {
                        HStack {
                            Text(
                                capturedFixtureURLs.isEmpty
                                    ? "No fixtures captured yet"
                                    : "Captured fixtures: \(capturedFixtureURLs.count)"
                            )
                            .font(.caption)
                            .foregroundStyle(
                                capturedFixtureURLs.isEmpty ? HSPalette.textSecondary : HSPalette.accent)
                            Spacer()
                            if !capturedFixtureURLs.isEmpty {
                                ShareLink(items: capturedFixtureURLs) {
                                    Label("Share", systemImage: "square.and.arrow.up")
                                }
                                .font(.caption2)
                                .foregroundStyle(HSPalette.accent)
                            }
                        }
                        .listRowBackground(HSPalette.surface)
                    } header: {
                        SectionHeader(title: "Fixtures")
                    }

                    Section {
                        TriggerRow(title: "Report state: home") {
                            HitchScope.reportState(domain, label: "home")
                            lastAction = "Reported state \"home\" on \(domain)"
                        }
                        TriggerRow(title: "Report state: detail") {
                            HitchScope.reportState(domain, label: "detail")
                            lastAction = "Reported state \"detail\" on \(domain)"
                        }
                        TriggerRow(title: "Clear state") {
                            HitchScope.reportState(domain, label: nil)
                            lastAction = "Cleared state on \(domain)"
                        }
                        // Domains are independent - this one tracks an A/B
                        // experiment variant, simultaneously with whatever's
                        // active on `domain` above. Neither is privileged;
                        // MetricKit attaches both to every diagnostic/metric
                        // report at once.
                        TriggerRow(title: "Report experiment: variant_b") {
                            HitchScope.reportState(experimentDomain, label: "variant_b")
                            lastAction = "Reported state \"variant_b\" on \(experimentDomain)"
                        }
                        TriggerRow(
                            title: "Report state: home (with stableMetadata)",
                            subtitle: "Stable metadata is part of the state's identity - a new userTier is a new transition"
                        ) {
                            HitchScope.reportState(
                                domain, label: "home", stableMetadata: ["userTier": .init("premium")])
                            lastAction = "Reported state \"home\" on \(domain) with stableMetadata"
                        }
                        TriggerRow(
                            title: "Update cart items metadata (+1)",
                            subtitle: "cartItems=\(cartItems) - updates volatile metadata without starting a new transition"
                        ) {
                            cartItems += 1
                            HitchScope.updateVolatileMetadata(domain, ["cartItems": .init(cartItems)])
                            lastAction = "Updated volatile metadata cartItems=\(cartItems) on \(domain)"
                        }
                    } header: {
                        SectionHeader(title: "State & metadata")
                    } footer: {
                        Text(
                            "Optional - every trigger below already sets its own fixed, reproducible state (checkout/variant_b) first. These are only for exploring state reporting on its own."
                        )
                        .foregroundStyle(HSPalette.textSecondary)
                    }

                    Section {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(
                                "Sets state: checkout/variant_b, then blocks the main thread. A 2s hang has never actually produced a real diagnostic in testing - try 10s for better odds."
                            )
                            .font(.caption2)
                            .foregroundStyle(HSPalette.textSecondary)
                            Picker("Hang duration", selection: $hangDuration) {
                                Text("2s").tag(2.0)
                                Text("10s").tag(10.0)
                            }
                            .pickerStyle(.segmented)
                            Button("Trigger main-thread hang") {
                                setReproducibleState()
                                let duration = hangDuration
                                lastAction =
                                    "Set state: checkout/variant_b. Blocking the main thread for \(Int(duration))s to trigger a real MetricKit hang diagnostic…"
                                // Deliberately synchronous on the main thread —
                                // this is how you produce a genuine
                                // MXHangDiagnostic on device; there's no way to
                                // fake one via the SDK's own API.
                                Thread.sleep(forTimeInterval: duration)
                                lastAction =
                                    "Hang triggered. Unlike crash/memory (confirmed within a minute of relaunching), a hang diagnostic hasn't been confirmed to arrive through this pipeline yet."
                            }
                            .font(.system(.body, design: .default, weight: .bold))
                            .foregroundStyle(HSPalette.accent)
                        }
                        .listRowBackground(HSPalette.surface)

                        TriggerRow(
                            title: slowLaunchArmed
                                ? "Armed — force-quit and relaunch now" : "Arm slow next launch (~3s stall)",
                            subtitle:
                                "appLaunch fires for an unusually slow launch, not something a mid-session tap can produce. Arm, then force-quit and relaunch. (No state to set here - the next launch starts with none.)",
                            isDisabled: slowLaunchArmed
                        ) {
                            SlowLaunchFlag.arm()
                            slowLaunchArmed = true
                            lastAction = "Armed a ~3s stall for the next app launch. Force-quit via the App Switcher, then relaunch."
                        }
                        TriggerRow(
                            title: "Trigger crash",
                            subtitle: "Sets state: checkout/variant_b, then terminates immediately - check for a new fixture after relaunching.",
                            isDestructive: true
                        ) {
                            setReproducibleState()
                            // fatalError terminates synchronously - lastAction
                            // never gets a chance to render, so the subtitle
                            // above is static instead of a status update.
                            fatalError("HitchScope Example: deliberate crash trigger")
                        }
                        TriggerRow(
                            title: "Trigger memory exception",
                            subtitle: "Sets state: checkout/variant_b, then allocates until the OS jetsam-kills the process - check after relaunching.",
                            isDestructive: true
                        ) {
                            setReproducibleState()
                            lastAction =
                                "Set state: checkout/variant_b. Allocating memory until the OS terminates the app — relaunch afterward to check for a memory exception diagnostic."
                            // Off the main thread so this reads as memory
                            // pressure, not another main-thread hang - the OS
                            // jetsam-kills the process once it exceeds its
                            // memory limit.
                            DispatchQueue.global(qos: .userInitiated).async {
                                var blocks: [[UInt8]] = []
                                while true {
                                    blocks.append([UInt8](repeating: 0xFF, count: 50_000_000))
                                }
                            }
                        }
                    } header: {
                        SectionHeader(title: "One-shot incidents")
                    }

                    Section {
                        TriggerRow(
                            title: isRunningCPUWorkload ? "Running CPU workload (~60s)…" : "Run CPU-busy workload (~60s)",
                            subtitle: "Sets state: checkout/variant_b, then feeds cpuException if an undocumented threshold is crossed; always contributes to cpuTime/cpuInstructionsCount.",
                            isDisabled: isRunningCPUWorkload
                        ) {
                            setReproducibleState()
                            isRunningCPUWorkload = true
                            lastAction = "Set state: checkout/variant_b. Running 4 concurrent CPU-busy loops for ~60s…"
                            Workloads.runCPUBusyWorkload {
                                isRunningCPUWorkload = false
                                lastAction = "CPU-busy workload finished."
                            }
                        }
                        TriggerRow(
                            title: isRunningDiskWorkload
                                ? "Running disk-write workload (~60s)…" : "Run disk-write workload (~60s)",
                            subtitle: "Sets state: checkout/variant_b, then feeds diskWriteException if an undocumented threshold is crossed - not guaranteed.",
                            isDisabled: isRunningDiskWorkload
                        ) {
                            setReproducibleState()
                            isRunningDiskWorkload = true
                            lastAction = "Set state: checkout/variant_b. Writing to a scratch file for ~60s…"
                            Workloads.runDiskWriteWorkload {
                                isRunningDiskWorkload = false
                                lastAction = "Disk-write workload finished, scratch file removed."
                            }
                        }
                        TriggerRow(
                            title: "Spike peak memory (~300MB, held 2s)",
                            subtitle: "Sets state: checkout/variant_b, then a bounded single spike - can set today's peakMemory without risking a jetsam kill."
                        ) {
                            setReproducibleState()
                            lastAction = "Set state: checkout/variant_b. Allocating a bounded ~300MB spike, held for 2s…"
                            Workloads.runPeakMemorySpike {
                                lastAction = "Peak memory spike released."
                            }
                        }
                    } header: {
                        SectionHeader(title: "Sustained workloads")
                    }

                    Section {
                        TriggerRow(
                            title: "GPU Busy",
                            subtitle: "Sets state: checkout/variant_b, then feeds gpuTime - stay on screen for a couple minutes for it to matter."
                        ) {
                            setReproducibleState()
                            lastAction = "Set state: checkout/variant_b. Opening GPU Busy…"
                            showingGPUBusy = true
                        }
                        TriggerRow(
                            title: "Scroll Jank",
                            subtitle: "Sets state: checkout/variant_b, then feeds hitchTime - scroll up and down repeatedly for it to matter."
                        ) {
                            setReproducibleState()
                            lastAction = "Set state: checkout/variant_b. Opening Scroll Jank…"
                            showingScrollJank = true
                        }
                    } header: {
                        SectionHeader(title: "Rendering workloads")
                    }

                    Section {
                        TriggerRow(
                            title: "Run network workload (GET ~5MB + POST ~2MB)",
                            subtitle:
                                "Sets state: checkout/variant_b, then a real round-trip against httpbin.org - which of the 4 WiFi/cellular buckets it lands in depends on device connectivity, not the app."
                        ) {
                            setReproducibleState()
                            lastAction = "Set state: checkout/variant_b. Running a real network GET + POST against httpbin.org…"
                            Workloads.runNetworkWorkload {
                                lastAction = "Network workload finished."
                            }
                        }
                    } header: {
                        SectionHeader(title: "Network")
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(HSPalette.bg)
                .frame(maxHeight: .infinity)

                Rectangle()
                    .fill(HSPalette.divider)
                    .frame(height: 2)

                pinnedLogPanel
            }
            .background(HSPalette.bg.ignoresSafeArea())
            .navigationTitle("HitchScope Example")
            .navigationBarTitleDisplayMode(.inline)
        }
        .preferredColorScheme(.dark)
        .tint(HSPalette.accent)
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

    /// Stays pinned below the trigger list (not its own screen) - watching it
    /// react to whatever was just tapped is the app's whole point.
    private var pinnedLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(lastAction)
                .font(.caption)
                .foregroundStyle(HSPalette.textSecondary)
                .frame(maxWidth: .infinity, alignment: .leading)

            HStack {
                SectionHeader(title: "SDK log")
                Spacer()
                Button("Refresh") { refreshLogLines() }
                    .font(.caption2)
                    .foregroundStyle(HSPalette.accent)
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(line.contains("[ERROR]") ? HSPalette.accent : HSPalette.text)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                    }
                }
                .onChange(of: logLines.count) {
                    guard let last = logLines.indices.last else { return }
                    proxy.scrollTo(last, anchor: .bottom)
                }
            }
            .frame(height: 160)
        }
        .padding()
        .background(HSPalette.surface)
    }
}

#Preview {
    ContentView()
}
