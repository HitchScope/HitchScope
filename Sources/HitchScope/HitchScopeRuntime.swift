import Foundation
import os.log

actor HitchScopeRuntime {
  static let shared = HitchScopeRuntime()

  private static let log = OSLog(subsystem: "com.hitchscope.sdk", category: "HitchScope")
  private static let baseURL = URL(string: "https://api.hitchscope.com")!
  private static let bufferLimit = 500

  private var apiKey: String?
  private var declaredDomains: Set<String> = []
  // Type-erased: MetricKitBridge is iOS 27+ only, but this actor itself
  // must stay available at the package's lower floor so the public API
  // (HitchScope.configure/reportState/updateVolatileMetadata) is callable
  // unconditionally from any app code - it simply never gets constructed,
  // and every use of it below is behind its own `#available` check, on
  // earlier OS versions.
  private var bridge: Any?
  private var buffer: [IngestEvent] = []
  private var metricBuffer: [MetricAggregateIngestEvent] = []

  /// Set right before a guard's early return in `reportState`/
  /// `updateVolatileMetadata` — a lightweight, test-only observability
  /// seam so guard behavior is assertable without mocking `MetricKitBridge`
  /// (which would require abstracting it behind a protocol purely for
  /// testing, more machinery than this warrants). `nil` after a call that
  /// passed both guards.
  private(set) var lastRejectionReason: String?

  // Not private: tests construct fresh instances directly rather than
  // sharing `.shared`'s process-lifetime state (start() is intentionally
  // idempotent, which would otherwise make guard behavior untestable
  // across multiple test methods in the same process).
  init() {}

  /// Test-only seam: exercises the guard logic in `reportState`/
  /// `updateVolatileMetadata` without constructing a real `MetricKitBridge`
  /// (which requires a live `MetricManager`).
  func setDeclaredDomainsForTesting(_ domains: Set<String>) {
    declaredDomains = domains
  }

  func start(apiKey: String, trackedStates: Set<String>) {
    guard self.apiKey == nil else { return }  // idempotent: ignore a second configure()
    self.apiKey = apiKey
    self.declaredDomains = trackedStates

    // .default, not .info - .info is only kept in a volatile memory buffer
    // and routinely evicted before anyone looks, especially outside a live
    // Xcode session; .default is what actually persists to disk.
    os_log(
      .default, log: Self.log, "configured with domains: %{public}@",
      trackedStates.sorted().joined(separator: ", "))

    guard #available(iOS 27, *) else {
      os_log(
        .default, log: Self.log,
        "running as a no-op on this OS version - HitchScope requires iOS 27+")
      return
    }
    let bridge = MetricKitBridge(domains: trackedStates, sink: self)
    self.bridge = bridge
    Task { await bridge.start() }
  }

  func reportState(
    domain: String, label: String?, stableMetadata: [String: HitchScopeMetadataValue],
    volatileMetadata: [String: HitchScopeMetadataValue]
  ) async {
    guard declaredDomains.contains(domain) else {
      lastRejectionReason = "undeclaredDomain"
      os_log(
        .error, log: Self.log,
        "reportState(%{public}@, ...) ignored: domain was not declared in configure(trackedStates:)",
        domain)
      return
    }
    // Apple's API treats nil as "clear the active state" but crashes the
    // process on an empty string — refuse rather than forward it.
    if let label, label.isEmpty {
      lastRejectionReason = "emptyLabel"
      os_log(
        .error, log: Self.log,
        "reportState(%{public}@, label: \"\") ignored: pass nil to clear a state, not an empty string",
        domain)
      return
    }
    lastRejectionReason = nil
    guard #available(iOS 27, *), let bridge = bridge as? MetricKitBridge else { return }
    await bridge.reportState(
      domain: domain, label: label, stableMetadata: stableMetadata,
      volatileMetadata: volatileMetadata)
  }

  func updateVolatileMetadata(domain: String, metadata: [String: HitchScopeMetadataValue]) async {
    guard declaredDomains.contains(domain) else {
      lastRejectionReason = "undeclaredDomain"
      os_log(
        .error, log: Self.log,
        "updateVolatileMetadata(%{public}@, ...) ignored: domain was not declared in configure(trackedStates:)",
        domain)
      return
    }
    lastRejectionReason = nil
    guard #available(iOS 27, *), let bridge = bridge as? MetricKitBridge else { return }
    await bridge.updateVolatileMetadata(domain: domain, metadata: metadata)
  }

  func enqueue(_ event: IngestEvent) async {
    buffer.append(event)
    if buffer.count > Self.bufferLimit {
      buffer.removeFirst(buffer.count - Self.bufferLimit)
    }
    await flush()
  }

  /// Metric aggregates arrive as a whole `MetricReport` at once (roughly
  /// daily), already batched by the caller — appended and flushed together
  /// rather than triggering one flush per value.
  func enqueueMetrics(_ events: [MetricAggregateIngestEvent]) async {
    guard !events.isEmpty else { return }
    metricBuffer.append(contentsOf: events)
    if metricBuffer.count > Self.bufferLimit {
      metricBuffer.removeFirst(metricBuffer.count - Self.bufferLimit)
    }
    await flushMetrics()
  }

  private func flush() async {
    guard let apiKey, !buffer.isEmpty else { return }
    let client = IngestClient(baseURL: Self.baseURL, apiKey: apiKey)
    let pending = buffer
    let outcome = await client.send(
      appVersion: DeviceMetadata.appVersion,
      osVersion: DeviceMetadata.osVersion,
      deviceModel: DeviceMetadata.deviceModel,
      events: pending
    )
    // Drop whatever was actually sent, even on a partial failure (some
    // chunks succeeded before one failed) — more may also have been
    // enqueued concurrently while this flush was in flight, so this can
    // never remove more than `pending`'s own prefix.
    if outcome.sentCount > 0 {
      buffer.removeFirst(min(outcome.sentCount, buffer.count))
    }
    if let error = outcome.error {
      os_log(
        .error, log: Self.log, "flush failed, will retry on next event: %{public}@",
        String(describing: error))
    } else {
      os_log(.default, log: Self.log, "flushed %d diagnostic event(s)", outcome.accepted)
    }
  }

  private func flushMetrics() async {
    guard let apiKey, !metricBuffer.isEmpty else { return }
    let client = IngestClient(baseURL: Self.baseURL, apiKey: apiKey)
    let pending = metricBuffer
    let outcome = await client.sendMetrics(
      appVersion: DeviceMetadata.appVersion,
      osVersion: DeviceMetadata.osVersion,
      deviceModel: DeviceMetadata.deviceModel,
      metrics: pending
    )
    if outcome.sentCount > 0 {
      metricBuffer.removeFirst(min(outcome.sentCount, metricBuffer.count))
    }
    if let error = outcome.error {
      os_log(
        .error, log: Self.log, "metrics flush failed, will retry on next report: %{public}@",
        String(describing: error))
    } else {
      os_log(.default, log: Self.log, "flushed %d metric aggregate(s)", outcome.accepted)
    }
  }
}
