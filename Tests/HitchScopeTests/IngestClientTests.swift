import XCTest

@testable import HitchScope

/// Stubs network responses so IngestClient can be tested without a real
/// network call. Each test installs a handler on `StubURLProtocol.handler`.
final class StubURLProtocol: URLProtocol {
  // Test-only stub state, deliberately not actor-isolated — each test sets
  // a fresh handler in setUp/the test body and runs serially, so there's
  // no real concurrent access despite Swift 6 not being able to prove that.
  nonisolated(unsafe) static var handler: ((URLRequest) -> (Int, Data))?
  nonisolated(unsafe) static var capturedRequests: [URLRequest] = []

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    StubURLProtocol.capturedRequests.append(request)
    guard let handler = StubURLProtocol.handler else {
      client?.urlProtocol(self, didFailWithError: URLError(.badServerResponse))
      return
    }
    let (status, body) = handler(request)
    let response = HTTPURLResponse(
      url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    client?.urlProtocol(self, didLoad: body)
    client?.urlProtocolDidFinishLoading(self)
  }

  override func stopLoading() {}
}

final class IngestClientTests: XCTestCase {
  private func stubbedSession() -> URLSession {
    let config = URLSessionConfiguration.ephemeral
    config.protocolClasses = [StubURLProtocol.self]
    return URLSession(configuration: config)
  }

  private func sampleEvent() -> IngestEvent {
    IngestEvent(type: .crash, states: [], occurredAt: Date(), payload: ["threadCount": .int(1)])
  }

  override func setUp() {
    super.setUp()
    StubURLProtocol.capturedRequests = []
    StubURLProtocol.handler = nil
  }

  func testSuccessfulSendReturnsAcceptedCount() async {
    StubURLProtocol.handler = { _ in (201, #"{"accepted": 1}"#.data(using: .utf8)!) }
    let client = IngestClient(
      baseURL: URL(string: "https://example.com")!, apiKey: "key", session: stubbedSession())

    let outcome = await client.send(
      appVersion: "1.0", osVersion: "27.0", deviceModel: "iPhone", events: [sampleEvent()])

    XCTAssertNil(outcome.error)
    XCTAssertEqual(outcome.accepted, 1)
    XCTAssertEqual(outcome.sentCount, 1)
    XCTAssertEqual(
      StubURLProtocol.capturedRequests.first?.value(forHTTPHeaderField: "x-api-key"), "key")
  }

  func test401DoesNotRetry() async {
    var callCount = 0
    StubURLProtocol.handler = { _ in
      callCount += 1
      return (401, Data())
    }
    let client = IngestClient(
      baseURL: URL(string: "https://example.com")!, apiKey: "bad-key", session: stubbedSession())

    let outcome = await client.send(
      appVersion: "1.0", osVersion: "27.0", deviceModel: "iPhone", events: [sampleEvent()])

    guard case .invalidAPIKey = outcome.error else {
      return XCTFail("expected invalidAPIKey failure")
    }
    XCTAssertEqual(outcome.sentCount, 0)
    XCTAssertEqual(callCount, 1, "401 should not be retried")
  }

  func testServerErrorRetriesOnceThenFails() async {
    var callCount = 0
    StubURLProtocol.handler = { _ in
      callCount += 1
      return (500, Data())
    }
    let client = IngestClient(
      baseURL: URL(string: "https://example.com")!, apiKey: "key", session: stubbedSession())

    let outcome = await client.send(
      appVersion: "1.0", osVersion: "27.0", deviceModel: "iPhone", events: [sampleEvent()])

    guard case .serverError(500) = outcome.error else {
      return XCTFail("expected serverError failure")
    }
    XCTAssertEqual(outcome.sentCount, 0)
    XCTAssertEqual(callCount, 2, "transient failure should be retried exactly once")
  }

  func testServerErrorSucceedsOnRetry() async {
    var callCount = 0
    StubURLProtocol.handler = { _ in
      callCount += 1
      return callCount == 1 ? (500, Data()) : (201, #"{"accepted": 1}"#.data(using: .utf8)!)
    }
    let client = IngestClient(
      baseURL: URL(string: "https://example.com")!, apiKey: "key", session: stubbedSession())

    let outcome = await client.send(
      appVersion: "1.0", osVersion: "27.0", deviceModel: "iPhone", events: [sampleEvent()])

    XCTAssertNil(outcome.error, "expected success on retry")
    XCTAssertEqual(outcome.accepted, 1)
    XCTAssertEqual(outcome.sentCount, 1)
    XCTAssertEqual(callCount, 2)
  }

  /// Regression test for a duplicate-ingestion risk: if a batch spans more
  /// than one 500-event chunk and an earlier chunk succeeds before a later
  /// one fails, `sentCount` must reflect only the chunk(s) that actually
  /// reached the server - not 0 (which would make the caller resend an
  /// already-ingested chunk on retry) and not the full input count (which
  /// would make the caller drop events that were never sent).
  func testPartialChunkFailureReportsOnlySentPrefix() async {
    var callCount = 0
    StubURLProtocol.handler = { request in
      callCount += 1
      // First chunk (request 1, retried once on failure would be requests
      // 1-2) succeeds; the second chunk (request 3) fails and exhausts its
      // own retry (request 4).
      return callCount <= 1 ? (201, #"{"accepted": 500}"#.data(using: .utf8)!) : (500, Data())
    }
    let client = IngestClient(
      baseURL: URL(string: "https://example.com")!, apiKey: "key", session: stubbedSession())
    let events = (0..<600).map { _ in sampleEvent() }

    let outcome = await client.send(
      appVersion: "1.0", osVersion: "27.0", deviceModel: "iPhone", events: events)

    guard case .serverError(500) = outcome.error else {
      return XCTFail("expected the second chunk's serverError to propagate")
    }
    XCTAssertEqual(
      outcome.sentCount, 500, "only the first (successful) chunk should count as sent")
  }
}
