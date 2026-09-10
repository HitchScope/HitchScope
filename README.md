# HitchScope

Screen-level performance intelligence for iOS.

Every existing iOS monitoring tool reports app-wide averages — one hang-rate number, one launch-time percentile — which mathematically hides the exact screen you're trying to find. iOS 27's rebuilt MetricKit, with its StateReporting API, makes true per-screen attribution possible for the first time without custom instrumentation. HitchScope is the SDK that gets that data out of your app and into [Hitchscope](https://hitchscope.com) (or your own backend).

HitchScope is additive, not a replacement for your crash reporter. It plugs in alongside Crashlytics or Sentry and adds the screen-level layer they don't have.

## Status

Early scaffolding. The public API below is a stub — real MetricKit/StateReporting wiring is still in progress.

## Installation

Swift Package Manager:

```swift
.package(url: "https://github.com/hitchscope/HitchScope.git", from: "0.0.1")
```

## Usage

```swift
import HitchScope

HitchScope.configure(apiKey: "YOUR_API_KEY")
```

## Development

An `Example/` app is included for exercising local SDK changes on a simulator without publishing a release. See `Example/README.md`.

## License

MIT — see [LICENSE](LICENSE).
