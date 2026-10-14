// swift-tools-version: 5.9
// Сборка и тесты Core (ios/JAMbo.swiftpm/Core, символическая ссылка Sources/Core) на Linux и Mac.
// Запуск: . ios/tools/swift-env.sh && cd ios/CoreTests && swift test
import PackageDescription

let package = Package(
    name: "CoreTests",
    platforms: [.macOS("15.0"), .iOS("18.0")],
    targets: [
        .target(name: "Core", path: "Sources/Core"),
        .testTarget(name: "CoreTests", dependencies: ["Core"], path: "Tests/CoreTests"),
    ],
    swiftLanguageVersions: [.v5]
)
