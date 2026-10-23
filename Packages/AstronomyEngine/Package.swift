// swift-tools-version: 6.0
// Astronomy Engine v2.1.19 (C), by Don Cross, MIT license: https://github.com/cosinekitty/astronomy
// Vendored unchanged from source/c/ at tag v2.1.19.
import PackageDescription

let package = Package(
    name: "AstronomyEngine",
    platforms: [.iOS(.v18)],
    products: [
        .library(name: "CAstronomy", targets: ["CAstronomy"]),
    ],
    targets: [
        .target(name: "CAstronomy", path: "Sources/CAstronomy"),
    ]
)
