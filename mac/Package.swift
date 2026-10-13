// swift-tools-version:5.9
// Pastebird for macOS. Build the app with build.sh, which wraps this executable in Pastebird.app.
import PackageDescription

let package = Package(
    name: "Pastebird",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "Pastebird",
            path: "Sources/Pastebird"
        ),
    ]
)
