// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FaderCore",
    products: [
        .library(name: "FaderCore", targets: ["FaderCore"])
    ],
    targets: [
        .target(name: "FaderCore"),
        .testTarget(name: "FaderCoreTests", dependencies: ["FaderCore"])
    ]
)
