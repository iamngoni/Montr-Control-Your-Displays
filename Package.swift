// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Montr",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "Montr", targets: ["Montr"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.5.0"),
        .package(url: "https://github.com/getsentry/sentry-cocoa", from: "8.20.0")
    ],
    targets: [
        .executableTarget(
            name: "Montr",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle"),
                .product(name: "Sentry", package: "sentry-cocoa")
            ],
            path: "Montr — Control Your Displays",
            exclude: [
                "Assets.xcassets",
                "Info.plist",
                "Montr.entitlements"
            ],
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "MontrTests",
            dependencies: ["Montr"],
            path: "Montr — Control Your DisplaysTests"
        )
    ]
)
