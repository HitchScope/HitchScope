import Foundation

/// Entry point for configuring HitchScope in your app.
///
/// HitchScope relays real MetricKit diagnostics (crash, hang, launch,
/// memory exception) via Apple's StateReporting API, which is general —
/// not screen-specific. You choose which state-reporting domains to track;
/// none is privileged. See the README for worked examples (screens,
/// A/B experiments, heavy subsystems, funnel stages, entitlement tier).
public struct HitchScope {
  private init() {}

  /// Every state-reporting domain you intend to use must be declared here —
  /// MetricKit fixes its enabled domains when the manager is constructed
  /// and has no way to add one later. Calling this a second time has no
  /// effect (idempotent — avoids double-subscribing to MetricKit).
  public static func configure(apiKey: String, trackedStates: Set<String>) {
    Task { await HitchScopeRuntime.shared.start(apiKey: apiKey, trackedStates: trackedStates) }
  }

  /// Report a state transition on a declared domain. `label` should be one
  /// of a small, fixed set of values for that domain (e.g. "Checkout", not
  /// "Checkout-\(orderID)") — put dynamic/continuous values in
  /// `volatileMetadata` instead, or they'll fragment your data into buckets
  /// too small to be meaningful.
  ///
  /// Passing `nil` clears the active state for that domain. Passing `""` is
  /// refused (logged) rather than forwarded, since Apple's API crashes on
  /// an empty string. Redundant calls (same label+metadata as current) are
  /// cheap/safe — StateReporting no-ops them.
  ///
  /// Do not call this at high frequency (e.g. per-frame, in a scroll
  /// handler) — StateReporting rate-limits at human-interaction timescales
  /// and silently drops data called faster than that.
  public static func reportState(
    _ domain: String,
    label: String?,
    stableMetadata: [String: HitchScopeMetadataValue] = [:],
    volatileMetadata: [String: HitchScopeMetadataValue] = [:]
  ) {
    Task {
      await HitchScopeRuntime.shared.reportState(
        domain: domain,
        label: label,
        stableMetadata: stableMetadata,
        volatileMetadata: volatileMetadata
      )
    }
  }

  /// Update volatile metadata for the currently active state on a domain,
  /// without a full transition. No-op if no state is currently active on
  /// that domain. Same rate-limit caveat as `reportState` applies.
  public static func updateVolatileMetadata(
    _ domain: String, _ metadata: [String: HitchScopeMetadataValue]
  ) {
    Task {
      await HitchScopeRuntime.shared.updateVolatileMetadata(domain: domain, metadata: metadata)
    }
  }
}
