import SwiftUI
import HitchScope

private let screenDomain = "com.hitchscope.example.screen"

private struct ScreenStateReportingModifier: ViewModifier {
    let screenID: String

    func body(content: Content) -> some View {
        content
            .onAppear { HitchScope.reportState(screenDomain, label: screenID) }
            .onDisappear { HitchScope.reportState(screenDomain, label: nil) }
    }
}

extension View {
    /// Reports this screen's id as the active state on the shared screen
    /// domain for as long as this view is on-screen - mirrors how a real
    /// app would tag "what screen is the user on" via the State Reporting
    /// API. In a NavigationStack, pushing a screen fires its onAppear
    /// before the previous screen's onDisappear, so the last write (the
    /// new screen's id) is what's left active - exactly the value you want.
    func reportsScreenState(_ id: String) -> some View {
        modifier(ScreenStateReportingModifier(screenID: id))
    }
}
