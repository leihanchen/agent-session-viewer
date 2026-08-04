// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "agent-session-viewer",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "AgentSessionCore", targets: ["AgentSessionCore"]),
        .executable(name: "asv", targets: ["asv"]),
        .executable(name: "AgentSessionViewer", targets: ["AgentSessionViewer"]),
        .executable(name: "asv-check", targets: ["asv-check"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: [
        .target(
            name: "AgentSessionCore",
            path: "Sources/AgentSessionCore"
        ),
        .executableTarget(
            name: "asv",
            dependencies: [
                "AgentSessionCore",
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/asv"
        ),
        .executableTarget(
            name: "AgentSessionViewer",
            dependencies: [
                "AgentSessionCore",
            ],
            path: "Sources/AgentSessionViewer"
        ),
        .executableTarget(
            name: "asv-check",
            dependencies: [
                "AgentSessionCore",
            ],
            path: "Sources/asv-check"
        ),
        // XCTest target — requires full Xcode (not Command Line Tools alone).
        .testTarget(
            name: "AgentSessionCoreTests",
            dependencies: ["AgentSessionCore"],
            path: "Tests/AgentSessionCoreTests",
            resources: [
                .copy("Fixtures"),
            ]
        ),
    ]
)
