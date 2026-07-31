// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkdownWriter",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MarkdownWriter",
            path: "Sources/MarkdownWriter"
        )
    ]
)
