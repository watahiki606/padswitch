// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PadSwitch",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "PadSwitchCore",
            linkerSettings: [
                .linkedFramework("IOBluetooth"),
            ]
        ),
        .executableTarget(
            name: "padswitch-cli",
            dependencies: ["PadSwitchCore"]
        ),
        .executableTarget(
            name: "PadSwitchApp",
            dependencies: ["PadSwitchCore"]
        ),
        .testTarget(
            name: "PadSwitchCoreTests",
            dependencies: ["PadSwitchCore"]
        ),
    ]
)
