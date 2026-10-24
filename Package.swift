// swift-tools-version: 6.2
import PackageDescription

let package = Package(
  name: "LinkWheel",
  platforms: [.macOS(.v15)],
  targets: [
    // Pure logic: no AppKit, no side effects. Everything worth testing lives here.
    .target(name: "LinkWheelCore"),
    .executableTarget(
      name: "LinkWheel",
      dependencies: ["LinkWheelCore"],
      swiftSettings: [.defaultIsolation(MainActor.self)]
    ),
    .testTarget(name: "LinkWheelCoreTests", dependencies: ["LinkWheelCore"]),
  ]
)
