import Foundation

/// Whether a catalog entry is backed by a discrete MetricKit diagnostic, a
/// continuous windowed aggregate, or both for the same underlying phenomenon.
enum MetricCategory: Hashable {
    case diagnostic
    case aggregate
    case mixed
}

/// One field this screen's metric(s) actually report, with its unit and
/// which diagnostic/aggregate it comes from - drawn from the SDK's real
/// `DiagnosticSummary`/`MetricAggregateSummary` field names.
struct MetricField: Hashable {
    let name: String
    let unit: String
    let source: String
}

/// Everything one metric screen needs to describe itself - the single
/// source of truth for both the home list row and the detail screen's
/// header, so this descriptive text is never duplicated between the two.
struct MetricCatalogEntry: Identifiable {
    let id: String
    let title: String
    let symbolName: String
    let category: MetricCategory
    /// One line, for the home-list row.
    let summary: String
    /// Long-form, for the detail screen header.
    let overview: String
    let fields: [MetricField]
    let isReproducible: Bool
    let reproducibilityNote: String
    let hasPerformanceToggle: Bool
}

extension MetricCatalogEntry: Hashable {
    static func == (lhs: MetricCatalogEntry, rhs: MetricCatalogEntry) -> Bool { lhs.id == rhs.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// The 6 `DiagnosticKind` cases and 13 `MetricAggregateKind` cases the SDK
/// extracts (`Sources/HitchScope/DiagnosticSummary.swift`,
/// `Sources/HitchScope/MetricAggregateSummary.swift`), plus its generic
/// catch-all, each mapped to exactly one screen below - grouped by
/// phenomenon rather than 1:1 with the raw enum cases, since a hang (say)
/// produces both a discrete diagnostic and feeds a daily aggregate.
enum MetricCatalog {
    static let all: [MetricCatalogEntry] = [
        MetricCatalogEntry(
            id: "hangs",
            title: "Hangs",
            symbolName: "hourglass",
            category: .mixed,
            summary: "Main-thread stalls - a discrete diagnostic per hang, plus a daily aggregate.",
            overview: """
                A hang is any stretch where the main thread can't respond to input for long enough \
                that MetricKit considers the app unresponsive. Each individual hang is reported as a \
                discrete .hang diagnostic as soon as MetricKit notices it; every hang that happens in \
                a day also rolls up into the hangTime aggregate, a histogram of hang durations \
                delivered once a day.
                """,
            fields: [
                MetricField(name: "durationMs", unit: "ms", source: "hang diagnostic (per incident)"),
                MetricField(name: "threadCount", unit: "count", source: "hang diagnostic"),
                MetricField(name: "p50Ms / p95Ms / meanMs", unit: "ms", source: "hangTime aggregate (daily histogram)"),
            ],
            isReproducible: true,
            reproducibilityNote: """
                Blocks the main thread with Thread.sleep for the chosen duration - the only way to \
                produce a genuine hang, there's no API to fake one. A 2s hang has never reliably \
                produced a diagnostic in testing here; 10s has better odds. The stall always \
                contributes to hangTime regardless.
                """,
            hasPerformanceToggle: true
        ),
        MetricCatalogEntry(
            id: "appLaunch",
            title: "App Launch",
            symbolName: "bolt.fill",
            category: .mixed,
            summary: "Cold-launch duration - a discrete diagnostic plus a daily aggregate.",
            overview: """
                appLaunch diagnostics fire when a single cold launch takes unusually long; the \
                extendedLaunch aggregate is the same thing rolled up into a daily histogram. Both \
                measure wall-clock time from process start to first meaningful UI, so neither can be \
                produced by anything that happens after the app is already running. The dashboard \
                separately surfaces timeToFirstDraw, optimizedTimeToFirstDraw, and \
                applicationResumeTime - three more launch timings MetricKit reports that this SDK \
                currently relays only generically (see Other Device Metrics), not as typed fields.
                """,
            fields: [
                MetricField(name: "durationMs", unit: "ms", source: "appLaunch diagnostic"),
                MetricField(name: "threadCount", unit: "count", source: "appLaunch diagnostic"),
                MetricField(name: "p50Ms / p95Ms / meanMs", unit: "ms", source: "extendedLaunch aggregate (daily histogram)"),
            ],
            isReproducible: true,
            reproducibilityNote: """
                Arm a ~3 second stall for the *next* cold launch, then force-quit the app (swipe up \
                in the App Switcher) and relaunch it. There's no state to set beforehand - the next \
                launch starts with none.
                """,
            hasPerformanceToggle: false
        ),
        MetricCatalogEntry(
            id: "crashes",
            title: "Crashes",
            symbolName: "exclamationmark.triangle.fill",
            category: .diagnostic,
            summary: "Uncaught termination - a single discrete diagnostic per crash.",
            overview: """
                A crash diagnostic captures how the process died: the termination reason and \
                category, the exception type/code, the signal, and how many threads were running. \
                Unlike hangs or launches, this is a one-shot incident with no continuous aggregate \
                counterpart - either the app crashed or it didn't.
                """,
            fields: [
                MetricField(name: "terminationReason", unit: "string", source: "crash diagnostic"),
                MetricField(name: "terminationCategory", unit: "string", source: "crash diagnostic"),
                MetricField(name: "exceptionType / exceptionCode", unit: "raw", source: "crash diagnostic"),
                MetricField(name: "signal", unit: "raw", source: "crash diagnostic"),
                MetricField(name: "threadCount", unit: "count", source: "crash diagnostic"),
            ],
            isReproducible: true,
            reproducibilityNote: """
                Calls fatalError() and terminates immediately. Fixture state is set right before \
                terminating - check for a new fixture after relaunching; the crash diagnostic has \
                consistently shown up within a minute in testing.
                """,
            hasPerformanceToggle: false
        ),
        MetricCatalogEntry(
            id: "memory",
            title: "Memory",
            symbolName: "memorychip",
            category: .mixed,
            summary: "Jetsam terminations - a discrete diagnostic plus a daily peak-memory aggregate.",
            overview: """
                A memoryException diagnostic fires when the OS kills the app for exceeding its \
                memory limit (a "jetsam" termination) - the real diagnostic carries no severity or \
                peak-usage field, only a thread count. Separately, peakMemory is a daily aggregate of \
                the single highest memory footprint the app reached that day, whether or not it ever \
                got jetsam-killed.
                """,
            fields: [
                MetricField(name: "threadCount", unit: "count", source: "memoryException diagnostic (no severity/peak field exists)"),
                MetricField(name: "megabytes", unit: "MB", source: "peakMemory aggregate"),
            ],
            isReproducible: true,
            reproducibilityNote: """
                Two separate triggers below: one allocates memory in an unbounded loop until the OS \
                kills the app (produces the diagnostic, but force-quits the app - check after \
                relaunching); the other is a bounded ~300MB spike held for 2 seconds, safe to run \
                repeatedly, and only ever contributes to peakMemory.
                """,
            hasPerformanceToggle: false
        ),
        MetricCatalogEntry(
            id: "cpu",
            title: "CPU",
            symbolName: "cpu",
            category: .mixed,
            summary: "Sustained CPU load - a threshold-gated diagnostic plus two daily aggregates.",
            overview: """
                cpuException is a diagnostic that only fires if the app crosses an undocumented, \
                Apple-controlled CPU usage threshold over some sustained period - it's not \
                guaranteed just because the app was busy. cpuTime and cpuInstructionsCount are \
                unconditional daily aggregates: every bit of CPU work the app does contributes to \
                them, whether or not the exception threshold was ever crossed.
                """,
            fields: [
                MetricField(name: "totalCPUTimeMs / totalSampledTimeMs", unit: "ms", source: "cpuException diagnostic"),
                MetricField(name: "threadCount", unit: "count", source: "cpuException diagnostic"),
                MetricField(name: "ms", unit: "ms", source: "cpuTime aggregate"),
                MetricField(name: "count", unit: "count", source: "cpuInstructionsCount aggregate"),
            ],
            isReproducible: true,
            reproducibilityNote: """
                Runs 4 concurrent CPU-busy loops for ~60 seconds. This always contributes real work \
                to cpuTime/cpuInstructionsCount; whether it also produces a cpuException diagnostic \
                depends on crossing Apple's undocumented threshold, so it's not guaranteed.
                """,
            hasPerformanceToggle: true
        ),
        MetricCatalogEntry(
            id: "diskWrites",
            title: "Disk Writes",
            symbolName: "externaldrive.fill",
            category: .diagnostic,
            summary: "Sustained disk writes - a threshold-gated diagnostic, no continuous counterpart.",
            overview: """
                diskWriteException fires if the app crosses an undocumented, Apple-controlled \
                threshold for how much it writes to disk over some sustained period. Unlike CPU, \
                there's no unconditional daily aggregate alongside it here - this is purely a \
                threshold-gated diagnostic.
                """,
            fields: [
                MetricField(name: "totalBytesWritten", unit: "bytes", source: "diskWriteException diagnostic"),
                MetricField(name: "threadCount", unit: "count", source: "diskWriteException diagnostic"),
            ],
            isReproducible: true,
            reproducibilityNote: """
                Writes chunks to a scratch file under Caches for up to 60 seconds (deleted \
                afterward, regardless of outcome). Not guaranteed to cross the threshold and produce \
                a diagnostic.
                """,
            hasPerformanceToggle: true
        ),
        MetricCatalogEntry(
            id: "gpu",
            title: "GPU",
            symbolName: "display",
            category: .aggregate,
            summary: "GPU-busy time - a continuous daily aggregate, no discrete trigger.",
            overview: """
                gpuTime is a daily aggregate of how much time the app spent doing GPU work. There's \
                no discrete "GPU exception" diagnostic - the only way to move this number is to stay \
                on a GPU-heavy screen for a while and let it accumulate.
                """,
            fields: [
                MetricField(name: "ms", unit: "ms", source: "gpuTime aggregate")
            ],
            isReproducible: true,
            reproducibilityNote: """
                This screen renders 400 blurred, animated shapes continuously - genuinely \
                GPU-expensive, not just decorative. Stay on it for a couple of minutes; the number \
                only shows up in MetricKit's next daily report, never immediately.
                """,
            hasPerformanceToggle: false
        ),
        MetricCatalogEntry(
            id: "scrollHitches",
            title: "Scroll Hitches",
            symbolName: "list.bullet",
            category: .aggregate,
            summary: "Scroll jank - a continuous daily ratio, no discrete trigger.",
            overview: """
                hitchTime is a daily ratio of janky-to-total animation time (reported in \
                milliseconds of hitch per second of animation, not a percentage), plus the raw \
                totalHitchMs and totalAnimationMs it was computed from. There's no discrete "hitch" \
                diagnostic - only sustained scrolling with real stalls moves this number.
                """,
            fields: [
                MetricField(name: "ratio", unit: "ms/s", source: "hitchTime aggregate"),
                MetricField(name: "totalHitchMs / totalAnimationMs", unit: "ms", source: "hitchTime aggregate"),
            ],
            isReproducible: true,
            reproducibilityNote: """
                The list below deliberately stalls the main thread for 40ms on every 5th row as it \
                appears. Scroll up and down repeatedly - loading the screen once and never scrolling \
                won't produce any jank. Use the toggle to compare: off reproduces the stall, on \
                removes it entirely.
                """,
            hasPerformanceToggle: true
        ),
        MetricCatalogEntry(
            id: "network",
            title: "Network",
            symbolName: "network",
            category: .aggregate,
            summary: "WiFi/cellular transfer totals - four continuous daily aggregates.",
            overview: """
                MetricKit tracks total bytes transferred across four independent buckets: WiFi \
                upload, WiFi download, cellular upload, and cellular download. All four are \
                continuous daily aggregates with no discrete trigger.
                """,
            fields: [
                MetricField(name: "totalWiFiUpload / totalWiFiDownload", unit: "bytes", source: "WiFi aggregates"),
                MetricField(name: "totalCellularUpload / totalCellularDownload", unit: "bytes", source: "cellular aggregates"),
            ],
            isReproducible: true,
            reproducibilityNote: """
                Runs a real network round-trip - a ~5MB GET and a ~2MB POST against httpbin.org, a \
                public test endpoint (no real user data leaves the device). Which of the 4 buckets \
                it lands in depends on the device's actual connectivity at the time, not anything \
                the app controls.
                """,
            hasPerformanceToggle: false
        ),
        MetricCatalogEntry(
            id: "terminations",
            title: "App Terminations",
            symbolName: "xmark.octagon.fill",
            category: .aggregate,
            summary: "Why the app exited - two daily cause-count breakdowns, not reproducible.",
            overview: """
                foregroundTermination and backgroundTermination are daily counts of why the app's \
                process ended, broken down by cause (normal exit, hit the memory limit, bad memory \
                access, other abnormal exit, illegal instruction, watchdog timeout - plus, for \
                background exits only, high CPU usage, system memory pressure, a held file lock, and \
                a background task timeout).
                """,
            fields: [
                MetricField(
                    name: "normalCount / memoryLimitCount / badAccessCount / abnormalCount / illegalInstructionCount / watchdogCount",
                    unit: "count", source: "foregroundTermination + backgroundTermination"),
                MetricField(
                    name: "highCPUCount / systemPressureCount / fileLockCount / taskTimeoutCount",
                    unit: "count", source: "backgroundTermination only"),
            ],
            isReproducible: false,
            reproducibilityNote: """
                Not reproducible from in-app code. These are recorded by the OS whenever the process \
                actually ends, for whatever reason - there's no API to report a termination cause \
                directly. Triggering a crash or an unbounded memory allocation elsewhere in this app \
                will indirectly move these counts, but there's no dedicated trigger for this screen.
                """,
            hasPerformanceToggle: false
        ),
        MetricCatalogEntry(
            id: "otherMetrics",
            title: "Other Device Metrics",
            symbolName: "chart.bar.fill",
            category: .aggregate,
            summary: "Everything else MetricKit reports - relayed generically, not reproducible.",
            overview: """
                MetricKit reports several more metric families that this SDK currently relays \
                through a generic catch-all rather than giving bespoke typed fields: storage (total \
                file count/size, disk capacity), display (suspended-state memory, pixel luminance), \
                cellular signal condition, location activity time, background/foreground time \
                totals (including background audio and background location time), and logical disk \
                writes. The dashboard's timeToFirstDraw, optimizedTimeToFirstDraw, and \
                applicationResumeTime launch timings (see App Launch) also currently flow through \
                this same generic path.
                """,
            fields: [
                MetricField(name: "totalFileCount / totalFileSize / totalDiskSpaceCapacity", unit: "count / bytes", source: "storage"),
                MetricField(name: "suspendedMemory / pixelLuminance", unit: "MB / raw", source: "display"),
                MetricField(name: "cellularConditionTime", unit: "raw", source: "cellular condition"),
                MetricField(name: "locationActivityTime", unit: "raw", source: "location activity"),
                MetricField(
                    name: "totalForegroundTime / totalBackgroundTime / totalBackgroundAudioTime / totalBackgroundLocationTime",
                    unit: "ms", source: "time totals"),
                MetricField(name: "logicalDiskWrites", unit: "bytes", source: "disk"),
            ],
            isReproducible: false,
            reproducibilityNote: """
                Not reproducible by any single action - these are passive device/usage telemetry \
                MetricKit accumulates just from normal day-to-day use of the app and device, not \
                something a button can trigger on demand.
                """,
            hasPerformanceToggle: false
        ),
    ]

    static var reproducible: [MetricCatalogEntry] { all.filter(\.isReproducible) }
    static var referenceOnly: [MetricCatalogEntry] { all.filter { !$0.isReproducible } }

    /// Every screen only ever asks for an id this catalog actually defines
    /// (its own, hardcoded at the call site), so a missing entry would be a
    /// programmer error in this file, not a runtime condition to handle.
    static func entry(for id: String) -> MetricCatalogEntry {
        guard let match = all.first(where: { $0.id == id }) else {
            preconditionFailure("No MetricCatalog entry for id \"\(id)\"")
        }
        return match
    }
}
