// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Tock",
    platforms: [.macOS("26.0")],
    products: [.executable(name: "Tock", targets: ["TockApp"])],
    targets: [
        .target(name: "TockCore"),
        .executableTarget(name: "TockApp", dependencies: ["TockCore"]),
        .testTarget(name: "TockTests", dependencies: ["TockCore"])
    ]
)
