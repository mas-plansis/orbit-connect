// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "OrbitStatus",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OrbitStatus", targets: ["OrbitStatus"]),
        .library(name: "OrbitConnectPolicy", targets: ["OrbitConnectPolicy"]),
    ],
    targets: [
        .target(name: "OrbitConnectPolicy"),
        .target(
            name: "OrbitConnectFilterExtension",
            dependencies: ["OrbitConnectPolicy"],
            path: "SystemExtension/Sources"
        ),
        .executableTarget(
            name: "OrbitStatus",
            dependencies: ["OrbitConnectPolicy"]
        ),
        .testTarget(
            name: "OrbitStatusTests",
            dependencies: [
                "OrbitStatus",
                "OrbitConnectPolicy",
                "OrbitConnectFilterExtension",
            ]
        ),
    ]
)
