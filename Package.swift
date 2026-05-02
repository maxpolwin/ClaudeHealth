// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ClaudeHealth",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeHealth",
            path: "Sources/ClaudeHealth",
            swiftSettings: [
                .enableUpcomingFeature("BareSlashRegexLiterals"),
                .enableUpcomingFeature("ConciseMagicFile")
            ]
        )
    ]
)
