import HitchScope

private let fixtureDomain = "com.hitchscope.example.fixture"

/// A fixed business-state fixture, deliberately on its own domain rather
/// than the screen domain (`ScreenStateReporting`) or the demo domain
/// (`StateReportingScreen`) - "what business state is active" and "what
/// screen am I on" are different questions MetricKit tracks independently,
/// and conflating them onto one domain made it hard to tell which was which.
///
/// Called by every trigger screen that still wants "start from the exact
/// same state/metadata" regardless of what was tapped before it.
enum ReproducibleState {
    static func set() {
        HitchScope.reportState(
            fixtureDomain, label: "checkout", stableMetadata: ["userTier": .init("premium")])
        HitchScope.updateVolatileMetadata(fixtureDomain, ["cartItems": .init(3)])
    }
}
