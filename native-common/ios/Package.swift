// swift-tools-version:5.9
// G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
// Consumed by candidate C and candidate A as a local Swift package and by candidate B through G1NativeCommon.podspec.
import PackageDescription

let package = Package(
    name: "G1NativeCommon",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "G1NativeCommon", targets: ["G1NativeCommon"]),
    ],
    targets: [
        .target(
            name: "G1NativeCommon",
            resources: [.copy("Resources/g1")]
        ),
        .testTarget(
            name: "G1NativeCommonTests",
            dependencies: ["G1NativeCommon"]
        ),
    ]
)
