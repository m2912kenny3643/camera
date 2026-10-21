// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "R6CameraCore",
    platforms: [.macOS(.v13)],
    products: [.library(name: "R6Camera", targets: ["R6Camera"])],
    targets: [
        .target(name: "R6Camera", path: "R6Camera/Core"),
        .testTarget(name: "R6CameraTests", dependencies: ["R6Camera"], path: "Tests")
    ]
)
