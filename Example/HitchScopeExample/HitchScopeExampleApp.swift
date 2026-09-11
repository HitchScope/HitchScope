import SwiftUI
import HitchScope

@main
struct HitchScopeExampleApp: App {
    init() {
        // Matches the seeded dev app in hitchscope-backend's prisma/seed.ts —
        // "preview" isn't a real app and gets a 401 from every ingest call.
        HitchScope.configure(
            apiKey: "dev_local_hitchscope_key", trackedStates: ["com.hitchscope.example.screen"])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
