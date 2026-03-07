// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeWhisperer",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeWhisperer",
            path: "Sources/ClaudeWhisperer"
        )
    ]
)
