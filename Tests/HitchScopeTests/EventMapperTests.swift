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
          threadCount: 4
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
          threadCount: 1
        ))
    )

    let event = EventMapper.map(summary)

    XCTAssertNil(event.payload["terminationReason"])
    guard case .int(1) = event.payload["threadCount"] else {
      return XCTFail("expected threadCount even with no other fields")
    }
  }

  func testHangMapsDurationAndThreadCount() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate,
      kind: .hang(HangSummary(durationMs: 1500.5, threadCount: 6)))
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
      states: [], occurredAt: fixedDate,
      kind: .appLaunch(AppLaunchSummary(durationMs: 900, threadCount: 3)))
    let event = EventMapper.map(summary)

    XCTAssertEqual(event.type, .launch)
    guard case .double(900) = event.payload["launchDurationMs"] else {
      return XCTFail("expected launchDurationMs")
    }
  }

  func testCPUExceptionMapsTimesAndThreadCount() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate,
      kind: .cpuException(
        CPUExceptionSummary(totalCPUTimeMs: 5000, totalSampledTimeMs: 6000, threadCount: 8)))
    let event = EventMapper.map(summary)

    XCTAssertEqual(event.type, .cpuException)
    guard case .double(5000) = event.payload["totalCPUTimeMs"] else {
      return XCTFail("expected totalCPUTimeMs")
    }
    guard case .double(6000) = event.payload["totalSampledTimeMs"] else {
      return XCTFail("expected totalSampledTimeMs")
    }
    guard case .int(8) = event.payload["threadCount"] else {
      return XCTFail("expected threadCount")
    }
  }

  func testDiskWriteExceptionMapsBytesWrittenAndThreadCount() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate,
      kind: .diskWriteException(
        DiskWriteExceptionSummary(totalBytesWritten: 123_456, threadCount: 4)))
    let event = EventMapper.map(summary)

    XCTAssertEqual(event.type, .diskWriteException)
    guard case .double(123_456) = event.payload["totalBytesWritten"] else {
      return XCTFail("expected totalBytesWritten")
    }
    guard case .int(4) = event.payload["threadCount"] else {
      return XCTFail("expected threadCount")
    }
  }

  func testReportContextKeysReflectSummaryFlags() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate,
      kind: .memoryException(MemoryExceptionSummary(threadCount: 1)),
      lowPowerModeEnabled: true, isTestFlightApp: true, osBuildNumber: "24A435")
    let event = EventMapper.map(summary)

    guard case .bool(true) = event.payload["lowPowerModeEnabled"] else {
      return XCTFail("expected lowPowerModeEnabled to reflect the summary")
    }
    guard case .bool(true) = event.payload["isTestFlightApp"] else {
      return XCTFail("expected isTestFlightApp to reflect the summary")
    }
    guard case .string("24A435") = event.payload["osBuildNumber"] else {
      return XCTFail("expected osBuildNumber to reflect the summary")
    }
  }

  func testMemoryExceptionOnlyHasThreadCount() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate,
      kind: .memoryException(MemoryExceptionSummary(threadCount: 5)))
    let event = EventMapper.map(summary)

    XCTAssertEqual(event.type, .memory)
    // threadCount plus the two report-context keys every event carries,
    // regardless of kind - not additional memory-specific fields. No
    // osBuildNumber key since the summary didn't provide one.
    XCTAssertEqual(event.payload.count, 3)
    guard case .int(5) = event.payload["threadCount"] else {
      return XCTFail("expected threadCount")
    }
    guard case .bool(false) = event.payload["lowPowerModeEnabled"] else {
      return XCTFail("expected lowPowerModeEnabled context key")
    }
    guard case .bool(false) = event.payload["isTestFlightApp"] else {
      return XCTFail("expected isTestFlightApp context key")
    }
  }

  func testNoStatesProducesEmptyStatesArray() {
    let summary = DiagnosticSummary(
      states: [], occurredAt: fixedDate,
      kind: .memoryException(MemoryExceptionSummary(threadCount: 1)))
    let event = EventMapper.map(summary)

    XCTAssertTrue(event.states.isEmpty)
  }
}
