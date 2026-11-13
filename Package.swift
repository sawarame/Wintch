// swift-tools-version: 6.0
// Wintch パッケージ定義ファイル（Apple標準フレームワークのみ使用・外部依存ゼロ）

import PackageDescription

let package = Package(
    name: "Wintch",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "WintchCore",
            targets: ["WintchCore"]
        ),
        .executable(
            name: "Wintch",
            targets: ["Wintch"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "WintchCore",
            dependencies: [],
            path: "Sources/WintchCore"
        ),
        .executableTarget(
            name: "Wintch",
            dependencies: ["WintchCore"],
            path: "Sources/Wintch"
        ),
        .testTarget(
            name: "WintchCoreTests",
            dependencies: ["WintchCore"],
            path: "Tests/WintchCoreTests"
        )
    ]
)
