import SwiftUI
import HitchScope

@main
struct HitchScopeExampleApp: App {
    init() {
        HitchScope.configure(apiKey: "preview", trackedStates: ["com.hitchscope.example.screen"])
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
