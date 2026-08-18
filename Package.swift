// swift-tools-version: 5.9
import PackageDescription

// Viewer is macOS-only (SwiftUI). Core + asv + asv-check build on macOS and Linux.
var products: [Product] = [
    .library(name: "AgentSessionCore", targets: ["AgentSessionCore"]),
    .executable(name: "asv", targets: ["asv"]),
    .executable(name: "asv-check", targets: ["asv-check"]),
]

var targets: [Target] = [
    .target(
        name: "AgentSessionCore",
        path: "Sources/AgentSessionCore",
        linkerSettings: [
            .linkedLibrary("sqlite3"),
        ]
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
        name: "asv-check",
        dependencies: [
            "AgentSessionCore",
        ],
        path: "Sources/asv-check"
    ),
    .testTarget(
        name: "AgentSessionCoreTests",
        dependencies: ["AgentSessionCore"],
        path: "Tests/AgentSessionCoreTests",
        resources: [
            .copy("Fixtures"),
        ]
    ),
]

#if os(macOS)
products.append(
    .executable(name: "AgentSessionViewer", targets: ["AgentSessionViewer"])
)
targets.append(
    .executableTarget(
        name: "AgentSessionViewer",
        dependencies: [
            "AgentSessionCore",
        ],
        path: "Sources/AgentSessionViewer"
    )
)
#endif

let package = Package(
    name: "agent-session-viewer",
    platforms: [
        .macOS(.v14),
    ],
    products: products,
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0"),
    ],
    targets: targets
)
