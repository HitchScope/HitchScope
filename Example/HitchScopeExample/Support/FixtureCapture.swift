import Foundation
import MetricKit
import os.log

/// Harvests real on-device diagnostic/metric reports as JSON fixtures for
/// `HitchScope`'s own test suite (`Tests/HitchScopeTests/Fixtures/`) - not
/// something a real HitchScope integrator would ever ship. This used to
/// live inside the SDK itself (`MetricKitBridge`), but writing raw
/// MetricKit payloads to every user's device forever has no benefit to
/// them, so it now lives here instead, entirely separate from anything
/// `HitchScope.configure` does. `MetricManager` isn't a singleton (plain
/// `public init`, no `.shared`), so this instance and the SDK's own
/// internal one both receive their own independent stream of the same
/// underlying reports without interfering with each other.
enum FixtureCapture {
    private static let log = OSLog(subsystem: "com.hitchscope.example", category: "FixtureCapture")

    static let fixturesDirectory =
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("HitchScopeFixtures", isDirectory: true)

    private static var manager: MetricManager?
    private static var diagnosticsTask: Task<Void, Never>?
    private static var metricsTask: Task<Void, Never>?

    /// `domains` should be the same set passed to `HitchScope.configure` -
    /// captured fixtures need the same state-reporting domains enabled to
    /// carry the same environment data real ingested events would.
    static func start(domains: Set<String>) {
        guard manager == nil else { return }
        let manager = MetricManager(
            enabledStateReportingDomains: Set(domains.map { StateReportingDomain(rawValue: $0) }))
        self.manager = manager

        diagnosticsTask = Task {
            for await report in manager.diagnosticReports {
                capture(report, kind: "diagnostic")
            }
        }
        metricsTask = Task {
            for await report in manager.metricReports {
                capture(report, kind: "metric")
            }
        }
    }

    private static func capture(_ report: some Encodable, kind: String) {
        do {
            try FileManager.default.createDirectory(
                at: fixturesDirectory, withIntermediateDirectories: true)
            let formatter = DateFormatter()
            formatter.dateFormat = "yyyyMMdd'T'HHmmss.SSS"
            let filename = "\(kind)-\(formatter.string(from: Date())).json"
            let data = try JSONEncoder().encode(report)
            try data.write(to: fixturesDirectory.appendingPathComponent(filename))
            os_log(.default, log: Self.log, "captured fixture: %{public}@", filename)
        } catch {
            os_log(
                .error, log: Self.log, "failed to capture fixture: %{public}@",
                String(describing: error))
        }
    }
}
