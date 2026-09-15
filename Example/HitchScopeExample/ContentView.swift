import SwiftUI
import OSLog

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

private func fetchCapturedFixtureURLs() -> [URL] {
    (try? FileManager.default.contentsOfDirectory(
        at: FixtureCapture.fixturesDirectory, includingPropertiesForKeys: nil,
        options: [.skipsHiddenFiles])) ?? []
}

struct ContentView: View {
    @State private var logLines: [String] = []
    @State private var capturedFixtureURLs: [URL] = []

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
                    "A screen per MetricKit metric this SDK understands - a description, its units, and (where possible) a way to reproduce it. Diagnostics are discrete incidents; aggregates are continuous daily rollups that only show up in tomorrow's report."
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
                        NavigationLink {
                            StateReportingScreen()
                        } label: {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("State Reporting API")
                                    .font(.system(.body, design: .default, weight: .bold))
                                    .foregroundStyle(HSPalette.text)
                                Text("Explore reportState/updateVolatileMetadata directly, on their own demo domain.")
                                    .font(.caption2)
                                    .foregroundStyle(HSPalette.textSecondary)
                            }
                        }
                        .listRowBackground(HSPalette.surface)
                    } header: {
                        SectionHeader(title: "SDK API")
                    }

                    Section {
                        ForEach(MetricCatalog.reproducible) { entry in
                            NavigationLink(value: entry) {
                                MetricRowLabel(entry: entry)
                            }
                        }
                    } header: {
                        SectionHeader(title: "Diagnostics & performance problems")
                    }

                    Section {
                        ForEach(MetricCatalog.referenceOnly) { entry in
                            NavigationLink(value: entry) {
                                MetricRowLabel(entry: entry)
                            }
                        }
                    } header: {
                        SectionHeader(title: "Reference only")
                    } footer: {
                        Text("MetricKit reports these too, but nothing in this app can trigger them on demand.")
                            .foregroundStyle(HSPalette.textSecondary)
                    }
                }
                .listStyle(.plain)
                .scrollContentBackground(.hidden)
                .background(HSPalette.bg)
                .frame(maxHeight: .infinity)
                .navigationDestination(for: MetricCatalogEntry.self) { entry in
                    screen(for: entry.id)
                }

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
        .reportsScreenState("home")
        .onAppear { refreshLogLines() }
        // The log store doesn't push updates, so poll while this view is
        // visible rather than trying to observe it — simplest option for a
        // dev-only debug view. fetchSDKLogLines() does real OSLogStore I/O,
        // so it's dispatched off the main thread — running it inline here
        // every 1.5s was stalling the UI the whole time this view is up,
        // independent of anything else happening.
        .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
            refreshLogLines()
        }
    }

    @ViewBuilder
    private func screen(for id: String) -> some View {
        switch id {
        case "hangs": HangsScreen()
        case "appLaunch": AppLaunchScreen()
        case "crashes": CrashesScreen()
        case "memory": MemoryScreen()
        case "cpu": CPUScreen()
        case "diskWrites": DiskWritesScreen()
        case "gpu": GPUScreen()
        case "scrollHitches": ScrollHitchesScreen()
        case "network": NetworkScreen()
        case "terminations": TerminationsScreen()
        case "otherMetrics": OtherMetricsScreen()
        default: EmptyView()
        }
    }

    /// Stays pinned below the metric list (not its own screen) - watching
    /// the SDK's own log react to whatever was just tapped on any screen is
    /// the app's whole point.
    private var pinnedLogPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
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
