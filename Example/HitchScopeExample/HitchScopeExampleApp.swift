import SwiftUI
import HitchScope

@main
struct HitchScopeExampleApp: App {
    init() {
        HitchScope.configure(apiKey: "preview")
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
        }
    }
}
