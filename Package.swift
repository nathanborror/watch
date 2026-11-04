// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Watch",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Watch",
            path: "Sources/Watch"
        )
    ]
)
