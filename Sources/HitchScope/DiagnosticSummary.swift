import Foundation

/// A summarized root call-stack frame — never the full tree, which could be
/// arbitrarily large (many threads x deep subframe trees).
struct FrameSummary: Sendable {
  let binaryUUID: String?
  let offset: UInt64?
  let sampleCount: Int?
}

struct CrashSummary: Sendable {
  let terminationReason: String?
  let terminationCategory: String?
  let exceptionType: Int?
  let exceptionCode: UInt64?
  let signal: Int?
  let threadCount: Int
  let topFrames: [FrameSummary]
}

struct CPUExceptionSummary: Sendable {
  let totalCPUTimeMs: Double
  let totalSampledTimeMs: Double
  let threadCount: Int
  let topFrames: [FrameSummary]
}

struct DiskWriteExceptionSummary: Sendable {
  let totalBytesWritten: Double
  let threadCount: Int
  let topFrames: [FrameSummary]
}

enum DiagnosticKind: Sendable {
  case crash(CrashSummary)
  case hang(durationMs: Double, threadCount: Int)
  case appLaunch(durationMs: Double, threadCount: Int)
  case memoryException(threadCount: Int)
  case cpuException(CPUExceptionSummary)
  case diskWriteException(DiskWriteExceptionSummary)
}

/// A plain, fully constructible summary of one `DiagnosticReport` — the
/// boundary between Apple's framework types (which have no public
/// initializers and can't be constructed in tests) and everything
/// downstream (`EventMapper` and its tests), which only ever sees this type.
struct DiagnosticSummary: Sendable {
  /// Every state-reporting domain/label pair active when the diagnostic
  /// occurred — unfiltered, the full set from `environment.states`.
  let states: [StateEntry]
  let occurredAt: Date
  let kind: DiagnosticKind
  /// From `DiagnosticReport.Environment` - real report-level context,
  /// previously dropped entirely (only `.states` was ever read out of
  /// `environment`). Defaulted so existing test call sites that don't care
  /// about this context don't all need updating.
  let lowPowerModeEnabled: Bool
  let isTestFlightApp: Bool

  init(
    states: [StateEntry], occurredAt: Date, kind: DiagnosticKind,
    lowPowerModeEnabled: Bool = false, isTestFlightApp: Bool = false
  ) {
    self.states = states
    self.occurredAt = occurredAt
    self.kind = kind
    self.lowPowerModeEnabled = lowPowerModeEnabled
    self.isTestFlightApp = isTestFlightApp
  }
}
