// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeWhisperer",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "ClaudeWhisperer",
            path: "Sources/ClaudeWhisperer"
        )
    ]
)
