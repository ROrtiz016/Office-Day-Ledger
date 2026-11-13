// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "OfficeDayCounter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "OfficeDayCounter", targets: ["OfficeDayCounter"])
    ],
    targets: [
        .executableTarget(name: "OfficeDayCounter"),
        .testTarget(name: "OfficeDayCounterTests", dependencies: ["OfficeDayCounter"])
    ],
    swiftLanguageModes: [.v5]
)
