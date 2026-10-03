// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SimpleHiDPIScaler",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "SimpleHiDPIScaler", targets: ["SimpleHiDPIScaler"]),
        .executable(name: "SelfTest", targets: ["SelfTest"]),
        .executable(name: "LiveProbe", targets: ["LiveProbe"]),
        .library(name: "SimpleHiDPIScalerCore", targets: ["SimpleHiDPIScalerCore"]),
    ],
    targets: [
        .target(
            name: "PrivateBridge",
            path: "Sources/PrivateBridge",
            publicHeadersPath: "include"
        ),
        .target(
            name: "SimpleHiDPIScalerCore",
            dependencies: ["PrivateBridge"],
            path: "Sources/SimpleHiDPIScalerCore"
        ),
        .executableTarget(
            name: "SimpleHiDPIScaler",
            dependencies: ["SimpleHiDPIScalerCore"],
            path: "Sources/SimpleHiDPIScaler"
        ),
        .executableTarget(
            name: "SelfTest",
            dependencies: ["SimpleHiDPIScalerCore"],
            path: "Sources/SelfTest"
        ),
        .executableTarget(
            name: "LiveProbe",
            dependencies: ["SimpleHiDPIScalerCore"],
            path: "Sources/LiveProbe"
        ),
        .testTarget(
            name: "SimpleHiDPIScalerTests",
            dependencies: ["SimpleHiDPIScalerCore"],
            path: "Tests/SimpleHiDPIScalerTests"
        ),
    ]
)
