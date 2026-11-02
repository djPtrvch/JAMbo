import XCTest
@testable import Core

/// Порядок папок библиотеки: перетаскивание (moveFolder) — свой порядок; новые папки — после, по имени;
/// RECORDINGS — всегда первой; старый файл (без order) — по имени.
final class LibraryFolderOrderTests: XCTestCase {
    private func names(_ l: Library) -> [String] {
        return l.children(Library.root).map { $0.name }
    }

    func testMoveFolderKeepsOrder() {
        var l = Library()
        for n in ["Bass", "Drums", "Keys"] { l.createFolder(Library.root, n) }
        XCTAssertEqual(names(l), ["RECORDINGS", "Bass", "Drums", "Keys"])
        l.moveFolder(Library.root, from: 2, to: 0)
        XCTAssertEqual(names(l), ["RECORDINGS", "Keys", "Bass", "Drums"])
        l.createFolder(Library.root, "Acid")
        XCTAssertEqual(names(l), ["RECORDINGS", "Keys", "Bass", "Drums", "Acid"], "новая — после расставленных")
        l.moveFolder(Library.root, from: 3, to: 1)
        XCTAssertEqual(names(l), ["RECORDINGS", "Keys", "Acid", "Bass", "Drums"])
        // Сохранение и загрузка — порядок тот же.
        let data: Data = try! JSONEncoder().encode(l)
        let back: Library = try! JSONDecoder().decode(Library.self, from: data)
        XCTAssertEqual(names(back), names(l))
        // Без поля order (старый файл) — по имени.
        let old: String = String(data: data, encoding: .utf8)!.replacingOccurrences(of: #","order":\d+(\.\d+)?"#,
                                                                                    with: "", options: .regularExpression)
        let plain: Library = try! JSONDecoder().decode(Library.self, from: old.data(using: .utf8)!)
        XCTAssertEqual(names(plain), ["RECORDINGS", "Acid", "Bass", "Drums", "Keys"])
    }
}
