import SwiftUI
import HitchScope

/// One reusable on/off toggle per metric: persists via UserDefaults, reports
/// its current value on that metric's own experiment domain, and exposes a
/// plain Bool any workload can branch on synchronously.
///
/// `isOn == true` ("Fixed") is the background-safe code path; `isOn ==
/// false` (the default) reproduces the original performance problem, so a
/// fresh install still demonstrates the repro out of the box.
struct PerformanceToggle {
    let metricID: String

    private var domain: String { "com.hitchscope.example.experiment.\(metricID)" }
    private var defaultsKey: String { "HitchScopeExample.performanceToggle.\(metricID)" }

    var isOn: Bool {
        get { UserDefaults.standard.bool(forKey: defaultsKey) }
        nonmutating set {
            UserDefaults.standard.set(newValue, forKey: defaultsKey)
            HitchScope.reportState(domain, label: newValue ? "fixed" : "unfixed")
        }
    }

    /// Re-asserts the persisted value on the domain - call from the owning
    /// screen's onAppear so the experiment state is current even when the
    /// toggle itself wasn't touched this session.
    func reportCurrentState() {
        HitchScope.reportState(domain, label: isOn ? "fixed" : "unfixed")
    }
}

/// A labeled on/off row plus a description of what each side does - shown
/// near a screen's trigger so it reads as an A/B comparison, not a bare switch.
struct PerformanceToggleRow: View {
    let metricID: String
    let unfixedDescription: String
    let fixedDescription: String

    @State private var isOn: Bool

    init(metricID: String, unfixedDescription: String, fixedDescription: String) {
        self.metricID = metricID
        self.unfixedDescription = unfixedDescription
        self.fixedDescription = fixedDescription
        _isOn = State(initialValue: PerformanceToggle(metricID: metricID).isOn)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Fixed", isOn: $isOn)
                .tint(HSPalette.accent)
                .foregroundStyle(HSPalette.text)
                .onChange(of: isOn) { _, newValue in
                    PerformanceToggle(metricID: metricID).isOn = newValue
                }
            Text(isOn ? fixedDescription : unfixedDescription)
                .font(.caption2)
                .foregroundStyle(HSPalette.textSecondary)
        }
    }
}
