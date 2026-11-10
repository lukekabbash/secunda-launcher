// swift-tools-version: 6.1

import PackageDescription

let package = Package(
    name: "SecundaLauncher",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .executable(name: "SecundaLauncher", targets: ["SecundaLauncher"])
    ],
    dependencies: [
        // In-app updates. MIT-licensed; pinned exactly so a release build
        // never picks up an unreviewed updater.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")
    ],
    targets: [
        .executableTarget(
            name: "SecundaLauncher",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "app",
            linkerSettings: [
                // SwiftPM puts Sparkle.framework beside the executable, so
                // `swift run` needs to look there. The packaged app adds
                // its own Contents/Frameworks search path.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@loader_path"])
            ]
        )
    ],
    swiftLanguageModes: [.v5]
)
