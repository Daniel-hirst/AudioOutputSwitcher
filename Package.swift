// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "AudioOutputSwitcher",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "AudioOutputSwitcher",
            path: "Sources/AudioOutputSwitcher",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("CoreAudio"),
                .linkedFramework("AudioToolbox")
            ]
        )
    ]
)
