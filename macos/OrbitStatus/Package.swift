// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OrbitStatus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OrbitStatus", targets: ["OrbitStatus"]),
        .executable(name: "OrbitConnectAgent", targets: ["OrbitConnectAgent"]),
        .library(name: "OrbitConnectPolicy", targets: ["OrbitConnectPolicy"]),
        .library(name: "OrbitConnectAgentProtocol", targets: ["OrbitConnectAgentProtocol"]),
    ],
    targets: [
        .target(name: "OrbitConnectPolicy"),
        .target(name: "OrbitConnectAgentProtocol"),
        .executableTarget(
            name: "OrbitConnectAgent",
            dependencies: ["OrbitConnectAgentProtocol"]
        ),
        .executableTarget(
            name: "OrbitStatus",
            dependencies: [
                "OrbitConnectPolicy",
                "OrbitConnectAgentProtocol",
            ]
        ),
        .testTarget(
            name: "OrbitStatusTests",
            dependencies: [
                "OrbitStatus",
                "OrbitConnectPolicy",
                "OrbitConnectAgentProtocol",
            ]
        ),
    ]
)
