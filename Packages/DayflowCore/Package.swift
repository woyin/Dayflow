// swift-tools-version: 5.9
// Command-line build of the Foundation-only core logic, so it can be compiled and
// tested with just the Swift toolchain (no Xcode). The app still builds with
// Dayflow/Dayflow.xcodeproj; Sources/DayflowCore holds symlinks to the same files.
import PackageDescription

let package = Package(
  name: "DayflowCore",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "Dayflow"),
    .testTarget(name: "DayflowTests", dependencies: ["Dayflow"]),
  ]
)
