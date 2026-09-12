import Foundation

/// The diagnostic event types hitchscope-backend's `/v1/ingest` accepts.
public enum EventKind: String, Codable, Sendable {
  case crash = "CRASH"
  case hang = "HANG"
  case launch = "LAUNCH"
  case memory = "MEMORY"
  case cpuException = "CPU_EXCEPTION"
  case diskWriteException = "DISK_WRITE_EXCEPTION"
}

/// One state-reporting domain/label pair active when an event occurred.
/// Mirrors `MetricManager.ReportedState`, but plain and Codable so it can
/// cross the network and be constructed in tests without touching MetricKit.
struct StateEntry: Codable, Sendable, Equatable {
  let domain: String
  let label: String
  /// From `ReportedState.stableMetadata` - nil for metric-aggregate states,
  /// which carry no metadata concept, and for diagnostics where the app
  /// never attached any via `reportState(..., stableMetadata:)`.
  let metadata: [String: JSONValue]?
  /// From `ReportedState.duration` - how long this state had been active
  /// when the report was generated. Confirmed via real captured device
  /// fixtures to carry real, meaningful values (e.g. 19.26s) that were
  /// previously dropped entirely.
  let durationMs: Double?

  init(
    domain: String, label: String, metadata: [String: JSONValue]? = nil,
    durationMs: Double? = nil
  ) {
    self.domain = domain
    self.label = label
    self.metadata = metadata
    self.durationMs = durationMs
  }
}

/// A minimal heterogeneous JSON value, for encoding a diagnostic's
/// type-specific `payload` dictionary without pulling in a full JSON library.
enum JSONValue: Codable, Sendable, Equatable {
  case string(String)
  case int(Int)
  case double(Double)
  case bool(Bool)
  case array([JSONValue])
  case object([String: JSONValue])
  case null

  func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    switch self {
    case .string(let value): try container.encode(value)
    case .int(let value): try container.encode(value)
    case .double(let value): try container.encode(value)
    case .bool(let value): try container.encode(value)
    case .array(let value): try container.encode(value)
    case .object(let value): try container.encode(value)
    case .null: try container.encodeNil()
    }
  }

  init(from decoder: Decoder) throws {
    let container = try decoder.singleValueContainer()
    if let value = try? container.decode(String.self) {
      self = .string(value)
    } else if let value = try? container.decode(Int.self) {
      self = .int(value)
    } else if let value = try? container.decode(Double.self) {
      self = .double(value)
    } else if let value = try? container.decode(Bool.self) {
      self = .bool(value)
    } else if let value = try? container.decode([JSONValue].self) {
      self = .array(value)
    } else if let value = try? container.decode([String: JSONValue].self) {
      self = .object(value)
    } else {
      self = .null
    }
  }
}

/// One event as sent over the wire to `POST /v1/ingest`.
struct IngestEvent: Codable, Sendable {
  let type: EventKind
  let states: [StateEntry]
  let occurredAt: Date
  let payload: [String: JSONValue]
}

struct IngestRequest: Codable, Sendable {
  let appVersion: String
  let osVersion: String
  let deviceModel: String
  let events: [IngestEvent]
}

struct IngestResponse: Codable, Sendable {
  let accepted: Int
}
