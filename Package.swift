// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FlickOff",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Objective-C wrapper over CoreBrightness / DFRBrightness private frameworks.
        .target(name: "TBPrivate", cSettings: [.unsafeFlags(["-fobjc-arc"])], linkerSettings: [.linkedFramework("IOKit")]),
        // Everything testable: controller logic, compatibility report, system adapters.
        .target(
            name: "TouchBarKit",
            dependencies: ["TBPrivate"],
            linkerSettings: [.linkedFramework("IOKit"), .linkedFramework("ServiceManagement")]
        ),
        // SwiftUI menu bar app; build.sh wraps the binary into FlickOff.app.
        .executableTarget(
            name: "FlickOff",
            dependencies: ["TouchBarKit", .product(name: "Sparkle", package: "Sparkle")],
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
        ),
        .testTarget(name: "TouchBarKitTests", dependencies: ["TouchBarKit", "TBPrivate"]),
    ],
    swiftLanguageModes: [.v5]
)
