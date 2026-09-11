import Foundation
import MetricKit
import StateReporting
import os.log

/// The only file that imports `MetricKit`/`StateReporting`. Owns the
/// `MetricManager` (constructed once with every domain declared at
/// `configure`), one `StateReporter` per declared domain, and the task
/// consuming `diagnosticReports`.
actor MetricKitBridge {
  private static let log = OSLog(subsystem: "com.hitchscope.sdk", category: "MetricKitBridge")

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

  private var consumeMetricsTask: Task<Void, Never>?

  func start() {
    guard consumeTask == nil else { return }
    os_log(.info, log: Self.log, "started consuming diagnosticReports/metricReports")
    consumeTask = Task { [manager, sink] in
      for await report in manager.diagnosticReports {
        let summaries = Self.summarize(report)
        let kindName = Mirror(reflecting: report.result).children.first?.label ?? "unknown"
        os_log(.info, log: Self.log, "received diagnosticReport: kind=%{public}@", kindName)
        for summary in summaries {
          await sink.enqueue(EventMapper.map(summary))
        }
      }
    }
    consumeMetricsTask = Task { [manager, sink] in
      for await report in manager.metricReports {
        // Metrics arrive as a whole report at once (roughly daily, per
        // Apple's own docs) - batch the whole report into one flush rather
        // than one per value, keeping each ingest payload coherent.
        let summaries = Self.summarizeMetrics(report)
        os_log(
          .info, log: Self.log, "received metricReport: %d state entries, %d summaries",
          report.stateEntries.count, summaries.count)
        let events = summaries.map(MetricAggregateMapper.map)
        await sink.enqueueMetrics(events)
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

  // MARK: - MetricReport -> plain MetricAggregateSummary

  /// Iterates `report.stateEntries` only (one state, full-day window,
  /// unambiguous `windowStart`/`windowEnd` from `report.timeRange`) — NOT
  /// `report.intervalEntries`, whose sub-day windows don't carry an absolute
  /// start time of their own and how they anchor within the report's overall
  /// `timeRange` isn't documented. Deferred until confirmed empirically
  /// rather than guessed.
  private static func summarizeMetrics(_ report: MetricReport) -> [MetricAggregateSummary] {
    let windowStart = report.timeRange.start
    let windowEnd = report.timeRange.end

    var summaries: [MetricAggregateSummary] = []
    for stateEntry in report.stateEntries {
      let states = [StateEntry(domain: stateEntry.state.domain, label: stateEntry.state.label)]
      for value in stateEntry.values {
        guard let kind = metricAggregateKind(for: value) else { continue }
        summaries.append(
          MetricAggregateSummary(
            states: states, windowStart: windowStart, windowEnd: windowEnd, kind: kind))
      }
    }
    return summaries
  }

  /// The 4 "hero" kinds (matching the product's stated pillars) get bespoke
  /// extraction into typed fields. Every other `MetricResult` case falls
  /// through to `.generic` - captured via the case's own `Codable`
  /// conformance rather than a hand-written struct, so new MetricKit cases
  /// in a future OS are captured automatically, not silently dropped.
  private static func metricAggregateKind(for result: MetricResult) -> MetricAggregateKind? {
    switch result {
    case .hangTime(let metric):
      return .hangTime(buckets: bucketSummaries(metric.histogram))
    case .hitchTime(let metric):
      return .hitchTime(
        ratio: metric.ratio.value,
        totalHitchMs: metric.totalHitchTime.converted(to: .milliseconds).value,
        totalAnimationMs: metric.totalAnimationTime.converted(to: .milliseconds).value
      )
    case .extendedLaunch(let metric):
      return .extendedLaunch(buckets: bucketSummaries(metric.histogram))
    case .peakMemory(let metric):
      return .peakMemory(megabytes: metric.value.converted(to: .megabytes).value)
    default:
      // Case name via reflection (not a hand-maintained switch) so this
      // stays correct as Apple adds new MetricResult cases over time.
      let kindName = Mirror(reflecting: result).children.first?.label ?? "unknown"
      guard let encoded = try? JSONEncoder().encode(result) else { return nil }
      return .generic(kindName: kindName, encodedValue: encoded)
    }
  }

  private static func bucketSummaries(_ histogram: Histogram<UnitDuration>) -> [BucketSummary] {
    histogram.buckets.map {
      BucketSummary(
        lowerBoundMs: $0.lowerBound.converted(to: .milliseconds).value,
        upperBoundMs: $0.upperBound.converted(to: .milliseconds).value,
        count: $0.count
      )
    }
  }
}
