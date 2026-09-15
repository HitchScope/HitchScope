import SwiftUI
import HitchScope

/// Several independent domains, not one - each screen/experiment tracks its
/// own current label simultaneously, with none privileged: .screen
/// (auto-reported by every screen via reportsScreenState), .fixture (the
/// shared "checkout" business-state fixture triggers set before reproducing
/// a problem), .demo + .experiment.demo (the State Reporting API screen's
/// own manual demo domains), and one .experiment.<metricID> per metric
/// screen with an A/B toggle. Shared between HitchScope.configure and
/// FixtureCapture.start so captured fixtures carry the same environment
/// data real ingested events would.
private let trackedStateDomains: Set<String> = [
    "com.hitchscope.example.screen",
    "com.hitchscope.example.fixture",
    "com.hitchscope.example.demo",
    "com.hitchscope.example.experiment.demo",
    "com.hitchscope.example.experiment.hangs",
    "com.hitchscope.example.experiment.cpu",
    "com.hitchscope.example.experiment.diskWrites",
    "com.hitchscope.example.experiment.scrollHitches",
]

@main
struct HitchScopeExampleApp: App {
    init() {
        // Deliberately checked/cleared *before* HitchScope.configure -
        // appLaunch diagnostics measure the whole launch, so a deliberate
        // stall needs to happen as early as possible, and clearing the flag
        // immediately (not after the stall) means a crash mid-stall can't
        // wedge every future launch into stalling forever.
        if SlowLaunchFlag.consume() {
            Thread.sleep(forTimeInterval: 3)
        }

        // Real key from Secrets.swift (gitignored - this repo is public, see
        // Secrets.swift.example for the shape). Missing entirely is now a
        // compile error (Secrets doesn't exist), not a silent runtime
        // failure - a fresh checkout that hasn't copied the example file
        // yet won't build at all. The CI placeholder value still gets a
        // runtime check: CI only needs the project to compile, never
        // actually launches it, but fail loudly instead of silently posting
        // to nothing if that ever changes.
        precondition(
            Secrets.apiKey != "ci-placeholder-not-a-real-key",
            "Secrets.swift has the CI placeholder key, not a real one - see Secrets.swift.example.")

        HitchScope.configure(apiKey: Secrets.apiKey, trackedStates: trackedStateDomains)

        // Harvests real on-device reports as JSON fixtures for the SDK's own
        // test suite - entirely separate from what HitchScope.configure does,
        // see FixtureCapture's own doc comment for why this isn't part of
        // the SDK itself.
        FixtureCapture.start(domains: trackedStateDomains)
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
