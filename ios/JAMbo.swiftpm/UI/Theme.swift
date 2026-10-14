import SwiftUI

/// Цветовые токены — те же, что в вебе (src/style.css): тёмная и светлая темы.
struct Theme {
    let bg: Color
    let panel: Color
    let line: Color
    let text: Color
    let dim: Color
    let off: Color
    let accent: Color
    let onAccent: Color
    let rec: Color
    let gr: Color
    let meterTrack: Color

    static let dark = Theme(
        bg: Color(hex: 0x111111), panel: Color(hex: 0x1c1c1c), line: Color(hex: 0x333333),
        text: Color(hex: 0xececec), dim: Color(hex: 0x8a8a8a), off: Color(hex: 0x3d3d3d),
        accent: Color(hex: 0xffc81e), onAccent: Color(hex: 0x111111), rec: Color(hex: 0xff2b2b),
        gr: Color(hex: 0xff8a3d), meterTrack: Color(hex: 0x3a3a3a)
    )

    static let light = Theme(
        bg: Color(hex: 0xe6e5e1), panel: Color(hex: 0xf7f6f3), line: Color(hex: 0xcfceca),
        text: Color(hex: 0x161616), dim: Color(hex: 0x77766f), off: Color(hex: 0xc4c3be),
        accent: Color(hex: 0xf0b800), onAccent: Color(hex: 0x161616), rec: Color(hex: 0xe01418),
        gr: Color(hex: 0xf08a24), meterTrack: Color(hex: 0xcfcfcf)
    )

    static func of(_ scheme: ColorScheme) -> Theme {
        return scheme == .dark ? Theme.dark : Theme.light
    }
}

extension Color {
    init(hex: UInt32) {
        let r = Double((hex >> 16) & 0xff) / 255
        let g = Double((hex >> 8) & 0xff) / 255
        let b = Double(hex & 0xff) / 255
        self.init(.sRGB, red: r, green: g, blue: b, opacity: 1)
    }
}

/// Тема приложения: SYSTEM, LIGHT или DARK (как APPEARANCE в вебе).
enum Appearance: String, CaseIterable {
    case system = "SYSTEM"
    case light = "LIGHT"
    case dark = "DARK"

    var scheme: ColorScheme? {
        switch self {
        case .system: return nil
        case .light: return .light
        case .dark: return .dark
        }
    }
}

private struct ThemeKey: EnvironmentKey {
    static let defaultValue: Theme = Theme.dark
}

extension EnvironmentValues {
    var theme: Theme {
        get { return self[ThemeKey.self] }
        set { self[ThemeKey.self] = newValue }
    }
}
