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
    targets: [
        .executableTarget(
            name: "SecundaLauncher",
            path: "app"
        )
    ],
    swiftLanguageModes: [.v5]
)
