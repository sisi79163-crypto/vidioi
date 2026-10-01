// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "VidioiCore",
    products: [.library(name: "VidioiCore", targets: ["VidioiCore"])],
    targets: [
        .target(name: "VidioiCore", path: "Core"),
        .testTarget(name: "VidioiCoreTests", dependencies: ["VidioiCore"], path: "Tests")
    ]
)
