import Foundation
@testable import Core

/// Эталоны сверок с вебом — ios/CoreTests/golden (в приложение не входят: SELF-TEST убран 1.11).
enum GoldenPaths {
    static let goldenDir: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .appendingPathComponent("golden")
}
