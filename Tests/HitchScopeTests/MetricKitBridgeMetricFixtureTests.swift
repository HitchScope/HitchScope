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
/// Four fixtures, three deliberately different shapes:
/// - `metric-20260913T053136.820` and `metric-20260914T051245.159`:
///   `stateEntries` is empty. `summarizeMetrics` is a clean, non-crashing
///   no-op on these - but `summarizeFullDayInterval` (see below) recovers
///   real data from `intervalEntries` on both.
/// - `metric-20260913T053136.822`: real multi-domain, multi-state data -
///   the same report already visible in the live dashboard, so its
///   expectations below were cross-checked against `/v1/metric-aggregates`
///   independently of this test, not just re-derived from
///   `MetricKitBridge`'s own logic.
/// - `metric-20260914T051245.161`: a shape none of the other three cover -
///   `stateEntries` is non-empty (5 real states, both domains, one with
///   `userTier` stableMetadata) but every entry's `values` array is itself
///   empty. Confirms `summarizeMetrics` walks real multi-domain state data
///   without producing spurious empty-metric summaries, rather than that
///   emptiness alone (as with `.820`/`.159`) is what keeps it quiet - and
///   that this is exactly the case `summarizeFullDayInterval` recovers: this
///   report's real metric data (hitch ratio, a memory-limit termination,
///   etc.) exists only in `intervalEntries.fullDayEntry`, nowhere else.
///
/// All four fixtures also exercise `summarizeFullDayInterval(_:)`, which
/// reads `report.intervalEntries.fullDayEntry` - the one `intervalEntries`
/// entry Apple's own `MetricKit` framework singles out as spanning the
/// report's entire `timeRange` - independently of whatever `summarizeMetrics`
/// found. Every fixture here happens to carry a `fullDayEntry`, so every one
/// of these tests exercises real recovered data, not a synthetic case.
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
    for name in ["metric-20260913T053136.820", "metric-20260914T051245.159"] {
      let report = try loadFixture(name)
      XCTAssertTrue(
        report.stateEntries.isEmpty, "\(name): fixture assumption: this report has no stateEntries")

      let summaries = MetricKitBridge.summarizeMetrics(report)

      XCTAssertTrue(
        summaries.isEmpty,
        "\(name): a stateEntries-empty report should produce zero summaries today")
    }
  }

  /// Independently counted from the raw fixture JSON (not derived from
  /// `summarizeMetrics`' own logic): 5 real state entries - both domains,
  /// one with `userTier` stableMetadata - but every entry's `values` array
  /// is empty, so `summarizeMetrics` still produces zero summaries. Unlike
  /// `.820`/`.159` above, that emptiness isn't because `stateEntries` itself
  /// is empty.
  func testStateOnlyMultiDomainReportProducesNoSummaries() throws {
    let report = try loadFixture("metric-20260914T051245.161")

    XCTAssertEqual(report.stateEntries.count, 5)
    for stateEntry in report.stateEntries {
      XCTAssertTrue(stateEntry.values.isEmpty)
    }
    let domains = Set(report.stateEntries.map(\.state.domain))
    XCTAssertTrue(domains.contains("com.hitchscope.example.screen"))
    XCTAssertTrue(domains.contains("com.hitchscope.example.experiment.checkout_redesign"))

    let summaries = MetricKitBridge.summarizeMetrics(report)
    XCTAssertTrue(
      summaries.isEmpty,
      "every real stateEntry has empty values, so summarizeMetrics should still produce nothing")
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

  // MARK: - summarizeFullDayInterval

  /// Independently counted from the raw fixture JSON: both `.820` and
  /// `.159` have a single `intervalEntries` entry (duration 0s, matching
  /// their own zero-length `timeRange`) carrying exactly 3 values
  /// (`totalFileCount`/`totalFileSize`/`totalDiskSpaceCapacity`) and no
  /// states. Before this SDK change, that data was silently dropped
  /// entirely - `summarizeMetrics` alone produces zero summaries for these
  /// two reports (see `testIntervalEntriesOnlyReportProducesNoSummariesWithoutCrashing`).
  func testFullDayIntervalRecoversDiskMetricsPreviouslyDropped() throws {
    for name in ["metric-20260913T053136.820", "metric-20260914T051245.159"] {
      let report = try loadFixture(name)
      let summaries = MetricKitBridge.summarizeFullDayInterval(report)

      XCTAssertEqual(summaries.count, 3, "\(name)")
      for summary in summaries {
        XCTAssertEqual(summary.source, .fullDayInterval, "\(name)")
        XCTAssertTrue(summary.states.isEmpty, "\(name)")
      }
    }
  }

  /// Independently counted from the raw fixture JSON: `.161`'s
  /// `intervalEntries.fullDayEntry` (the 86400s entry) carries 25 values and
  /// 5 states across both domains - the exact real data this report's
  /// `stateEntries` (see `testStateOnlyMultiDomainReportProducesNoSummaries`)
  /// carries none of, despite listing the same states. This is the
  /// "N states, 0 summaries" production case the fix targets.
  func testFullDayIntervalRecoversDataStateEntriesMissedEntirely() throws {
    let report = try loadFixture("metric-20260914T051245.161")
    let summaries = MetricKitBridge.summarizeFullDayInterval(report)

    XCTAssertEqual(summaries.count, 25)
    for summary in summaries { XCTAssertEqual(summary.source, .fullDayInterval) }

    let domains = Set(summaries.flatMap { $0.states.map(\.domain) })
    XCTAssertTrue(domains.contains("com.hitchscope.example.screen"))
    XCTAssertTrue(domains.contains("com.hitchscope.example.experiment.checkout_redesign"))

    // summarizeMetrics (the stateEntries path) is untouched by this change -
    // still zero, proving recovery comes from the new path alone.
    XCTAssertTrue(MetricKitBridge.summarizeMetrics(report).isEmpty)
  }

  /// Independently counted from the raw fixture JSON: `.822`'s
  /// `intervalEntries.fullDayEntry` carries 24 values and 4 states - real
  /// data *in addition to* the 18 `stateEntries`-derived summaries already
  /// covered by `testRealMultiStateReportProducesExpectedKindCounts`, not a
  /// replacement for them. Confirms the two sources are additive and
  /// distinctly tagged, not merged or double-reporting the same rows.
  func testFullDayIntervalAddsToExistingStateSnapshotSummaries() throws {
    let report = try loadFixture("metric-20260913T053136.822")

    let stateSnapshotSummaries = MetricKitBridge.summarizeMetrics(report)
    let intervalSummaries = MetricKitBridge.summarizeFullDayInterval(report)

    XCTAssertEqual(stateSnapshotSummaries.count, 18)
    XCTAssertEqual(intervalSummaries.count, 24)
    for summary in stateSnapshotSummaries { XCTAssertEqual(summary.source, .stateSnapshot) }
    for summary in intervalSummaries { XCTAssertEqual(summary.source, .fullDayInterval) }
  }

  func testEveryRealSummaryMapsToAnIngestEventWithoutCrashing() throws {
    for name in [
      "metric-20260913T053136.820", "metric-20260913T053136.822",
      "metric-20260914T051245.159", "metric-20260914T051245.161",
    ] {
      let report = try loadFixture(name)
      let summaries =
        MetricKitBridge.summarizeMetrics(report)
        + MetricKitBridge
        .summarizeFullDayInterval(report)
      for summary in summaries {
        _ = MetricAggregateMapper.map(summary)
      }
    }
  }
}
