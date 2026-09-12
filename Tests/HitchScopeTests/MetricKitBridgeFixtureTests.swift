import MetricKit
import XCTest

@testable import HitchScope

/// Exercises `MetricKitBridge.summarize(_:)` against real `DiagnosticReport`
/// JSON captured on a physical device (via the SDK's own fixture-harvesting
/// mechanism, then pulled from the device and committed here) - not
/// hand-written test doubles. `DiagnosticReport` has no public initializer
/// (confirmed: Apple's MetricKit types only construct via `Decodable`), so
/// decoding a real capture is the only way to get one for a test at all.
///
/// This also caught a real bug (frame-extraction only ever read the
/// outermost frame of an arbitrary thread, not the attributed one, missing
/// 50+ real frames per fixture) that no synthetic test data would have
/// surfaced, since hand-written fixtures naturally only exercise the shapes
/// the author already thought of.
final class MetricKitBridgeFixtureTests: XCTestCase {
  private func loadFixture(_ name: String) throws -> DiagnosticReport {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      "fixture \(name).json not found in test bundle")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(DiagnosticReport.self, from: data)
  }

  private let allFixtureNames = [
    "diagnostic-20260912T110745.770",  // memoryException, no states
    "diagnostic-20260912T110757.564",  // crash, no states
    "diagnostic-20260912T131926.292",  // memoryException, no states
    "diagnostic-20260912T172415.580",  // crash, 2 states (multi-domain)
    "diagnostic-20260912T172435.024",  // memoryException, 3 states (incl. stableMetadata)
  ]

  func testAllFixturesDecodeWithoutError() throws {
    for name in allFixtureNames {
      XCTAssertNoThrow(try loadFixture(name), "failed to decode \(name)")
    }
  }

  func testAllFixturesSummarizeToExactlyOneSummary() throws {
    for name in allFixtureNames {
      let report = try loadFixture(name)
      let summaries = MetricKitBridge.summarize(report)
      XCTAssertEqual(
        summaries.count, 1, "\(name) should summarize to exactly one DiagnosticSummary")
    }
  }

  func testCrashFixtureExtractsRealSignalAndDeepFrames() throws {
    let report = try loadFixture("diagnostic-20260912T110757.564")
    let summary = try XCTUnwrap(MetricKitBridge.summarize(report).first)

    guard case .crash(let crash) = summary.kind else {
      return XCTFail("expected .crash")
    }
    // Real captured values - this crash is a real SIGABRT-family signal.
    XCTAssertEqual(crash.signal, 5)
    XCTAssertEqual(crash.threadCount, 6)
    // The real bug: the old code took `threads.first.rootFrames.prefix(5)`
    // with no descent into `subFrames`, so it only ever produced exactly 1
    // frame (the single root, before any subFrame walk) regardless of how
    // deep the real stack was. This thread's real stack is 53 frames deep.
    XCTAssertGreaterThan(
      crash.topFrames.count, 1,
      "frame extraction should walk subFrames, not just read the single root frame")
  }

  func testMultiDomainFixtureCapturesAllStatesWithDuration() throws {
    let report = try loadFixture("diagnostic-20260912T172415.580")
    let summary = try XCTUnwrap(MetricKitBridge.summarize(report).first)

    XCTAssertEqual(summary.states.count, 2)
    let domains = Set(summary.states.map(\.domain))
    XCTAssertTrue(domains.contains("com.hitchscope.example.screen"))
    XCTAssertTrue(domains.contains("com.hitchscope.example.experiment.checkout_redesign"))
    // Every real state entry carries a real, nonzero duration - this was
    // being dropped entirely before `durationMs` existed on `StateEntry`.
    for state in summary.states {
      let duration = try XCTUnwrap(state.durationMs)
      XCTAssertGreaterThan(duration, 0)
    }
  }

  func testStableMetadataFixtureRoundTripsUserTier() throws {
    let report = try loadFixture("diagnostic-20260912T172435.024")
    let summary = try XCTUnwrap(MetricKitBridge.summarize(report).first)

    let withMetadata = summary.states.first { $0.metadata != nil }
    let metadata = try XCTUnwrap(withMetadata?.metadata)
    guard case .string("premium") = metadata["userTier"] else {
      return XCTFail("expected userTier=premium stableMetadata to survive real capture + decode")
    }
  }

  func testEnvironmentContextReflectsRealDevice() throws {
    let report = try loadFixture("diagnostic-20260912T110757.564")
    let summary = try XCTUnwrap(MetricKitBridge.summarize(report).first)

    XCTAssertTrue(summary.isTestFlightApp)
    XCTAssertFalse(summary.lowPowerModeEnabled)
    XCTAssertEqual(summary.osBuildNumber, "24A435")
  }

  func testEveryFixtureMapsToAnIngestEventWithoutCrashing() throws {
    for name in allFixtureNames {
      let report = try loadFixture(name)
      for summary in MetricKitBridge.summarize(report) {
        _ = EventMapper.map(summary)  // exercising for crashes/traps only
      }
    }
  }
}
