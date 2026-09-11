import Foundation
import UIKit

enum DeviceMetadata {
  static var appVersion: String {
    (Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String) ?? "unknown"
  }

  static var osVersion: String {
    UIDevice.current.systemVersion
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
