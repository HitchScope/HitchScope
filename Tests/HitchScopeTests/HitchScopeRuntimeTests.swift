import XCTest

@testable import HitchScope

final class HitchScopeRuntimeTests: XCTestCase {
  func testReportStateRejectsUndeclaredDomain() async {
    let runtime = HitchScopeRuntime()
    await runtime.setDeclaredDomainsForTesting(["com.app.screen"])

    await runtime.reportState(
      domain: "com.app.never-declared", label: "X", stableMetadata: [:], volatileMetadata: [:])

    let reason = await runtime.lastRejectionReason
    XCTAssertEqual(reason, "undeclaredDomain")
  }

  func testReportStateRejectsEmptyStringLabel() async {
    let runtime = HitchScopeRuntime()
    await runtime.setDeclaredDomainsForTesting(["com.app.screen"])

    await runtime.reportState(
      domain: "com.app.screen", label: "", stableMetadata: [:], volatileMetadata: [:])

    let reason = await runtime.lastRejectionReason
    XCTAssertEqual(reason, "emptyLabel")
  }

  func testReportStateAllowsNilLabelToClearState() async {
    let runtime = HitchScopeRuntime()
    await runtime.setDeclaredDomainsForTesting(["com.app.screen"])

    await runtime.reportState(
      domain: "com.app.screen", label: nil, stableMetadata: [:], volatileMetadata: [:])

    let reason = await runtime.lastRejectionReason
    XCTAssertNil(reason, "nil label clears state and should pass both guards")
  }

  func testReportStatePassesGuardsForDeclaredDomainAndNonEmptyLabel() async {
    let runtime = HitchScopeRuntime()
    await runtime.setDeclaredDomainsForTesting(["com.app.screen"])

    await runtime.reportState(
      domain: "com.app.screen", label: "Checkout", stableMetadata: [:], volatileMetadata: [:])

    let reason = await runtime.lastRejectionReason
    XCTAssertNil(reason)
  }

  func testUpdateVolatileMetadataRejectsUndeclaredDomain() async {
    let runtime = HitchScopeRuntime()
    await runtime.setDeclaredDomainsForTesting(["com.app.screen"])

    await runtime.updateVolatileMetadata(domain: "com.app.never-declared", metadata: [:])

    let reason = await runtime.lastRejectionReason
    XCTAssertEqual(reason, "undeclaredDomain")
  }
}
