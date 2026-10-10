// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "VizorNativeCleanup",
  platforms: [.macOS(.v13)],
  products: [.executable(name: "vizor-native-cleanup", targets: ["CleanupCommand"])],
  targets: [
    .target(name: "NativeCleanup"),
    .executableTarget(name: "CleanupCommand", dependencies: ["NativeCleanup"]),
    .testTarget(name: "NativeCleanupTests", dependencies: ["NativeCleanup"]),
  ]
)
