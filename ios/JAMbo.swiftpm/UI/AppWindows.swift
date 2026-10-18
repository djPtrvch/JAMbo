import SwiftUI

/// Окна раздела APP бутерброда (S9e): поверх экрана, название слева, ✕ справа в верхней строке.
enum AppWindow: String, CaseIterable {
    case diagnostics = "DIAGNOSTICS"
    case selfTest = "SELF-TEST"
    case licenses = "LICENSES"
}

struct AppWindowView: View {
    let model: AppModel
    let window: AppWindow
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text(window.rawValue).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                CloseButton { model.appWindow = nil }
            }
            content
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(theme.bg, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).stroke(theme.line, lineWidth: 1))
    }

    @ViewBuilder
    private var content: some View {
        switch window {
        case .diagnostics: DiagnosticsView(model: model)
        case .selfTest: SelfTestPanel()
        case .licenses: LicensesView()
        }
    }
}

/// Лицензия стороннего кода: название и текст (Resources/licenses).
struct LicenseText: Identifiable {
    let id: String
    let title: String
    let text: String

    /// Названия по имени файла; файл без названия — под своим именем.
    static let titles: [String: String] = [
        "LICENSE-MI": "Mutable Instruments Plaits and stmlib — MIT License",
    ]

    /// Тексты из ресурсов приложения (LICENSE-*.txt), по имени файла.
    static func load() -> [LicenseText] {
        guard let dir = PlaitsSelfTest.directory(of: "LICENSE-MI.txt", in: Bundle.main,
                                                 subdirectories: ["licenses", "Resources/licenses"]) else { return [] }
        let names: [String] = (try? FileManager.default.contentsOfDirectory(atPath: dir.path)) ?? []
        var out: [LicenseText] = []
        for n in names.sorted() where n.hasPrefix("LICENSE") && n.hasSuffix(".txt") {
            let base = String(n.dropLast(4))
            guard let text = try? String(contentsOf: dir.appendingPathComponent(n), encoding: .utf8) else { continue }
            out.append(LicenseText(id: base, title: titles[base] ?? base, text: text))
        }
        return out
    }
}

/// LICENSES: сторонний код в приложении и его лицензии (прокрутка пальцем).
struct LicensesView: View {
    @State private var items: [LicenseText] = []
    @Environment(\.theme) private var theme

    var body: some View {
        MenuScroll {
            VStack(alignment: .leading, spacing: 12) {
                SettingsNote(text: "JAMbo includes code ported from these projects. Their licenses:")
                ForEach(items) { item in
                    MenuHead(title: item.title)
                    Text(item.text).font(.system(size: 12, design: .monospaced)).foregroundStyle(theme.text)
                        .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
                }
                if items.isEmpty {
                    SettingsNote(text: "License texts not found in the app resources.")
                }
            }
            .padding(.trailing, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onAppear { items = LicenseText.load() }
    }
}
