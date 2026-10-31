import Foundation
@testable import Core

/// Эталоны — ios/CoreTests/Golden (решение пользователя: из приложения убраны вместе с SELF-TEST — 13 МБ ресурсов
/// мешали сборке в Playgrounds; сверка — только здесь, в тестах Core).
enum GoldenPaths {
    static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("Golden")
}
