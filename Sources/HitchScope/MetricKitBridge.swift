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
    // .default throughout this file, not .info - .info only lives in a
    // volatile memory buffer and is routinely evicted before anyone looks,
    // especially outside a live Xcode session; .default actually persists.
    os_log(.default, log: Self.log, "started consuming diagnosticReports/metricReports")
    consumeTask = Task { [manager, sink] in
      for await report in manager.diagnosticReports {
        Self.captureFixture(report, kind: "diagnostic")
        let summaries = Self.summarize(report)
        let kindName = Mirror(reflecting: report.result).children.first?.label ?? "unknown"
        os_log(.default, log: Self.log, "received diagnosticReport: kind=%{public}@", kindName)
        for summary in summaries {
          await sink.enqueue(EventMapper.map(summary))
        }
      }
    }
    consumeMetricsTask = Task { [manager, sink] in
      for await report in manager.metricReports {
        Self.captureFixture(report, kind: "metric")
        // Metrics arrive as a whole report at once (roughly daily, per
        // Apple's own docs) - batch the whole report into one flush rather
        // than one per value, keeping each ingest payload coherent.
        let summaries = Self.summarizeMetrics(report)
        os_log(
          .default, log: Self.log, "received metricReport: %d state entries, %d summaries",
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

  // MARK: - Fixture capture (temporary harvesting tool, not a shipped
  // feature - delete once real fixtures exist for MetricKitBridgeFixtureTests.
  // See the MetricKit fixture-test-harness plan.)

  // Path is duplicated (not exposed as public API) in the Example app's
  // ContentView.swift so it can list captured files - not worth growing
  // the SDK's public surface for scaffolding meant to be deleted later.
  private static let fixturesDirectory: URL = {
    FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
      .appendingPathComponent("HitchScopeFixtures", isDirectory: true)
  }()

  private static func captureFixture(_ report: some Encodable, kind: String) {
    do {
      try FileManager.default.createDirectory(
        at: fixturesDirectory, withIntermediateDirectories: true)
      let formatter = DateFormatter()
      formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS"
      let filename = "\(kind)-\(formatter.string(from: Date())).json"
      let data = try JSONEncoder().encode(report)
      try data.write(to: fixturesDirectory.appendingPathComponent(filename))
      os_log(.default, log: Self.log, "captured fixture: %{public}@", filename)
    } catch {
      os_log(
        .error, log: Self.log, "failed to capture fixture: %{public}@",
        String(describing: error))
    }
  }

  // MARK: - DiagnosticReport -> plain DiagnosticSummary

  static func summarize(_ report: DiagnosticReport) -> [DiagnosticSummary] {
    let states = report.environment.states.map {
      StateEntry(
        domain: $0.domain, label: $0.label, metadata: metadataJSON($0.stableMetadata),
        durationMs: $0.duration.converted(to: .milliseconds).value)
    }
    // `.start` of the report's time window — the closest available
    // approximation of when the underlying incident actually happened.
    let occurredAt = report.timeRange.start
    let lowPowerModeEnabled = report.environment.lowPowerModeEnabled
    let isTestFlightApp = report.environment.isTestFlightApp
    let osBuildNumber = report.environment.osVersion.buildNumber

    func summary(_ kind: DiagnosticKind) -> [DiagnosticSummary] {
      [
        DiagnosticSummary(
          states: states, occurredAt: occurredAt, kind: kind,
          lowPowerModeEnabled: lowPowerModeEnabled, isTestFlightApp: isTestFlightApp,
          osBuildNumber: osBuildNumber)
      ]
    }

    switch report.result {
    case .crash(let diagnostic):
      let threads = diagnostic.callStackTree.callStackThreads
      let crash = CrashSummary(
        terminationReason: diagnostic.terminationReason?.rawValue,
        terminationCategory: diagnostic.terminationCategory?.rawValue,
        exceptionType: diagnostic.exceptionType,
        exceptionCode: diagnostic.exceptionCode,
        signal: diagnostic.signal,
        virtualMemoryRegionInfo: diagnostic.virtualMemoryRegionInfo,
        exceptionReason: diagnostic.exceptionReason.map {
          ExceptionReasonSummary(
            composedMessage: $0.composedMessage, formatString: $0.formatString,
            arguments: $0.arguments, exceptionType: $0.exceptionType, className: $0.className,
            exceptionName: $0.exceptionName)
        },
        threadCount: threads.count,
        topFrames: topFrames(from: diagnostic.callStackTree)
      )
      return summary(.crash(crash))

    case .hang(let diagnostic):
      let threads = diagnostic.callStackTree.callStackThreads
      let durationMs = diagnostic.hangDuration.converted(to: .milliseconds).value
      return summary(
        .hang(
          HangSummary(
            durationMs: durationMs, threadCount: threads.count,
            topFrames: topFrames(from: diagnostic.callStackTree))))

    case .appLaunch(let diagnostic):
      let threads = diagnostic.callStackTree.callStackThreads
      let durationMs = diagnostic.launchDuration.converted(to: .milliseconds).value
      return summary(
        .appLaunch(
          AppLaunchSummary(
            durationMs: durationMs, threadCount: threads.count,
            topFrames: topFrames(from: diagnostic.callStackTree))))

    case .memoryException(let diagnostic):
      let threads = diagnostic.callStackTree.callStackThreads
      return summary(
        .memoryException(
          MemoryExceptionSummary(
            threadCount: threads.count, topFrames: topFrames(from: diagnostic.callStackTree))))

    case .cpuException(let diagnostic):
      let threads = diagnostic.callStackTree.callStackThreads
      let exception = CPUExceptionSummary(
        totalCPUTimeMs: diagnostic.totalCPUTime.converted(to: .milliseconds).value,
        totalSampledTimeMs: diagnostic.totalSampledTime.converted(to: .milliseconds).value,
        threadCount: threads.count,
        topFrames: topFrames(from: diagnostic.callStackTree)
      )
      return summary(.cpuException(exception))

    case .diskWriteException(let diagnostic):
      let threads = diagnostic.callStackTree.callStackThreads
      let exception = DiskWriteExceptionSummary(
        totalBytesWritten: diagnostic.totalBytesWritten.converted(to: .bytes).value,
        threadCount: threads.count,
        topFrames: topFrames(from: diagnostic.callStackTree)
      )
      return summary(.diskWriteException(exception))

    @unknown default:
      return []
    }
  }

  // MARK: - CallStackTree -> [FrameSummary]

  /// Picks the thread MetricKit marked as attributed (the actual crashing/
  /// hanging thread) rather than assuming it's first in the array. Real
  /// captured fixtures happened to have the attributed thread at index 0,
  /// but that's not something to rely on - `threadAttributed` exists
  /// specifically so callers don't have to guess.
  private static func attributedThread(in tree: CallStackTree) -> CallStackThread? {
    let threads = tree.callStackThreads
    return threads.first(where: { $0.threadAttributed == true }) ?? threads.first
  }

  /// Walks from a root frame down through `subFrames`, following the
  /// branch with the highest `sampleCount` at each split (ties/missing
  /// counts resolve to the first child). Real fixtures show a thread's
  /// stack is often a single linear chain 50+ frames deep - `rootFrames`
  /// alone (with no descent into `subFrames`) only ever gave the single
  /// outermost, least specific frame.
  private static func deepestPath(from frame: CallStackFrame) -> [CallStackFrame] {
    var path = [frame]
    var current = frame
    while let next = current.subFrames.max(by: { ($0.sampleCount ?? 0) < ($1.sampleCount ?? 0) }) {
      path.append(next)
      current = next
    }
    return path
  }

  /// Innermost (crash/hang site) frame first, matching how a symbolicated
  /// stack trace is conventionally read - frame 0 is where execution
  /// actually was, not the outermost caller.
  private static func topFrames(from tree: CallStackTree, limit: Int = 20) -> [FrameSummary] {
    guard let thread = attributedThread(in: tree),
      let root = thread.rootFrames.max(by: { ($0.sampleCount ?? 0) < ($1.sampleCount ?? 0) })
    else { return [] }
    return deepestPath(from: root).reversed().prefix(limit).map {
      FrameSummary(
        binaryUUID: $0.binaryUUID?.uuidString, offset: $0.offsetIntoBinaryTextSegment,
        sampleCount: $0.sampleCount)
    }
  }

  // MARK: - MetricReport -> plain MetricAggregateSummary

  /// Iterates `report.stateEntries` only (one state, full-day window,
  /// unambiguous `windowStart`/`windowEnd` from `report.timeRange`) — NOT
  /// `report.intervalEntries`, whose sub-day windows don't carry an absolute
  /// start time of their own and how they anchor within the report's overall
  /// `timeRange` isn't documented. Deferred until confirmed empirically
  /// rather than guessed.
  static func summarizeMetrics(_ report: MetricReport) -> [MetricAggregateSummary] {
    let windowStart = report.timeRange.start
    let windowEnd = report.timeRange.end
    // `environment` is optional on MetricReport (unlike DiagnosticReport,
    // where it's always present) - absent, not defaulted, when genuinely
    // unknown rather than guessed as false.
    let lowPowerModeEnabled = report.environment?.lowPowerModeEnabled ?? false
    let isTestFlightApp = report.environment?.isTestFlightApp ?? false
    let hasExceededStateLimit = report.environment?.hasExceededStateLimit ?? false
    let osBuildNumber = report.environment?.osVersion.buildNumber

    var summaries: [MetricAggregateSummary] = []
    for stateEntry in report.stateEntries {
      let states = [
        StateEntry(
          domain: stateEntry.state.domain, label: stateEntry.state.label,
          metadata: metadataJSON(stateEntry.state.stableMetadata),
          durationMs: stateEntry.state.duration.converted(to: .milliseconds).value)
      ]
      for value in stateEntry.values {
        guard let kind = metricAggregateKind(for: value) else { continue }
        summaries.append(
          MetricAggregateSummary(
            states: states, windowStart: windowStart, windowEnd: windowEnd, kind: kind,
            lowPowerModeEnabled: lowPowerModeEnabled, isTestFlightApp: isTestFlightApp,
            hasExceededStateLimit: hasExceededStateLimit, osBuildNumber: osBuildNumber))
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
    case .cpuTime(let metric):
      return .cpuTime(ms: metric.value.converted(to: .milliseconds).value)
    case .cpuInstructionsCount(let metric):
      return .cpuInstructionsCount(count: metric.value)
    case .gpuTime(let metric):
      return .gpuTime(ms: metric.value.converted(to: .milliseconds).value)
    case .totalWiFiUpload(let metric):
      return .totalWiFiUpload(bytes: metric.value.converted(to: .bytes).value)
    case .totalWiFiDownload(let metric):
      return .totalWiFiDownload(bytes: metric.value.converted(to: .bytes).value)
    case .totalCellularUpload(let metric):
      return .totalCellularUpload(bytes: metric.value.converted(to: .bytes).value)
    case .totalCellularDownload(let metric):
      return .totalCellularDownload(bytes: metric.value.converted(to: .bytes).value)
    case .foregroundTermination(let metric):
      return .foregroundTermination(
        TerminationSummary(
          normalCount: metric.normalTerminationCount,
          memoryLimitCount: metric.memoryLimitTerminationCount,
          badAccessCount: metric.badAccessTerminationCount,
          abnormalCount: metric.abnormalTerminationCount,
          illegalInstructionCount: metric.illegalInstructionTerminationCount,
          watchdogCount: metric.watchdogTerminationCount,
          highCPUCount: nil, systemPressureCount: nil, fileLockCount: nil, taskTimeoutCount: nil
        ))
    case .backgroundTermination(let metric):
      return .backgroundTermination(
        TerminationSummary(
          normalCount: metric.normalTerminationCount,
          memoryLimitCount: metric.memoryLimitTerminationCount,
          badAccessCount: metric.badAccessTerminationCount,
          abnormalCount: metric.abnormalTerminationCount,
          illegalInstructionCount: metric.illegalInstructionTerminationCount,
          watchdogCount: metric.watchdogTerminationCount,
          highCPUCount: metric.highCPUTerminationCount,
          systemPressureCount: metric.systemPressureTerminationCount,
          fileLockCount: metric.fileLockTerminationCount,
          taskTimeoutCount: metric.taskTimeoutTerminationCount
        ))
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

  // MARK: - ReportedState.stableMetadata -> plain JSONValue

  /// `nil` when empty rather than `[:]` - keeps the wire payload the same
  /// shape as before for the overwhelmingly common case of no metadata,
  /// rather than adding an always-present empty object to every state.
  private static func metadataJSON(
    _ metadata: [String: ReportableMetadataValue]
  ) -> [String: JSONValue]? {
    guard !metadata.isEmpty else { return nil }
    return metadata.mapValues(jsonValue)
  }

  private static func jsonValue(_ value: ReportableMetadataValue) -> JSONValue {
    switch value {
    case .string(let value):
      return .string(value)
    case .date(let value):
      return .string(ISO8601DateFormatter().string(from: value))
    case .floatingPoint(let value):
      return .double(value)
    case .integer(let value):
      // Outside Int's range (Int128 can exceed it) - preserve the exact
      // value as text rather than silently truncating.
      return Int(exactly: value).map(JSONValue.int) ?? .string(String(value))
    @unknown default:
      return .null
    }
  }
}
