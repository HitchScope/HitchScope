import SwiftUI
import HitchScope

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

        // Two domains, not one - demonstrates that domains are independent
        // (a screen and an experiment variant can both be active at once,
        // each with its own current label) rather than one privileged slot.
        HitchScope.configure(
            apiKey: Secrets.apiKey,
            trackedStates: [
                "com.hitchscope.example.screen",
                "com.hitchscope.example.experiment.checkout_redesign",
            ])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
