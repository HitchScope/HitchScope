import XCTest

@testable import HitchScope

final class EventMapperTests: XCTestCase {
  private let fixedDate = Date(timeIntervalSince1970: 1_700_000_000)

  func testCrashMapsAllFieldsAndMultipleStates() {
    let summary = DiagnosticSummary(
      states: [
        StateEntry(domain: "com.app.screen", label: "Checkout"),
        StateEntry(domain: "com.app.experiment.redesign", label: "variant_b"),
      ],
      occurredAt: fixedDate,
      kind: .crash(
        CrashSummary(
          terminationReason: "SIGNAL",
          terminationCategory: "badAccess",
          exceptionType: 1,
          exceptionCode: 2,
          signal: 11,
          threadCount: 4,
          topFrames: [FrameSummary(binaryUUID: "ABC-123", offset: 0x100, sampleCount: 3)]
        ))
    )

    let event = EventMapper.map(summary)

    XCTAssertEqual(event.type, .crash)
    XCTAssertEqual(event.occurredAt, fixedDate)
    XCTAssertEqual(event.states.count, 2)
    XCTAssertEqual(event.states[0].domain, "com.app.screen")
    XCTAssertEqual(event.states[0].label, "Checkout")
    XCTAssertEqual(event.states[1].domain, "com.app.experiment.redesign")
    XCTAssertEqual(event.states[1].label, "variant_b")

    guard case .string("SIGNAL") = event.payload["terminationReason"] else {
      return XCTFail("expected terminationReason")
    }
    guard case .int(4) = event.payload["threadCount"] else {
      return XCTFail("expected threadCount")
    }
    guard case .array(let frames) = event.payload["topFrames"], frames.count == 1 else {
      return XCTFail("expected one topFrame")
    }
  }

  func testCrashOmitsNilOptionalFields() {
    let summary = DiagnosticSummary(
      states: [],
      occurredAt: fixedDate,
      kind: .crash(
        CrashSummary(
          terminationReason: nil,
          terminationCategory: nil,
          exceptionType: nil,
          exceptionCode: nil,
          signal: nil,
          threadCount: 1,
          topFrames: []
        ))
    )

    let event = EventMapper.map(summary)

    XCTAssertNil(event.payload["terminationReason"])
    XCTAssertNil(event.payload["topFrames"])
    guard case .int(1) = event.payload["threadCount"] else {
      return XCTFail("expected threadCount even with no other fields")
    }
  }

  func testHangMapsDurationAndThreadCount() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate, kind: .hang(durationMs: 1500.5, threadCount: 6))
    let event = EventMapper.map(summary)

    XCTAssertEqual(event.type, .hang)
    guard case .double(1500.5) = event.payload["hangDurationMs"] else {
      return XCTFail("expected hangDurationMs")
    }
    guard case .int(6) = event.payload["threadCount"] else {
      return XCTFail("expected threadCount")
    }
  }

  func testAppLaunchMapsDurationAndThreadCount() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate, kind: .appLaunch(durationMs: 900, threadCount: 3))
    let event = EventMapper.map(summary)

    XCTAssertEqual(event.type, .launch)
    guard case .double(900) = event.payload["launchDurationMs"] else {
      return XCTFail("expected launchDurationMs")
    }
  }

  func testMemoryExceptionOnlyHasThreadCount() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate, kind: .memoryException(threadCount: 5))
    let event = EventMapper.map(summary)

    XCTAssertEqual(event.type, .memory)
    XCTAssertEqual(event.payload.count, 1)
    guard case .int(5) = event.payload["threadCount"] else {
      return XCTFail("expected threadCount")
    }
  }

  func testNoStatesProducesEmptyStatesArray() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate, kind: .memoryException(threadCount: 1))
    let event = EventMapper.map(summary)

    XCTAssertTrue(event.states.isEmpty)
  }
}
