import Foundation

// Пакет голов (15.11, решение пользователя): головы для меню HEAD — не в сборке, а отдельным файлом .zip (IMPORT в меню
// HEAD): rooms.json (тот же вид, что в ресурсах: комнаты с space и head_name) и WAV-импульсы комнат. Генератор —
// ios/tools/generate_room_srir.py --pack. Пакет хранится в папке приложения и добавляет комнаты к комнатам сборки.

public enum HeadPack {
    /// Разбор архива: комнаты из rooms.json и файлы (имя → данные; папки в архиве не важны). Нет rooms.json, нет комнат
    /// или нет файла импульса комнаты — nil и причина.
    public static func unpack(_ data: Data) -> (rooms: [RoomInfo], files: [String: Data])? {
        guard let entries = Zip.read(data) else { return nil }
        var files: [String: Data] = [:]
        for e in entries where !e.isFolder {
            let name: String = (e.path as NSString).lastPathComponent
            if name.hasPrefix(".") { continue }
            files[name] = e.data
        }
        guard let json = files["rooms.json"] else { return nil }
        let rooms: [RoomInfo] = RoomInfo.list(json).filter { files[$0.file] != nil }
        if rooms.isEmpty { return nil }
        return (rooms, files)
    }

    /// Имена всех файлов, на которые ссылаются комнаты (импульс, HEAD, выровненные варианты).
    public static func referenced(_ rooms: [RoomInfo]) -> [String] {
        var out: [String] = ["rooms.json"]
        for r in rooms {
            for f in [r.file, r.headFile, r.flatFile, r.flatHeadFile] where !f.isEmpty && !out.contains(f) {
                out.append(f)
            }
        }
        return out
    }

    /// Головы пакета (имена в меню HEAD) по порядку, без повторов.
    public static func heads(_ rooms: [RoomInfo]) -> [String] {
        var out: [String] = []
        for r in rooms where !out.contains(r.headName) { out.append(r.headName) }
        return out
    }
}
