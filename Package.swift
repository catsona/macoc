// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Capswitch",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Capswitch", targets: ["Capswitch"]),
    ],
    targets: [
        .target(
            name: "CapswitchCore",
            path: "Sources/Capswitch"
        ),
        .executableTarget(
            name: "Capswitch",
            dependencies: ["CapswitchCore", "CapswitchHID"],
            path: "Sources/CapswitchApp",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .target(
            name: "CapswitchHID",
            path: "Sources/CapswitchHID",
            publicHeadersPath: "include",
            linkerSettings: [.linkedFramework("IOKit")]
        ),
        .testTarget(
            name: "CapswitchCoreTests",
            dependencies: ["CapswitchCore"],
            path: "Tests/CapswitchCoreTests"
        ),
    ]
)
