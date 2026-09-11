import Foundation

/// A single bucket from a MetricKit `Histogram`, captured plainly (bounds
/// already converted to milliseconds).
struct BucketSummary: Sendable {
  let lowerBoundMs: Double
  let upperBoundMs: Double
  let count: Int
}

enum MetricAggregateKind: Sendable {
  case hangTime(buckets: [BucketSummary])
  case hitchTime(ratio: Double, totalHitchMs: Double, totalAnimationMs: Double)
  case extendedLaunch(buckets: [BucketSummary])
  case peakMemory(megabytes: Double)
  /// Every other `MetricResult` case (there are ~20: CPU, GPU, network,
  /// disk, location, background time, signposts, etc.) — captured
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
}
