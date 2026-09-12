import Foundation

/// A summarized call-stack frame. Real fixtures show a single thread's stack
/// is often a single linear chain 50+ frames deep via `subFrames` - this is
/// one frame from that walked path, not a raw tree node.
struct FrameSummary: Sendable {
  let binaryUUID: String?
  let offset: UInt64?
  let sampleCount: Int?
}

/// From `CrashDiagnostic.ObjectiveCExceptionReason` - only present for an
/// uncaught NSException-style crash.
struct ExceptionReasonSummary: Sendable {
  let composedMessage: String
  let formatString: String
  let arguments: [String]
  let exceptionType: String
  let className: String
  let exceptionName: String
}

struct CrashSummary: Sendable {
  let terminationReason: String?
  let terminationCategory: String?
  let exceptionType: Int?
  let exceptionCode: UInt64?
  let signal: Int?
  let virtualMemoryRegionInfo: String?
  let exceptionReason: ExceptionReasonSummary?
  let threadCount: Int
  let topFrames: [FrameSummary]
}

struct HangSummary: Sendable {
  let durationMs: Double
  let threadCount: Int
  let topFrames: [FrameSummary]
}

struct AppLaunchSummary: Sendable {
  let durationMs: Double
  let threadCount: Int
  let topFrames: [FrameSummary]
}

struct MemoryExceptionSummary: Sendable {
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
  case hang(HangSummary)
  case appLaunch(AppLaunchSummary)
  case memoryException(MemoryExceptionSummary)
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
  /// From `environment.osVersion.buildNumber` (e.g. "24A435") - the exact
  /// build, not just the marketing OS version already sent at the top level
  /// of every ingest request via `DeviceMetadata`.
  let osBuildNumber: String?

  init(
    states: [StateEntry], occurredAt: Date, kind: DiagnosticKind,
    lowPowerModeEnabled: Bool = false, isTestFlightApp: Bool = false,
    osBuildNumber: String? = nil
  ) {
    self.states = states
    self.occurredAt = occurredAt
    self.kind = kind
    self.lowPowerModeEnabled = lowPowerModeEnabled
    self.isTestFlightApp = isTestFlightApp
    self.osBuildNumber = osBuildNumber
  }
}
