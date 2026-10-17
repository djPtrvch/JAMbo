import Foundation
@testable import Core

/// Пути к Resources в репозитории (на iPad — bundle приложения, PlaitsSelfTest.directory).
enum PlaitsGolden {
    static let resourcesDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().appendingPathComponent("JAMbo.swiftpm/Resources")

    static let tablesDir = resourcesDir.appendingPathComponent("plaits")
    static let goldenDir = resourcesDir.appendingPathComponent("golden")

    /// Таблицы с a0 веба (как у эталонов).
    static let resources: PlaitsResources? = PlaitsSelfTest.webResources(tablesDir)
}
