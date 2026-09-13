import Foundation

/// Persisted across launches so the app can deliberately stall its *next*
/// cold start - `appLaunch` diagnostics are about launch duration, which
/// can't be produced by an in-session button tap the way a crash/hang can.
enum SlowLaunchFlag {
  private static let key = "HitchScopeExample.slowNextLaunch"

  static var isArmed: Bool {
    UserDefaults.standard.bool(forKey: key)
  }

  static func arm() {
    UserDefaults.standard.set(true, forKey: key)
  }

  /// Clears the flag and returns whether it had been armed - called once,
  /// as early as possible in app init, so a crash mid-stall can't wedge
  /// every future launch into stalling forever.
  static func consume() -> Bool {
    let wasArmed = UserDefaults.standard.bool(forKey: key)
    UserDefaults.standard.set(false, forKey: key)
    return wasArmed
  }
}
