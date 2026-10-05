// swift-tools-version: 5.9
// Candidate A adapter to the G1 common native module (iOS) - NON-PRODUCTION / SYNTHETIC DATA ONLY.
import Foundation
import PackageDescription

// Flutter refers to this plugin through a symlink (ios/Flutter/ephemeral/Packages/.packages/g1_native); the common
// module is located from the real path of this manifest.
let here = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath().deletingLastPathComponent()
let common = here.appendingPathComponent("../../../../../native-common/ios").standardizedFileURL.path

let package = Package(
    name: "g1_native",
    platforms: [.iOS("16.0")],
    products: [
        .library(name: "g1-native", targets: ["g1_native"]),
    ],
    dependencies: [
        .package(name: "G1NativeCommon", path: common),
    ],
    targets: [
        .target(
            name: "g1_native",
            dependencies: [.product(name: "G1NativeCommon", package: "G1NativeCommon")]
        ),
    ]
)
