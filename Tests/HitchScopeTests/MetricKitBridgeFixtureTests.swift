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
/// Coverage is currently 2 of the 6 `DiagnosticKind` cases - crash and
/// memoryException. No real fixtures exist yet for hang, appLaunch,
/// cpuException, or diskWriteException (the Example app has no trigger for
/// the latter two at all yet - see the future-roadmap note on Example app
/// trigger coverage). Don't read "all fixture tests pass" as "every
/// diagnostic kind is validated against real data" - it isn't, yet.
///
/// No call-stack frame extraction here (or in `MetricKitBridge` at all) - a
/// MetricKit frame is just a binary UUID + offset, meaningless without a
/// dSYM to symbolicate it, and Xcode Organizer already gives that for free
/// on any TestFlight/App Store build. See the future-roadmap doc.
final class MetricKitBridgeFixtureTests: XCTestCase {
  private func loadFixture(_ name: String) throws -> DiagnosticReport {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      "fixture \(name).json not found in test bundle")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(DiagnosticReport.self, from: data)
  }

  private struct ExpectedKind {
    let kind: String
    let numStates: Int
  }

  private let expectations: [String: ExpectedKind] = [
    "diagnostic-20260912T110745.770": ExpectedKind(kind: "memoryException", numStates: 0),
    "diagnostic-20260912T110757.564": ExpectedKind(kind: "crash", numStates: 0),
    "diagnostic-20260912T131926.292": ExpectedKind(kind: "memoryException", numStates: 0),
    "diagnostic-20260912T172415.580": ExpectedKind(kind: "crash", numStates: 2),
    "diagnostic-20260912T172435.024": ExpectedKind(kind: "memoryException", numStates: 3),
    "diagnostic-20260912T181913.431": ExpectedKind(kind: "memoryException", numStates: 4),
  ]

  private func kindName(for summary: DiagnosticSummary) -> String {
    switch summary.kind {
    case .crash: return "crash"
    case .memoryException: return "memoryException"
    case .hang: return "hang"
    case .appLaunch: return "appLaunch"
    case .cpuException: return "cpuException"
    case .diskWriteException: return "diskWriteException"
    }
  }

  func testEveryFixtureParsesIntoTheExpectedKind() throws {
    for (name, expected) in expectations {
      let report = try loadFixture(name)
      let summaries = MetricKitBridge.summarize(report)
      XCTAssertEqual(summaries.count, 1, "\(name): expected exactly one DiagnosticSummary")
      guard let summary = summaries.first else { continue }

      XCTAssertEqual(kindName(for: summary), expected.kind, "\(name): wrong DiagnosticKind")
      XCTAssertEqual(summary.states.count, expected.numStates, "\(name): wrong state count")
    }
  }

  func testEveryFixtureMapsToAnIngestEventWithoutCrashing() throws {
    for name in expectations.keys {
      let report = try loadFixture(name)
      for summary in MetricKitBridge.summarize(report) {
        _ = EventMapper.map(summary)
      }
    }
  }

  func testMultiDomainFixtureCapturesAllStatesWithDuration() throws {
    let report = try loadFixture("diagnostic-20260912T172415.580")
    let summary = try XCTUnwrap(MetricKitBridge.summarize(report).first)

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
}
