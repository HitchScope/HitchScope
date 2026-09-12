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
      return (.crash, payload)

    case .hang(let hang):
      let payload: [String: JSONValue] = [
        "hangDurationMs": .double(hang.durationMs), "threadCount": .int(hang.threadCount),
      ]
      return (.hang, payload)

    case .appLaunch(let launch):
      let payload: [String: JSONValue] = [
        "launchDurationMs": .double(launch.durationMs), "threadCount": .int(launch.threadCount),
      ]
      return (.launch, payload)

    case .memoryException(let exception):
      // Real MemoryExceptionDiagnostic has no severity/fatal/peak-memory
      // fields — don't invent isFatal/pressureLevel to match richer
      // synthetic data from earlier phases; this is what's actually there.
      let payload: [String: JSONValue] = ["threadCount": .int(exception.threadCount)]
      return (.memory, payload)

    case .cpuException(let exception):
      let payload: [String: JSONValue] = [
        "totalCPUTimeMs": .double(exception.totalCPUTimeMs),
        "totalSampledTimeMs": .double(exception.totalSampledTimeMs),
        "threadCount": .int(exception.threadCount),
      ]
      return (.cpuException, payload)

    case .diskWriteException(let exception):
      let payload: [String: JSONValue] = [
        "totalBytesWritten": .double(exception.totalBytesWritten),
        "threadCount": .int(exception.threadCount),
      ]
      return (.diskWriteException, payload)
    }
  }
}
