// swift-tools-version: 6.4
import PackageDescription

let package = Package(
    name: "HitchScope",
    platforms: [.iOS(.v27)],
    products: [
        .library(name: "HitchScope", targets: ["HitchScope"])
    ],
    targets: [
        .target(name: "HitchScope"),
        .testTarget(name: "HitchScopeTests", dependencies: ["HitchScope"])
    ]
)
