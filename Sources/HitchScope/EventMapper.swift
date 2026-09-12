import Foundation

/// Pure mapping from a `DiagnosticSummary` to the wire-format `IngestEvent`.
/// Plain types only — no Apple framework types, no availability annotation,
/// fully unit-testable.
enum EventMapper {
  static func map(_ summary: DiagnosticSummary) -> IngestEvent {
    let (type, kindPayload) = payload(for: summary.kind)
    var payload = kindPayload
    // Report-level context, not specific to any one diagnostic kind - same
    // keys on every event, regardless of type.
    payload["lowPowerModeEnabled"] = .bool(summary.lowPowerModeEnabled)
    payload["isTestFlightApp"] = .bool(summary.isTestFlightApp)
    if let osBuildNumber = summary.osBuildNumber {
      payload["osBuildNumber"] = .string(osBuildNumber)
    }
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
      if let vmRegionInfo = crash.virtualMemoryRegionInfo {
        payload["virtualMemoryRegionInfo"] = .string(vmRegionInfo)
      }
      if let reason = crash.exceptionReason {
        payload["exceptionReason"] = .object([
          "composedMessage": .string(reason.composedMessage),
          "formatString": .string(reason.formatString),
          "arguments": .array(reason.arguments.map(JSONValue.string)),
          "exceptionType": .string(reason.exceptionType),
          "className": .string(reason.className),
          "exceptionName": .string(reason.exceptionName),
        ])
      }
      if !crash.topFrames.isEmpty {
        payload["topFrames"] = .array(crash.topFrames.map(frameJSON))
      }
      return (.crash, payload)

    case .hang(let hang):
      var payload: [String: JSONValue] = [
        "hangDurationMs": .double(hang.durationMs), "threadCount": .int(hang.threadCount),
      ]
      if !hang.topFrames.isEmpty { payload["topFrames"] = .array(hang.topFrames.map(frameJSON)) }
      return (.hang, payload)

    case .appLaunch(let launch):
      var payload: [String: JSONValue] = [
        "launchDurationMs": .double(launch.durationMs), "threadCount": .int(launch.threadCount),
      ]
      if !launch.topFrames.isEmpty {
        payload["topFrames"] = .array(launch.topFrames.map(frameJSON))
      }
      return (.launch, payload)

    case .memoryException(let exception):
      // Real MemoryExceptionDiagnostic has no severity/fatal/peak-memory
      // fields — don't invent isFatal/pressureLevel to match richer
      // synthetic data from earlier phases; this is what's actually there.
      var payload: [String: JSONValue] = ["threadCount": .int(exception.threadCount)]
      if !exception.topFrames.isEmpty {
        payload["topFrames"] = .array(exception.topFrames.map(frameJSON))
      }
      return (.memory, payload)

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
