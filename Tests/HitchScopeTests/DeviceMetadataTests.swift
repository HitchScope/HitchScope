import XCTest

@testable import HitchScope

final class DeviceMetadataTests: XCTestCase {
  // Can't assert exact values in a simulator run — just confirm these don't
  // crash and return something non-empty (or the documented "unknown" fallback).
  func testAppVersionIsNonEmpty() {
    XCTAssertFalse(DeviceMetadata.appVersion.isEmpty)
  }

  func testOSVersionIsNonEmpty() {
    XCTAssertFalse(DeviceMetadata.osVersion.isEmpty)
  }

  func testDeviceModelIsNonEmpty() {
    XCTAssertFalse(DeviceMetadata.deviceModel.isEmpty)
  }
}
