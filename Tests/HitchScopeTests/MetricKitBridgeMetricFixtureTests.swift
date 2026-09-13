import MetricKit
import XCTest

@testable import HitchScope

/// Exercises `MetricKitBridge.summarizeMetrics(_:)` against real
/// `MetricReport` JSON captured on a physical device - mirrors
/// `MetricKitBridgeFixtureTests`' fixture-based approach for
/// `DiagnosticReport`, for the same reason: `MetricReport` has no public
/// initializer, so decoding a real capture is the only way to construct one
/// for a test, and hand-written doubles can't prove the real wire format
/// parses correctly.
///
/// Two fixtures, deliberately different shapes:
/// - `metric-20260913T053136.820`: `stateEntries` is empty - all of this
///   report's real content lives in `intervalEntries`, which
///   `summarizeMetrics` doesn't read (see the future-roadmap note on
///   `intervalEntries`). Confirms that's a clean, non-crashing no-op today,
///   not silently mishandled data.
/// - `metric-20260913T053136.822`: real multi-domain, multi-state data -
///   the same report already visible in the live dashboard, so its
///   expectations below were cross-checked against `/v1/metric-aggregates`
///   independently of this test, not just re-derived from
///   `MetricKitBridge`'s own logic.
final class MetricKitBridgeMetricFixtureTests: XCTestCase {
  private func loadFixture(_ name: String) throws -> MetricReport {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      "fixture \(name).json not found in test bundle")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(MetricReport.self, from: data)
  }

  private func kindName(for summary: MetricAggregateSummary) -> String {
    switch summary.kind {
    case .hangTime: return "hangTime"
    case .hitchTime: return "hitchTime"
    case .extendedLaunch: return "extendedLaunch"
    case .peakMemory: return "peakMemory"
    case .cpuTime: return "cpuTime"
    case .cpuInstructionsCount: return "cpuInstructionsCount"
    case .gpuTime: return "gpuTime"
    case .totalWiFiUpload: return "totalWiFiUpload"
    case .totalWiFiDownload: return "totalWiFiDownload"
    case .totalCellularUpload: return "totalCellularUpload"
    case .totalCellularDownload: return "totalCellularDownload"
    case .foregroundTermination: return "foregroundTermination"
    case .backgroundTermination: return "backgroundTermination"
    case .generic(let kindName, _): return kindName
    }
  }

  func testIntervalEntriesOnlyReportProducesNoSummariesWithoutCrashing() throws {
    let report = try loadFixture("metric-20260913T053136.820")
    XCTAssertTrue(
      report.stateEntries.isEmpty, "fixture assumption: this report has no stateEntries")

    let summaries = MetricKitBridge.summarizeMetrics(report)

    XCTAssertTrue(
      summaries.isEmpty, "a stateEntries-empty report should produce zero summaries today")
  }

  /// Independently counted from the raw fixture JSON (not derived from
  /// `summarizeMetrics`' own logic): 4 state entries -
  /// (variant_b: 7 kinds), (home: 0 kinds), (detail: 4 kinds), (home: 7
  /// kinds) = 18 total. Matches the 18 rows this exact report produced in
  /// the live backend.
  func testRealMultiStateReportProducesExpectedKindCounts() throws {
    let report = try loadFixture("metric-20260913T053136.822")
    let summaries = MetricKitBridge.summarizeMetrics(report)

    XCTAssertEqual(summaries.count, 18)

    var counts: [String: Int] = [:]
    for summary in summaries { counts[kindName(for: summary), default: 0] += 1 }

    XCTAssertEqual(counts["hangTime"], 2)
    XCTAssertEqual(counts["foregroundTermination"], 2)
    XCTAssertEqual(counts["backgroundTermination"], 2)
    XCTAssertEqual(counts["timeToFirstDraw"], 3)
    XCTAssertEqual(counts["applicationResumeTime"], 3)
    XCTAssertEqual(counts["optimizedTimeToFirstDraw"], 3)
    XCTAssertEqual(counts["extendedLaunch"], 3)
  }

  func testRealMultiStateReportCoversBothDomains() throws {
    let report = try loadFixture("metric-20260913T053136.822")
    let summaries = MetricKitBridge.summarizeMetrics(report)

    let domains = Set(summaries.flatMap { $0.states.map(\.domain) })
    XCTAssertTrue(domains.contains("com.hitchscope.example.screen"))
    XCTAssertTrue(domains.contains("com.hitchscope.example.experiment.checkout_redesign"))
  }

  /// The real hangTime histogram has 2 buckets - 340-349ms (count 1) and
  /// 2000-2009ms (count 1), independently read from the raw JSON. Confirms
  /// bucket conversion to milliseconds is exact, not just present.
  func testRealHangTimeBucketsMatchRawFixture() throws {
    let report = try loadFixture("metric-20260913T053136.822")
    let summaries = MetricKitBridge.summarizeMetrics(report)

    let hangTimeSummaries = summaries.filter {
      if case .hangTime = $0.kind { return true }
      return false
    }
    XCTAssertEqual(hangTimeSummaries.count, 2)

    for summary in hangTimeSummaries {
      guard case .hangTime(let buckets) = summary.kind else { continue }
      XCTAssertEqual(buckets.count, 2)
      let sorted = buckets.sorted { $0.lowerBoundMs < $1.lowerBoundMs }
      XCTAssertEqual(sorted[0].lowerBoundMs, 340)
      XCTAssertEqual(sorted[0].upperBoundMs, 349)
      XCTAssertEqual(sorted[0].count, 1)
      XCTAssertEqual(sorted[1].lowerBoundMs, 2000)
      XCTAssertEqual(sorted[1].upperBoundMs, 2009)
      XCTAssertEqual(sorted[1].count, 1)
    }
  }

  func testRealMultiStateReportEnvironmentContext() throws {
    let report = try loadFixture("metric-20260913T053136.822")
    let summaries = MetricKitBridge.summarizeMetrics(report)

    let summary = try XCTUnwrap(summaries.first)
    XCTAssertFalse(summary.isTestFlightApp)
    XCTAssertFalse(summary.lowPowerModeEnabled)
    XCTAssertFalse(summary.hasExceededStateLimit)
    XCTAssertEqual(summary.osBuildNumber, "24A435")
  }

  func testEveryRealSummaryMapsToAnIngestEventWithoutCrashing() throws {
    for name in ["metric-20260913T053136.820", "metric-20260913T053136.822"] {
      let report = try loadFixture(name)
      for summary in MetricKitBridge.summarizeMetrics(report) {
        _ = MetricAggregateMapper.map(summary)
      }
    }
  }
}
