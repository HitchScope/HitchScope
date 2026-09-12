import Foundation

/// A single bucket from a MetricKit `Histogram`, captured plainly (bounds
/// already converted to milliseconds).
struct BucketSummary: Sendable {
  let lowerBoundMs: Double
  let upperBoundMs: Double
  let count: Int
}

/// Termination-cause breakdown shared by `ForegroundTerminationMetric` (a
/// subset of these fields) and `BackgroundTerminationMetric` (all of them) -
/// one struct for both, with the foreground-only fields left `nil` when
/// built from a `ForegroundTerminationMetric`, answers "why did the OS kill
/// this state" the same way crash/memory diagnostics answer it for
/// individual incidents.
struct TerminationSummary: Sendable {
  let normalCount: Int
  let memoryLimitCount: Int
  let badAccessCount: Int
  let abnormalCount: Int
  let illegalInstructionCount: Int
  let watchdogCount: Int
  /// Background-only fields - `nil` for a foreground breakdown.
  let highCPUCount: Int?
  let systemPressureCount: Int?
  let fileLockCount: Int?
  let taskTimeoutCount: Int?
}

enum MetricAggregateKind: Sendable {
  case hangTime(buckets: [BucketSummary])
  case hitchTime(ratio: Double, totalHitchMs: Double, totalAnimationMs: Double)
  case extendedLaunch(buckets: [BucketSummary])
  case peakMemory(megabytes: Double)
  case cpuTime(ms: Double)
  case cpuInstructionsCount(count: Int)
  case gpuTime(ms: Double)
  case totalWiFiUpload(bytes: Double)
  case totalWiFiDownload(bytes: Double)
  case totalCellularUpload(bytes: Double)
  case totalCellularDownload(bytes: Double)
  case foregroundTermination(TerminationSummary)
  case backgroundTermination(TerminationSummary)
  /// Every other `MetricResult` case (there are ~17 left: disk, location,
  /// signposts, background/foreground time totals, etc.) — captured
  /// generically rather than mapped case-by-case. `kindName` comes from
  /// runtime reflection on the enum case (not hand-maintained, so a future
  /// OS adding new cases needs no code change here), `encodedValue` is the
  /// case's own `Codable` encoding, decoded into a plain JSON shape by the
  /// mapper.
  case generic(kindName: String, encodedValue: Data)
}

/// A plain, fully constructible summary of one state's metric values within
/// one `MetricReport` window — the boundary between Apple's framework types
/// (no public initializers, can't be constructed in tests) and everything
/// downstream (`MetricAggregateMapper` and its tests).
struct MetricAggregateSummary: Sendable {
  let states: [StateEntry]
  let windowStart: Date
  let windowEnd: Date
  let kind: MetricAggregateKind
  /// From `MetricReport.Environment` - real report-level context, previously
  /// dropped entirely. `hasExceededStateLimit` in particular is a real
  /// correctness signal: the report hit an internal state-combination cap.
  /// Defaulted so existing test call sites don't all need updating.
  let lowPowerModeEnabled: Bool
  let isTestFlightApp: Bool
  let hasExceededStateLimit: Bool

  init(
    states: [StateEntry], windowStart: Date, windowEnd: Date, kind: MetricAggregateKind,
    lowPowerModeEnabled: Bool = false, isTestFlightApp: Bool = false,
    hasExceededStateLimit: Bool = false
  ) {
    self.states = states
    self.windowStart = windowStart
    self.windowEnd = windowEnd
    self.kind = kind
    self.lowPowerModeEnabled = lowPowerModeEnabled
    self.isTestFlightApp = isTestFlightApp
    self.hasExceededStateLimit = hasExceededStateLimit
  }
}
