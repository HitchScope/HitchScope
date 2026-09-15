import MetricKit
import XCTest

@testable import HitchScope

/// A dormant export utility, not a real test - `fixturesToExport` is empty
/// by default, so this is always a no-op (and never touches the network or
/// any database) in normal `xcodebuild test` runs, including CI. Exists so
/// real MetricKit captures already committed under
/// `Tests/HitchScopeTests/Fixtures/` can be replayed through the SDK's own
/// tested decode -> summarize -> map pipeline into the exact wire-format
/// JSON `IngestClient` would have sent, for backend tooling to separately
/// POST - rather than a parallel, untested reimplementation of that mapping
/// in another language. See hitchscope-backend's `scripts/ingest-fixture.ts`.
/// To use: list the fixture name(s) below, run this one test, then read the
/// exported JSON from the path XCTFail prints (the simulator's `Caches`
/// directory - persists past the test run, unlike NSTemporaryDirectory(),
/// and the simulator's whole filesystem lives on the host disk under
/// ~/Library/Developer/CoreSimulator/, so a plain `cat` from the host reads
/// it directly) - then blank the array again before committing.
@available(iOS 27, *)
final class FixtureReplayExportTests: XCTestCase {
  private let fixturesToExport: [String] = []

  func testExportFixturesForReplay() throws {
    // Caches, not NSTemporaryDirectory() - a simulator's /tmp is cleared as
    // part of the run's own teardown, before there's any chance to read it
    // back from the host; Caches is what the Example app's `FixtureCapture`
    // already uses for exactly this "pull a file off the simulator after
    // the run" purpose, and it persists.
    let cachesURL = try FileManager.default.url(
      for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true)
    for fixtureName in fixturesToExport {
      let outputURL = cachesURL.appendingPathComponent("\(fixtureName).ingest.json")
      try export(fixtureName, to: outputURL)
      XCTFail("exported \(fixtureName) -> \(outputURL.path)")
    }
  }

  private func export(_ fixtureName: String, to outputURL: URL) throws {
    let url = try XCTUnwrap(
      Bundle.module.url(forResource: fixtureName, withExtension: "json", subdirectory: "Fixtures"),
      "fixture \(fixtureName).json not found in test bundle")
    let data = try Data(contentsOf: url)

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601

    let payload: Data
    if fixtureName.hasPrefix("diagnostic-") {
      let report = try JSONDecoder().decode(DiagnosticReport.self, from: data)
      let events = MetricKitBridge.summarize(report).map(EventMapper.map)
      let request = IngestRequest(
        appVersion: report.environment.applicationVersion,
        osVersion: report.environment.osVersion.number,
        deviceModel: report.environment.deviceType,
        events: events
      )
      payload = try encoder.encode(request)
    } else if fixtureName.hasPrefix("metric-") {
      let report = try JSONDecoder().decode(MetricReport.self, from: data)
      let summaries =
        MetricKitBridge.summarizeMetrics(report)
        + MetricKitBridge
        .summarizeFullDayInterval(report)
      let metrics = summaries.map(MetricAggregateMapper.map)
      let request = MetricAggregateIngestRequest(
        appVersion: report.environment?.latestApplicationVersion ?? "unknown",
        osVersion: report.environment?.osVersion.number ?? "unknown",
        deviceModel: report.environment?.deviceType ?? "unknown",
        metrics: metrics
      )
      payload = try encoder.encode(request)
    } else {
      XCTFail("fixture \(fixtureName) doesn't start with \"diagnostic-\" or \"metric-\"")
      return
    }

    try payload.write(to: outputURL)
  }
}
