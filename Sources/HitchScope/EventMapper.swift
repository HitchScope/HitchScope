import Foundation

/// Pure mapping from a `DiagnosticSummary` to the wire-format `IngestEvent`.
/// Plain types only — no Apple framework types, no availability annotation,
/// fully unit-testable.
enum EventMapper {
  static func map(_ summary: DiagnosticSummary) -> IngestEvent {
    let (type, kindPayload) = payload(for: summary.kind)
    var payload = kindPayload
    // Report-level context, not specific to any one diagnostic kind - same
    // two keys on every event, regardless of type.
    payload["lowPowerModeEnabled"] = .bool(summary.lowPowerModeEnabled)
    payload["isTestFlightApp"] = .bool(summary.isTestFlightApp)
    return IngestEvent(
      type: type,
      states: summary.states,
      occurredAt: summary.occurredAt,
      payload: payload
    )
  }

  private static func payload(for kind: DiagnosticKind) -> (EventKind, [String: JSONValue]) {
    switch kind {
    case .crash(let crash):
      var payload: [String: JSONValue] = ["threadCount": .int(crash.threadCount)]
      if let reason = crash.terminationReason { payload["terminationReason"] = .string(reason) }
      if let category = crash.terminationCategory {
        payload["terminationCategory"] = .string(category)
      }
      if let exceptionType = crash.exceptionType { payload["exceptionType"] = .int(exceptionType) }
      if let exceptionCode = crash.exceptionCode {
        payload["exceptionCode"] = .double(Double(exceptionCode))
      }
      if let signal = crash.signal { payload["signal"] = .int(signal) }
      if !crash.topFrames.isEmpty {
        payload["topFrames"] = .array(crash.topFrames.map(frameJSON))
      }
      return (.crash, payload)

    case .hang(let durationMs, let threadCount):
      return (.hang, ["hangDurationMs": .double(durationMs), "threadCount": .int(threadCount)])

    case .appLaunch(let durationMs, let threadCount):
      return (.launch, ["launchDurationMs": .double(durationMs), "threadCount": .int(threadCount)])

    case .memoryException(let threadCount):
      // Real MemoryExceptionDiagnostic has no severity/fatal/peak-memory
      // fields — don't invent isFatal/pressureLevel to match richer
      // synthetic data from earlier phases; this is what's actually there.
      return (.memory, ["threadCount": .int(threadCount)])

    case .cpuException(let exception):
      var payload: [String: JSONValue] = [
        "totalCPUTimeMs": .double(exception.totalCPUTimeMs),
        "totalSampledTimeMs": .double(exception.totalSampledTimeMs),
        "threadCount": .int(exception.threadCount),
      ]
      if !exception.topFrames.isEmpty {
        payload["topFrames"] = .array(exception.topFrames.map(frameJSON))
      }
      return (.cpuException, payload)

    case .diskWriteException(let exception):
      var payload: [String: JSONValue] = [
        "totalBytesWritten": .double(exception.totalBytesWritten),
        "threadCount": .int(exception.threadCount),
      ]
      if !exception.topFrames.isEmpty {
        payload["topFrames"] = .array(exception.topFrames.map(frameJSON))
      }
      return (.diskWriteException, payload)
    }
  }

  private static func frameJSON(_ frame: FrameSummary) -> JSONValue {
    var object: [String: JSONValue] = [:]
    if let binaryUUID = frame.binaryUUID { object["binaryUUID"] = .string(binaryUUID) }
    if let offset = frame.offset { object["offset"] = .double(Double(offset)) }
    if let sampleCount = frame.sampleCount { object["sampleCount"] = .int(sampleCount) }
    return .object(object)
  }
}
