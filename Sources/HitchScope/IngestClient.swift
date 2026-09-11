import Foundation

/// POSTs batches of events to hitchscope-backend's `/v1/ingest`. In-memory
/// only — no persistence, no backoff, one immediate retry on a transient
/// failure. Buffered-but-unsent events are lost if the app terminates before
/// the next flush; an accepted v1 limit, not an oversight.
struct IngestClient: Sendable {
  private let baseURL: URL
  private let apiKey: String
  private let session: URLSession
  private let encoder: JSONEncoder

  init(baseURL: URL, apiKey: String, session: URLSession = .shared) {
    self.baseURL = baseURL
    self.apiKey = apiKey
    self.session = session
    let encoder = JSONEncoder()
    encoder.dateEncodingStrategy = .iso8601
    self.encoder = encoder
  }

  enum IngestError: Error {
    case invalidAPIKey
    case serverError(status: Int)
    case transportError(Error)
  }

  /// Sends one request per chunk of up to 500 events (the backend's max
  /// batch size). Returns once every chunk has either succeeded or
  /// exhausted its retry.
  func send(appVersion: String, osVersion: String, deviceModel: String, events: [IngestEvent]) async
    -> Result<Int, IngestError>
  {
    var totalAccepted = 0
    for chunk in events.chunked(into: 500) {
      let request = IngestRequest(
        appVersion: appVersion,
        osVersion: osVersion,
        deviceModel: deviceModel,
        events: chunk
      )
      switch await sendOnce(request) {
      case .success(let accepted):
        totalAccepted += accepted
      case .failure(let error):
        return .failure(error)
      }
    }
    return .success(totalAccepted)
  }

  private func sendOnce(_ request: IngestRequest) async -> Result<Int, IngestError> {
    let result = await attempt(request)
    switch result {
    case .success:
      return result
    case .failure(.invalidAPIKey):
      // Not retryable — the key is wrong, retrying won't help.
      return result
    case .failure(.transportError), .failure(.serverError):
      return await attempt(request)
    }
  }

  private func attempt(_ request: IngestRequest) async -> Result<Int, IngestError> {
    var urlRequest = URLRequest(url: baseURL.appendingPathComponent("v1/ingest"))
    urlRequest.httpMethod = "POST"
    urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
    urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")

    do {
      urlRequest.httpBody = try encoder.encode(request)
    } catch {
      return .failure(.transportError(error))
    }

    do {
      let (data, response) = try await session.data(for: urlRequest)
      guard let httpResponse = response as? HTTPURLResponse else {
        return .failure(.transportError(URLError(.badServerResponse)))
      }
      switch httpResponse.statusCode {
      case 201:
        let decoded = try JSONDecoder().decode(IngestResponse.self, from: data)
        return .success(decoded.accepted)
      case 401:
        return .failure(.invalidAPIKey)
      default:
        return .failure(.serverError(status: httpResponse.statusCode))
      }
    } catch {
      return .failure(.transportError(error))
    }
  }
}

extension Array {
  fileprivate func chunked(into size: Int) -> [[Element]] {
    guard size > 0, !isEmpty else { return isEmpty ? [] : [self] }
    return stride(from: 0, to: count, by: size).map {
      Array(self[$0..<Swift.min($0 + size, count)])
    }
  }
}
