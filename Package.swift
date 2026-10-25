// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "macoc",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "macoc", targets: ["macoc"]),
    ],
    targets: [
        .target(
            name: "CapswitchCore",
            path: "Sources/Capswitch"
        ),
        .executableTarget(
            name: "macoc",
            dependencies: ["CapswitchCore", "CapswitchHID"],
            path: "Sources/CapswitchApp",
            linkerSettings: [
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
            ]
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
