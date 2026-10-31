import Foundation
@testable import Core

/// Пути к Resources в репозитории (на iPad — bundle приложения, Golden.directory).
enum GoldenPaths {
    static let resourcesDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("JAMbo.swiftpm/Resources")

    static let goldenDir = resourcesDir.appendingPathComponent("golden")
}
