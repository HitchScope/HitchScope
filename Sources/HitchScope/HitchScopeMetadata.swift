import StateReporting

/// Re-export of StateReporting's own value type — HitchScope doesn't invent
/// its own metadata value representation, just gives a stable name for it at
/// the SDK's public surface.
public typealias HitchScopeMetadataValue = ReportableMetadataValue

/// A single metadata type used for every domain HitchScope reports on.
///
/// Apple's `StateReporter.reporter(for:)` crashes at runtime if called twice
/// for the same domain with different metadata *types* — awkward for a
/// third-party SDK that doesn't know ahead of time what metadata shape a
/// given app wants for a given domain. Using one uniform dictionary-backed
/// type everywhere sidesteps that entirely: every `StateReporter` HitchScope
/// creates is `StateReporter<HitchScopeMetadataDictionary, HitchScopeMetadataDictionary>`,
/// so there's never a type mismatch across repeated `.reporter(for:)` calls.
struct HitchScopeMetadataDictionary: ReportableMetadata {
  let metadataDictionary: [String: ReportableMetadataValue]

  init(_ values: [String: ReportableMetadataValue]) {
    self.metadataDictionary = values
  }
}
