# HitchScope

Performance intelligence for iOS, broken down by whatever app state actually matters to you — not one blended average.

Every existing iOS monitoring tool reports app-wide averages — one hang-rate number, one launch-time percentile — which mathematically hides the exact condition you're trying to find. iOS 27's rebuilt MetricKit, with its StateReporting API, makes true state-level attribution possible for the first time without custom instrumentation. HitchScope is the SDK that gets that data out of your app and into [HitchScope](https://hitchscope.com) (or your own backend).

HitchScope is additive, not a replacement for your crash reporter. It plugs in alongside Crashlytics or Sentry and adds the state-level layer they don't have.

**HitchScope's SDK is deliberately not screen-specific.** Apple's StateReporting API is general — apps report transitions on any domain they choose, with MetricKit later breaking diagnostics down by whichever domains were active. HitchScope relays that data as-is; it doesn't privilege "screen" over any other use of the API. A few things people track with it:

```swift
import HitchScope

// Every domain you'll use has to be declared upfront - MetricKit fixes its
// enabled domains when the manager is constructed and can't add more later.
HitchScope.configure(apiKey: "YOUR_API_KEY", trackedStates: [
    "com.myapp.screen",
    "com.myapp.experiment.checkout_redesign",
    "com.myapp.subsystem",
])
```

**Current screen** — the obvious one, call it from `.onAppear` (SwiftUI) or `viewDidAppear` (UIKit):

```swift
HitchScope.reportState("com.myapp.screen", label: "Checkout")
```

**A/B experiment or feature-flag variant** — correlate performance with which arm a user is bucketed into:

```swift
HitchScope.reportState("com.myapp.experiment.checkout_redesign", label: "variant_b")
```

**A heavy subsystem being active** (camera/AR session, video playback, large list rendering) — these are disproportionate hang/memory sources regardless of which screen hosts them:

```swift
HitchScope.reportState("com.myapp.subsystem", label: "camera_active")
// ...
HitchScope.reportState("com.myapp.subsystem", label: nil) // clears the state when it ends
```

Other domains worth considering, not built in, just report them: funnel/flow stage (onboarding vs. main app vs. settings), user tier/entitlement, entry-point/attribution source for cold-start correlation.

## Metadata

`reportState` also takes stable and volatile metadata (dates, strings, integers, floats) if a fixed label isn't enough context on its own:

```swift
HitchScope.updateVolatileMetadata("com.myapp.subsystem", ["frameRate": .init(currentFPS)])
```

Put continuously-changing values here, not in the label — Apple's own guidance is that a label like `"Score-\(score)"` fragments your data into buckets too small to be meaningful; a small, fixed set of labels (`"Low"`, `"Medium"`, `"High"`) is what state-reporting domains are for.

## Constraints worth knowing

- **Rate limit**: report state at human-interaction timescales (button taps, screen navigation) — calling `reportState`/`updateVolatileMetadata` in a tight loop or per-frame causes StateReporting to silently drop data. This is Apple's own limit, not something HitchScope can work around transparently.
- **Empty string vs. `nil`**: pass `nil` to clear a domain's active state. Passing `""` is refused by HitchScope (logged, not forwarded) — Apple's underlying API crashes the process on an empty string.
- **Undeclared domains are ignored** (logged): every domain you intend to use must be listed in `configure(trackedStates:)` up front.

## Status

Real MetricKit/StateReporting wiring is in — `configure` subscribes to `MetricManager.diagnosticReports` and relays crash, hang, launch, and memory-exception diagnostics. Not yet handled: `MetricManager.metricReports` (aggregated histograms — no slot in the current backend contract), full symbolicated call stacks (payloads carry a small summary, not the full tree), and on-disk persistence for events buffered but not yet uploaded (in-memory only for now — lost if the app terminates before the next upload).

## Requirements

iOS 27+. This SDK is built on APIs introduced in iOS 27 — there's no fallback for earlier versions.

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/HitchScope/HitchScope.git", from: "0.0.1")
```

## Development

Requires Xcode with the iOS 27 SDK. `swift build`/`swift test` alone won't work — they compile for the macOS host by default, and this package is iOS-only (no macOS platform declared). Build and test against an iOS simulator instead:

```bash
xcodebuild test -scheme HitchScope -destination 'platform=iOS Simulator,name=iPhone 18 Pro'
```

(Swap in whatever simulator you have available — `xcrun simctl list devices` to see options.)

An `Example/` app is included for exercising local SDK changes on a simulator without publishing a release. See `Example/README.md`.

## License

MIT — see [LICENSE](LICENSE).
