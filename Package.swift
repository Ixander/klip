// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Klip",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Klip",
            path: "Sources/Klip",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
