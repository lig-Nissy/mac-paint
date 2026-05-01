// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacPaint",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "MacPaint",
            path: "Sources/MacPaint"
        )
    ]
)
