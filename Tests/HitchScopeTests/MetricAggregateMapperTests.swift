import XCTest

@testable import HitchScope

final class MetricAggregateMapperTests: XCTestCase {
  private let windowStart = Date(timeIntervalSince1970: 1_700_000_000)
  private let windowEnd = Date(timeIntervalSince1970: 1_700_086_400)
  private let states = [StateEntry(domain: "com.app.screen", label: "Checkout")]

  private func summary(_ kind: MetricAggregateKind) -> MetricAggregateSummary {
    MetricAggregateSummary(
      states: states, windowStart: windowStart, windowEnd: windowEnd, kind: kind)
  }

  func testHitchTimeMapsRatioAndTotalsDirectly() {
    let event = MetricAggregateMapper.map(
      summary(.hitchTime(ratio: 0.071, totalHitchMs: 21_300, totalAnimationMs: 300_000)))

    XCTAssertEqual(event.kind, "hitchTime")
    XCTAssertEqual(event.hitchRatio, 0.071)
    XCTAssertEqual(event.totalHitchMs, 21_300)
    XCTAssertEqual(event.totalAnimMs, 300_000)
    XCTAssertNil(event.p50Ms)
    XCTAssertEqual(event.states, states)
    XCTAssertEqual(event.windowStart, windowStart)
    XCTAssertEqual(event.windowEnd, windowEnd)
  }

  func testPeakMemoryMapsDirectly() {
    let event = MetricAggregateMapper.map(summary(.peakMemory(megabytes: 312.5)))

    XCTAssertEqual(event.kind, "peakMemory")
    XCTAssertEqual(event.peakMemoryMB, 312.5)
  }

  func testGenericKindDecodesRawFromEncodedValue() throws {
    let encoded = try JSONEncoder().encode(["valueMs": 4200])
    let event = MetricAggregateMapper.map(
      summary(.generic(kindName: "cpuTime", encodedValue: encoded)))

    XCTAssertEqual(event.kind, "cpuTime")
    XCTAssertNil(event.p50Ms)
    XCTAssertNil(event.hitchRatio)
    guard case .int(4200) = event.raw["valueMs"] else {
      return XCTFail("expected valueMs to survive the generic capture path")
    }
  }

  func testGenericKindWithUndecodableValueFallsBackToEmptyRaw() {
    // A JSON array, not an object - [String: JSONValue] decode should fail
    // gracefully rather than crash.
    let encoded = Data("[1,2,3]".utf8)
    let event = MetricAggregateMapper.map(
      summary(.generic(kindName: "weird", encodedValue: encoded)))

    XCTAssertEqual(event.kind, "weird")
    // The generic decode contributes nothing beyond the three report-context
    // keys every event carries, regardless of kind.
    XCTAssertEqual(event.raw.count, 3)
    guard case .bool(false) = event.raw["lowPowerModeEnabled"] else {
      return XCTFail("expected lowPowerModeEnabled context key even when generic decode fails")
    }
  }

  // MARK: - Histogram percentile stats

  func testPercentileStatsOnEmptyHistogram() {
    let stats = MetricAggregateMapper.percentileStats(buckets: [])

    XCTAssertEqual(stats.sampleCount, 0)
    XCTAssertNil(stats.p50Ms)
    XCTAssertNil(stats.p95Ms)
    XCTAssertNil(stats.meanMs)
  }

  func testPercentileStatsOnSingleBucket() {
    let stats = MetricAggregateMapper.percentileStats(
      buckets: [BucketSummary(lowerBoundMs: 100, upperBoundMs: 200, count: 10)])

    XCTAssertEqual(stats.sampleCount, 10)
    XCTAssertEqual(stats.p50Ms, 150)
    XCTAssertEqual(stats.p95Ms, 150)
    XCTAssertEqual(stats.meanMs, 150)
  }

  func testPercentileStatsAcrossMultipleBuckets() {
    // 38 samples in [0,500), 4 samples in [500,2000) - p50 should land in
    // the first bucket, p95 should land in the second.
    let stats = MetricAggregateMapper.percentileStats(
      buckets: [
        BucketSummary(lowerBoundMs: 0, upperBoundMs: 500, count: 38),
        BucketSummary(lowerBoundMs: 500, upperBoundMs: 2000, count: 4),
      ])

    XCTAssertEqual(stats.sampleCount, 42)
    XCTAssertEqual(stats.p50Ms, 250)  // midpoint of the first bucket
    XCTAssertEqual(stats.p95Ms, 1250)  // midpoint of the second bucket
  }

  func testPercentileStatsHandlesUnsortedBuckets() {
    let stats = MetricAggregateMapper.percentileStats(
      buckets: [
        BucketSummary(lowerBoundMs: 500, upperBoundMs: 2000, count: 4),
        BucketSummary(lowerBoundMs: 0, upperBoundMs: 500, count: 38),
      ])

    XCTAssertEqual(stats.p50Ms, 250, "should sort by lowerBound before walking cumulative counts")
  }
}
