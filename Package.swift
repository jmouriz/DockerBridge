// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "DockerBridge",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "DockerBridge", targets: ["DockerBridge"]),
        .executable(name: "DockerBridgeLoginItem", targets: ["DockerBridgeLoginItem"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-nio.git", from: "2.81.0"),
        .package(url: "https://github.com/apple/swift-nio-ssh.git", from: "0.14.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0"..<"5.0.0")
    ],
    targets: [
        .executableTarget(
            name: "DockerBridge",
            dependencies: [
                .product(name: "NIOCore", package: "swift-nio"),
                .product(name: "NIOPosix", package: "swift-nio"),
                .product(name: "NIOSSH", package: "swift-nio-ssh"),
                .product(name: "Crypto", package: "swift-crypto")
            ],
            path: "Sources/DockerBridge",
            swiftSettings: [
                .unsafeFlags(["-parse-as-library"])
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Security"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("WebKit")
            ]
        ),
        .executableTarget(
            name: "DockerBridgeLoginItem",
            path: "Sources/DockerBridgeLoginItem",
            linkerSettings: [
                .linkedFramework("AppKit")
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
