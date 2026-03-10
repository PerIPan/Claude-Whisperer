// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OpenWhisperer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "OpenWhisperer",
            path: "Sources/OpenWhisperer"
        )
    ]
)
