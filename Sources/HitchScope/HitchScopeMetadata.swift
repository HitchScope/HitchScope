import Foundation

/// SDK-owned metadata value, not a re-export of StateReporting's own
/// `ReportableMetadataValue` (which is iOS 27+ only, and so can't appear in
/// this SDK's public API surface if `reportState`/`updateVolatileMetadata`
/// are to stay callable unconditionally on earlier OS versions). Same shape
/// as Apple's type - converted 1:1 to the real thing only on iOS 27+, in
/// `MetricKitBridge`, which is the only file that needs to know it exists.
public enum HitchScopeMetadataValue: Sendable, Equatable, Hashable {
  case date(Date)
  case string(String)
  case integer(Int)
  case floatingPoint(Double)

  public init(_ value: String) { self = .string(value) }
  public init(_ value: Date) { self = .date(value) }
  public init(_ value: Bool) { self = .integer(value ? 1 : 0) }
  public init(_ value: Int) { self = .integer(value) }
  public init(_ value: Int8) { self = .integer(Int(value)) }
  public init(_ value: Int16) { self = .integer(Int(value)) }
  public init(_ value: Int32) { self = .integer(Int(value)) }
  public init(_ value: Int64) { self = .integer(Int(value)) }
  public init(_ value: UInt8) { self = .integer(Int(value)) }
  public init(_ value: UInt16) { self = .integer(Int(value)) }
  public init(_ value: UInt32) { self = .integer(Int(value)) }
  // UInt/UInt64 can exceed Int.max - clamp rather than trap, since these
  // are meant for small, fixed-set metadata values (a count, a flag), not
  // values anywhere near that boundary.
  public init(_ value: UInt) { self = .integer(Int(clamping: value)) }
  public init(_ value: UInt64) { self = .integer(Int(clamping: value)) }
  public init(_ value: Float) { self = .floatingPoint(Double(value)) }
  public init(_ value: Double) { self = .floatingPoint(value) }
}
