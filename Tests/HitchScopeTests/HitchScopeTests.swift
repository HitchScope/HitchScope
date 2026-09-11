import XCTest

@testable import HitchScope

final class HitchScopeTests: XCTestCase {
  func testConfigureDoesNotCrash() {
    HitchScope.configure(apiKey: "test-key", trackedStates: ["com.hitchscope.tests.screen"])
  }
}
