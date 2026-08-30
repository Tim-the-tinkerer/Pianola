// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Pianola",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Pianola", targets: ["Pianola"]),
    ],
    targets: [
        .executableTarget(
            name: "Pianola",
            path: "Sources/Pianola",
            resources: [
                .copy("Resources/MIDI"),
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("AudioToolbox"),
                .linkedFramework("CoreAudio"),
            ]
        ),
    ]
)
