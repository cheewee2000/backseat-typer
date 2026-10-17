// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Omnikeys",
    platforms: [.macOS("26.0")],
    targets: [
        .executableTarget(
            name: "Omnikeys",
            path: "Sources/Omnikeys",
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("FoundationModels"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("ServiceManagement"),
            ]
        )
    ]
)
