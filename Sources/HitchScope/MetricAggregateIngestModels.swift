import Foundation

/// One metric aggregate as sent over the wire to `POST /v1/ingest-metrics`.
/// `kind` is MetricKit's own case name ("hangTime", "cpuTime", ...) - a
/// plain string, not a shared enum with the backend, so new MetricKit cases
/// in a future OS need no SDK/backend coordination. Only the "hero" kinds
/// (hangTime/hitchTime/extendedLaunch/peakMemory) populate the summary
/// fields; everything else leaves them nil and relies on `raw`.
struct MetricAggregateIngestEvent: Codable, Sendable {
  let kind: String
  let states: [StateEntry]
  let windowStart: Date
  let windowEnd: Date
  let sampleCount: Int?
  let p50Ms: Double?
  let p95Ms: Double?
  let meanMs: Double?
  let hitchRatio: Double?
  let totalHitchMs: Double?
  let totalAnimMs: Double?
  let peakMemoryMB: Double?
  let raw: [String: JSONValue]
}

struct MetricAggregateIngestRequest: Codable, Sendable {
  let appVersion: String
  let osVersion: String
  let deviceModel: String
  let metrics: [MetricAggregateIngestEvent]
}
