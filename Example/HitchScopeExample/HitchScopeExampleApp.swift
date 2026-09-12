import SwiftUI
import HitchScope

@main
struct HitchScopeExampleApp: App {
    init() {
        // Matches the seeded dev app in hitchscope-backend's prisma/seed.ts —
        // "preview" isn't a real app and gets a 401 from every ingest call.
        // Two domains, not one - demonstrates that domains are independent
        // (a screen and an experiment variant can both be active at once,
        // each with its own current label) rather than one privileged slot.
        HitchScope.configure(
            apiKey: "dev_local_hitchscope_key",
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
