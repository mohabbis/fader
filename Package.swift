// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Fader",
    platforms: [
        .macOS("14.2")
    ],
    products: [
        .executable(name: "Fader", targets: ["Fader"]),
        .library(name: "FaderCore", targets: ["FaderCore"])
    ],
    targets: [
        .target(name: "FaderCore"),
        .executableTarget(
            name: "Fader",
            dependencies: ["FaderCore"],
            path: "Fader",
            exclude: ["Info.plist", "Assets.xcassets"]
        ),
        .testTarget(name: "FaderCoreTests", dependencies: ["FaderCore"])
    ]
)
