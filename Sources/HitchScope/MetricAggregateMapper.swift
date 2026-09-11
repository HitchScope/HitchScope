import Foundation

/// Pure mapping from a `MetricAggregateSummary` to the wire-format
/// `MetricAggregateIngestEvent`. Plain types only — no Apple framework
/// types, no availability annotation, fully unit-testable.
enum MetricAggregateMapper {
  static func map(_ summary: MetricAggregateSummary) -> MetricAggregateIngestEvent {
    switch summary.kind {
    case .hangTime(let buckets):
      let stats = percentileStats(buckets: buckets)
      return event(
        summary, kind: "hangTime",
        sampleCount: stats.sampleCount, p50Ms: stats.p50Ms, p95Ms: stats.p95Ms,
        meanMs: stats.meanMs,
        raw: rawFromBuckets(buckets)
      )

    case .hitchTime(let ratio, let totalHitchMs, let totalAnimationMs):
      return event(
        summary, kind: "hitchTime",
        hitchRatio: ratio, totalHitchMs: totalHitchMs, totalAnimMs: totalAnimationMs,
        raw: [
          "ratio": .double(ratio),
          "totalHitchTime": .double(totalHitchMs),
          "totalAnimationTime": .double(totalAnimationMs),
        ]
      )

    case .extendedLaunch(let buckets):
      let stats = percentileStats(buckets: buckets)
      return event(
        summary, kind: "extendedLaunch",
        sampleCount: stats.sampleCount, p50Ms: stats.p50Ms, p95Ms: stats.p95Ms,
        meanMs: stats.meanMs,
        raw: rawFromBuckets(buckets)
      )

    case .peakMemory(let megabytes):
      return event(
        summary, kind: "peakMemory",
        peakMemoryMB: megabytes,
        raw: ["valueMB": .double(megabytes)]
      )

    case .generic(let kindName, let encodedValue):
      let raw = (try? JSONDecoder().decode([String: JSONValue].self, from: encodedValue)) ?? [:]
      return event(summary, kind: kindName, raw: raw)
    }
  }

  // MARK: - Histogram -> percentile stats

  struct PercentileStats {
    let sampleCount: Int
    let p50Ms: Double?
    let p95Ms: Double?
    let meanMs: Double?
  }

  /// Estimates sample count, p50, p95, and mean from histogram buckets.
  /// Percentiles are estimated as the midpoint of the bucket containing the
  /// target cumulative-count rank — a simple, defensible approximation given
  /// only bucketed data, not exact sample-level percentiles.
  static func percentileStats(buckets: [BucketSummary]) -> PercentileStats {
    let totalCount = buckets.reduce(0) { $0 + $1.count }
    guard totalCount > 0 else {
      return PercentileStats(sampleCount: 0, p50Ms: nil, p95Ms: nil, meanMs: nil)
    }

    let sorted = buckets.sorted { $0.lowerBoundMs < $1.lowerBoundMs }

    func percentile(_ p: Double) -> Double {
      let targetRank = p * Double(totalCount)
      var cumulative = 0
      for bucket in sorted {
        cumulative += bucket.count
        if Double(cumulative) >= targetRank {
          return (bucket.lowerBoundMs + bucket.upperBoundMs) / 2
        }
      }
      let last = sorted[sorted.count - 1]
      return (last.lowerBoundMs + last.upperBoundMs) / 2
    }

    let weightedSum = sorted.reduce(0.0) { sum, bucket in
      sum + (bucket.lowerBoundMs + bucket.upperBoundMs) / 2 * Double(bucket.count)
    }

    return PercentileStats(
      sampleCount: totalCount,
      p50Ms: percentile(0.5),
      p95Ms: percentile(0.95),
      meanMs: weightedSum / Double(totalCount)
    )
  }

  private static func rawFromBuckets(_ buckets: [BucketSummary]) -> [String: JSONValue] {
    [
      "buckets": .array(
        buckets.map {
          .object([
            "lowerBoundMs": .double($0.lowerBoundMs),
            "upperBoundMs": .double($0.upperBoundMs),
            "count": .int($0.count),
          ])
        })
    ]
  }

  private static func event(
    _ summary: MetricAggregateSummary,
    kind: String,
    sampleCount: Int? = nil,
    p50Ms: Double? = nil,
    p95Ms: Double? = nil,
    meanMs: Double? = nil,
    hitchRatio: Double? = nil,
    totalHitchMs: Double? = nil,
    totalAnimMs: Double? = nil,
    peakMemoryMB: Double? = nil,
    raw: [String: JSONValue]
  ) -> MetricAggregateIngestEvent {
    MetricAggregateIngestEvent(
      kind: kind,
      states: summary.states,
      windowStart: summary.windowStart,
      windowEnd: summary.windowEnd,
      sampleCount: sampleCount,
      p50Ms: p50Ms,
      p95Ms: p95Ms,
      meanMs: meanMs,
      hitchRatio: hitchRatio,
      totalHitchMs: totalHitchMs,
      totalAnimMs: totalAnimMs,
      peakMemoryMB: peakMemoryMB,
      raw: raw
    )
  }
}
