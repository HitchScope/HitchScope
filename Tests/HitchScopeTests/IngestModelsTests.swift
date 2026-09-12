import XCTest

@testable import HitchScope

final class IngestModelsTests: XCTestCase {
  func testRequestEncodesWithExactBackendContractKeys() throws {
    let event = IngestEvent(
      type: .hang,
      states: [StateEntry(domain: "com.app.screen", label: "Checkout")],
      occurredAt: Date(timeIntervalSince1970: 1_700_000_000),
      payload: ["hangDurationMs": .double(1234.5), "threadCount": .int(3)]
    )
    let request = IngestRequest(
      appVersion: "1.0.0",
      osVersion: "27.0",
      deviceModel: "iPhone18,1",
      events: [event]
    )

    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    let data = try encoder.encode(request)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertEqual(json["appVersion"] as? String, "1.0.0")
    XCTAssertEqual(json["osVersion"] as? String, "27.0")
    XCTAssertEqual(json["deviceModel"] as? String, "iPhone18,1")

    let events = try XCTUnwrap(json["events"] as? [[String: Any]])
    XCTAssertEqual(events.count, 1)
    XCTAssertEqual(events[0]["type"] as? String, "HANG")
    XCTAssertNotNil(events[0]["occurredAt"] as? String)

    let states = try XCTUnwrap(events[0]["states"] as? [[String: Any]])
    XCTAssertEqual(states.count, 1)
    XCTAssertEqual(states[0]["domain"] as? String, "com.app.screen")
    XCTAssertEqual(states[0]["label"] as? String, "Checkout")

    let payload = try XCTUnwrap(events[0]["payload"] as? [String: Any])
    XCTAssertEqual(payload["hangDurationMs"] as? Double, 1234.5)
    XCTAssertEqual(payload["threadCount"] as? Int, 3)
  }

  func testEventKindRawValuesMatchBackendEnum() {
    XCTAssertEqual(EventKind.crash.rawValue, "CRASH")
    XCTAssertEqual(EventKind.hang.rawValue, "HANG")
    XCTAssertEqual(EventKind.launch.rawValue, "LAUNCH")
    XCTAssertEqual(EventKind.memory.rawValue, "MEMORY")
    XCTAssertEqual(EventKind.cpuException.rawValue, "CPU_EXCEPTION")
    XCTAssertEqual(EventKind.diskWriteException.rawValue, "DISK_WRITE_EXCEPTION")
  }

  func testResponseDecodesAcceptedCount() throws {
    let json = #"{"accepted": 12}"#.data(using: .utf8)!
    let response = try JSONDecoder().decode(IngestResponse.self, from: json)
    XCTAssertEqual(response.accepted, 12)
  }

  func testStateEntryOmitsMetadataKeyWhenNil() throws {
    let state = StateEntry(domain: "com.app.screen", label: "Checkout")
    let data = try JSONEncoder().encode(state)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertNil(json["metadata"])
  }

  func testStateEntryMetadataRoundTrips() throws {
    let state = StateEntry(
      domain: "com.app.experiment.checkout_redesign", label: "variant_b",
      metadata: ["userTier": .string("premium"), "cartTotal": .double(49.99)]
    )
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(StateEntry.self, from: data)

    XCTAssertEqual(decoded.domain, state.domain)
    XCTAssertEqual(decoded.label, state.label)
    guard case .string("premium") = decoded.metadata?["userTier"] else {
      return XCTFail("expected userTier metadata")
    }
    guard case .double(49.99) = decoded.metadata?["cartTotal"] else {
      return XCTFail("expected cartTotal metadata")
    }
  }

  func testStateEntryDurationMsRoundTrips() throws {
    let state = StateEntry(domain: "com.app.screen", label: "home", durationMs: 19_256.77)
    let data = try JSONEncoder().encode(state)
    let decoded = try JSONDecoder().decode(StateEntry.self, from: data)

    XCTAssertEqual(decoded.durationMs, 19_256.77)
  }

  func testStateEntryOmitsDurationMsKeyWhenNil() throws {
    let state = StateEntry(domain: "com.app.screen", label: "Checkout")
    let data = try JSONEncoder().encode(state)
    let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

    XCTAssertNil(json["durationMs"])
  }

  func testJSONValueRoundTripsHeterogeneousTypes() throws {
    let value: [String: JSONValue] = [
      "s": .string("x"),
      "i": .int(1),
      "d": .double(2.5),
      "b": .bool(true),
      "arr": .array([.int(1), .string("two")]),
      "obj": .object(["nested": .bool(false)]),
    ]
    let encoder = JSONEncoder()
    let data = try encoder.encode(value)
    let decoded = try JSONDecoder().decode([String: JSONValue].self, from: data)

    guard case .string("x") = decoded["s"] else { return XCTFail() }
    guard case .double(2.5) = decoded["d"] else { return XCTFail() }
    guard case .array(let arr) = decoded["arr"], arr.count == 2 else { return XCTFail() }
    guard case .object(let obj) = decoded["obj"] else { return XCTFail() }
    guard case .bool(false) = obj["nested"] else { return XCTFail() }
  }
}
