import Foundation

enum DeviceMetadata {
  static var appVersion: String {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
  }

  /// `UIDevice.current.systemVersion` is `@MainActor`-isolated, which would
  /// force every caller (HitchScopeRuntime/MetricKitBridge, deliberately
  /// plain actors that never touch the main thread) onto MainActor just to
  /// read a version string. `ProcessInfo` gives the same information and
  /// was designed to be thread-safe - no isolation to work around at all.
  static var osVersion: String {
    let v = ProcessInfo.processInfo.operatingSystemVersion
    let patch = v.patchVersion != 0 ? ".\(v.patchVersion)" : ""
    return "\(v.majorVersion).\(v.minorVersion)\(patch)"
  }

  /// The raw hardware identifier (e.g. "iPhone18,1") — not `UIDevice.current.model`,
  /// which returns a generic string like "iPhone" regardless of the specific device.
  static var deviceModel: String {
    var systemInfo = utsname()
    uname(&systemInfo)
    let machineMirror = Mirror(reflecting: systemInfo.machine)
    let identifier = machineMirror.children.reduce(into: "") { result, element in
      guard let value = element.value as? Int8, value != 0 else { return }
      result += String(UnicodeScalar(UInt8(value)))
    }
    return identifier.isEmpty ? "unknown" : identifier
  }
}
