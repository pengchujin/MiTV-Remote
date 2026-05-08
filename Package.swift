// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MiTV-Remote",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MiTV-Remote", targets: ["TVVolumeCEC"])
    ],
    targets: [
        .target(
            name: "CECPrivateBridge",
            path: "Sources/CECPrivateBridge",
            publicHeadersPath: "include"
        ),
        .executableTarget(
            name: "TVVolumeCEC",
            dependencies: ["CECPrivateBridge"],
            path: "Sources/TVVolumeCEC"
        )
    ]
)
