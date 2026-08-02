// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MarkoDarko",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "MarkoDarko",
            path: "Sources/MarkoDarko"
        )
    ]
)
