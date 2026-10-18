// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MenuBoard",
    platforms: [.macOS(.v15)],
    targets: [
        .executableTarget(
            name: "MenuBoard",
            path: "Sources/MenuBoard",
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("IOKit"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("Accelerate"),
            ]
        )
    ]
)
