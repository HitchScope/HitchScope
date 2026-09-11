import Foundation
import MetricKit
import StateReporting

/// The only file that imports `MetricKit`/`StateReporting`. Owns the
/// `MetricManager` (constructed once with every domain declared at
/// `configure`), one `StateReporter` per declared domain, and the task
/// consuming `diagnosticReports`.
actor MetricKitBridge {
  private let manager: MetricManager
  private var reporters:
    [String: StateReporter<HitchScopeMetadataDictionary, HitchScopeMetadataDictionary>] = [:]
  private let sink: HitchScopeRuntime
  private var consumeTask: Task<Void, Never>?

  init(domains: Set<String>, sink: HitchScopeRuntime) {
    self.manager = MetricManager(
      enabledStateReportingDomains: Set(domains.map { StateReportingDomain(rawValue: $0) }))
    self.sink = sink
    for domain in domains {
      reporters[domain] = StateReporter.reporter(
        for: domain,
        stableMetadata: HitchScopeMetadataDictionary.self,
        volatileMetadata: HitchScopeMetadataDictionary.self
      )
    }
  }

  func start() {
    guard consumeTask == nil else { return }
    consumeTask = Task { [manager, sink] in
      for await report in manager.diagnosticReports {
        for summary in Self.summarize(report) {
          await sink.enqueue(EventMapper.map(summary))
        }
      }
    }
  }

  /// Caller (`HitchScopeRuntime`) has already validated that `domain` was
  /// declared and `label` isn't an empty string — this assumes valid input.
  func reportState(
    domain: String, label: String?, stableMetadata: [String: HitchScopeMetadataValue],
    volatileMetadata: [String: HitchScopeMetadataValue]
  ) {
    reporters[domain]?.reportTransition(
      to: label,
      stableMetadata: HitchScopeMetadataDictionary(stableMetadata),
      volatileMetadata: HitchScopeMetadataDictionary(volatileMetadata)
    )
  }

  func updateVolatileMetadata(domain: String, metadata: [String: HitchScopeMetadataValue]) {
    reporters[domain]?.reportVolatileMetadataUpdate(HitchScopeMetadataDictionary(metadata))
  }

  // MARK: - DiagnosticReport -> plain DiagnosticSummary

  private static func summarize(_ report: DiagnosticReport) -> [DiagnosticSummary] {
    let states = report.environment.states.map { StateEntry(domain: $0.domain, label: $0.label) }
    // `.start` of the report's time window — the closest available
    // approximation of when the underlying incident actually happened.
    let occurredAt = report.timeRange.start

    switch report.result {
    case .crash(let diagnostic):
      let threads = diagnostic.callStackTree.callStackThreads
      let topFrames = (threads.first?.rootFrames ?? []).prefix(5).map { frame in
        FrameSummary(
          binaryUUID: frame.binaryUUID?.uuidString,
          offset: frame.offsetIntoBinaryTextSegment,
          sampleCount: frame.sampleCount
        )
      }
      let crash = CrashSummary(
        terminationReason: diagnostic.terminationReason?.rawValue,
        terminationCategory: diagnostic.terminationCategory?.rawValue,
        exceptionType: diagnostic.exceptionType,
        exceptionCode: diagnostic.exceptionCode,
        signal: diagnostic.signal,
        threadCount: threads.count,
        topFrames: Array(topFrames)
      )
      return [DiagnosticSummary(states: states, occurredAt: occurredAt, kind: .crash(crash))]

    case .hang(let diagnostic):
      let threadCount = diagnostic.callStackTree.callStackThreads.count
      let durationMs = diagnostic.hangDuration.converted(to: .milliseconds).value
      return [
        DiagnosticSummary(
          states: states, occurredAt: occurredAt,
          kind: .hang(durationMs: durationMs, threadCount: threadCount))
      ]

    case .appLaunch(let diagnostic):
      let threadCount = diagnostic.callStackTree.callStackThreads.count
      let durationMs = diagnostic.launchDuration.converted(to: .milliseconds).value
      return [
        DiagnosticSummary(
          states: states, occurredAt: occurredAt,
          kind: .appLaunch(durationMs: durationMs, threadCount: threadCount))
      ]

    case .memoryException(let diagnostic):
      let threadCount = diagnostic.callStackTree.callStackThreads.count
      return [
        DiagnosticSummary(
          states: states, occurredAt: occurredAt, kind: .memoryException(threadCount: threadCount))
      ]

    case .cpuException, .diskWriteException:
      // No slot in the backend's 4-type contract — dropped, not mis-mapped.
      return []

    @unknown default:
      return []
    }
  }
}
