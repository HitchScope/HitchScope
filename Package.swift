// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "HitchScope",
    platforms: [.iOS(.v13)],
    products: [
        .library(name: "HitchScope", targets: ["HitchScope"])
    ],
    targets: [
        .target(name: "HitchScope"),
        .testTarget(name: "HitchScopeTests", dependencies: ["HitchScope"])
    ]
)
