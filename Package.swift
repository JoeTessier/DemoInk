// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DemoInk",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "DemoInk",
            path: "Sources/DemoInk",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
            ]
        )
    ]
)
