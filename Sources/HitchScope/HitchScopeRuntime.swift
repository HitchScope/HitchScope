import Foundation
import os.log

actor HitchScopeRuntime {
  static let shared = HitchScopeRuntime()

  private static let log = OSLog(subsystem: "com.hitchscope.sdk", category: "HitchScope")
  private static let baseURL = URL(string: "https://hitchscope.onrender.com")!
  private static let bufferLimit = 500

  private var apiKey: String?
  private var declaredDomains: Set<String> = []
  private var bridge: MetricKitBridge?
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

    os_log(
      .info, log: Self.log, "configured with domains: %{public}@",
      trackedStates.sorted().joined(separator: ", "))

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
    await bridge?.reportState(
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
    await bridge?.updateVolatileMetadata(domain: domain, metadata: metadata)
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
    let result = await client.send(
      appVersion: DeviceMetadata.appVersion,
      osVersion: DeviceMetadata.osVersion,
      deviceModel: DeviceMetadata.deviceModel,
      events: pending
    )
    switch result {
    case .success(let accepted):
      // Only clear what we actually sent — more may have been enqueued
      // concurrently while this flush was in flight.
      buffer.removeFirst(min(pending.count, buffer.count))
      os_log(.info, log: Self.log, "flushed %d diagnostic event(s)", accepted)
    case .failure(let error):
      os_log(
        .error, log: Self.log, "flush failed, will retry on next event: %{public}@",
        String(describing: error))
    }
  }

  private func flushMetrics() async {
    guard let apiKey, !metricBuffer.isEmpty else { return }
    let client = IngestClient(baseURL: Self.baseURL, apiKey: apiKey)
    let pending = metricBuffer
    let result = await client.sendMetrics(
      appVersion: DeviceMetadata.appVersion,
      osVersion: DeviceMetadata.osVersion,
      deviceModel: DeviceMetadata.deviceModel,
      metrics: pending
    )
    switch result {
    case .success(let accepted):
      metricBuffer.removeFirst(min(pending.count, metricBuffer.count))
      os_log(.info, log: Self.log, "flushed %d metric aggregate(s)", accepted)
    case .failure(let error):
      os_log(
        .error, log: Self.log, "metrics flush failed, will retry on next report: %{public}@",
        String(describing: error))
    }
  }
}
