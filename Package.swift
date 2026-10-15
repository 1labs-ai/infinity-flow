// swift-tools-version:5.10
// Builds Infinity Flow with the Command Line Tools alone; `scripts/build-app.sh` wraps it into an app.
// Xcode users can keep using project.yml (XcodeGen), which also runs the tests.
import PackageDescription

let package = Package(
    name: "InfinityFlow",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "InfinityFlow",
            path: "Sources",
            // The app icon is compiled into AppIcon.icns by the build script; actool needs Xcode.
            exclude: ["Assets.xcassets"]),
    ]
)
