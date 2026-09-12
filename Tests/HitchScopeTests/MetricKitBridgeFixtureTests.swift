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
/// This also caught a real bug: frame extraction only ever read the single
/// outermost frame of `threads.first`, not the attributed thread, and never
/// descended into `subFrames`. The 4 real memoryException fixtures make
/// this concrete: the OS-attributed thread is index 2, 4, 2, and 1
/// respectively - never index 0 - so the old code would have picked the
/// wrong thread's stack entirely, not just truncated the right one. Index 1
/// in particular is the boundary case an off-by-one fix could still miss.
final class MetricKitBridgeFixtureTests: XCTestCase {
  private func loadFixture(_ name: String) throws -> DiagnosticReport {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: name, withExtension: "json", subdirectory: "Fixtures"),
      "fixture \(name).json not found in test bundle")
    let data = try Data(contentsOf: url)
    return try JSONDecoder().decode(DiagnosticReport.self, from: data)
  }

  /// Every leaf value here was independently extracted from the raw fixture
  /// JSON (walking `subFrames` in Python, picking the OS-attributed thread),
  /// not derived from `MetricKitBridge`'s own logic - this is what makes it
  /// an actual check of correctness rather than a change-detector that
  /// would pass just as well if the fix were subtly wrong.
  private struct ExpectedLeafFrame {
    let kind: String
    let attributedThreadIndex: Int
    let leafBinaryUUID: String
    let leafOffset: UInt64
    let numStates: Int
  }

  private let expectations: [String: ExpectedLeafFrame] = [
    "diagnostic-20260912T110745.770": ExpectedLeafFrame(
      kind: "memoryException", attributedThreadIndex: 2,
      leafBinaryUUID: "694C772A-A9F8-3AC0-9417-7C304043A771", leafOffset: 2320, numStates: 0),
    "diagnostic-20260912T110757.564": ExpectedLeafFrame(
      kind: "crash", attributedThreadIndex: 0,
      leafBinaryUUID: "D3F59B02-EE07-371B-B091-3F150A078ED8", leafOffset: 21944, numStates: 0),
    "diagnostic-20260912T131926.292": ExpectedLeafFrame(
      kind: "memoryException", attributedThreadIndex: 4,
      leafBinaryUUID: "694C772A-A9F8-3AC0-9417-7C304043A771", leafOffset: 2320, numStates: 0),
    "diagnostic-20260912T172415.580": ExpectedLeafFrame(
      kind: "crash", attributedThreadIndex: 0,
      leafBinaryUUID: "D3F59B02-EE07-371B-B091-3F150A078ED8", leafOffset: 21944, numStates: 2),
    "diagnostic-20260912T172435.024": ExpectedLeafFrame(
      kind: "memoryException", attributedThreadIndex: 2,
      leafBinaryUUID: "694C772A-A9F8-3AC0-9417-7C304043A771", leafOffset: 2320, numStates: 3),
    "diagnostic-20260912T181913.431": ExpectedLeafFrame(
      kind: "memoryException", attributedThreadIndex: 1,
      leafBinaryUUID: "694C772A-A9F8-3AC0-9417-7C304043A771", leafOffset: 2320, numStates: 4),
  ]

  private func topFrames(for summary: DiagnosticSummary) -> [FrameSummary]? {
    switch summary.kind {
    case .crash(let crash): return crash.topFrames
    case .memoryException(let exception): return exception.topFrames
    case .hang(let hang): return hang.topFrames
    case .appLaunch(let launch): return launch.topFrames
    case .cpuException(let exception): return exception.topFrames
    case .diskWriteException(let exception): return exception.topFrames
    }
  }

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

  func testEveryFixtureParsesIntoTheExpectedKindWithTheRealLeafFrameFirst() throws {
    for (name, expected) in expectations {
      let report = try loadFixture(name)
      let summaries = MetricKitBridge.summarize(report)
      XCTAssertEqual(summaries.count, 1, "\(name): expected exactly one DiagnosticSummary")
      guard let summary = summaries.first else { continue }

      XCTAssertEqual(kindName(for: summary), expected.kind, "\(name): wrong DiagnosticKind")
      XCTAssertEqual(summary.states.count, expected.numStates, "\(name): wrong state count")

      let frames = try XCTUnwrap(topFrames(for: summary), "\(name): no topFrames case matched")
      let firstFrame = try XCTUnwrap(frames.first, "\(name): topFrames is empty")
      XCTAssertEqual(
        firstFrame.binaryUUID, expected.leafBinaryUUID,
        "\(name): topFrames[0] should be the real leaf frame from the attributed thread (index \(expected.attributedThreadIndex)), not the wrong thread or an outer frame"
      )
      XCTAssertEqual(
        firstFrame.offset, expected.leafOffset, "\(name): topFrames[0].offset mismatch")
      XCTAssertGreaterThan(
        frames.count, 1,
        "\(name): should have walked subFrames for real depth, not just the single root frame")
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
