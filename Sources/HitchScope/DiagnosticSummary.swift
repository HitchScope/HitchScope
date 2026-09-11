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

enum DiagnosticKind: Sendable {
  case crash(CrashSummary)
  case hang(durationMs: Double, threadCount: Int)
  case appLaunch(durationMs: Double, threadCount: Int)
  case memoryException(threadCount: Int)
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
}
