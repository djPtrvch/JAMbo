import SwiftUI

/// Строка Headphone Monitor в окне коррекции наушников (под строкой EQ) — регуляторы вкладки, выбранной в строке EQ
/// (на месте M/S, DYN, LISTEN): PHONES — CORRECTION (сила коррекции профилем) и TRIM 5 полос ±3 dB; ROOM — TRANSLATION,
/// ANGLE и AMOUNT (Crossfeed); CHECK — MONO, SUB, LEVEL (компенсация громкости, только показ). Поля — как у EQ: палец
/// вверх-вниз, двойной тап — значение по умолчанию.
struct MonitorBar: View {
    static let tabs: [String] = ["PHONES", "ROOM", "CHECK"]
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let m: AppModel = model
        let s: MonitorSettings = m.monitor
        let tab: Int = max(0, min(2, s.tab))
        let items: [AnyView]
        switch tab {
        case 1: items = [AnyView(translationField), angleField(s), amountField(s)]
        case 2: items = [
            AnyView(EqTool(title: "MONO", enabled: true, active: s.mono) { m.setMonitor { $0.mono.toggle() } }),
            AnyView(EqTool(title: "SUB", enabled: true, active: s.sub) { m.setMonitor { $0.sub.toggle() } }),
            AnyView(levelLabel),
        ]
        default: items = [correctionField(s)] + MonitorBar.trimFields(m)
        }
        return MonitorRow(name: MonitorBar.tabs[tab], items: items, height: m.barH)
    }

    /// Кнопка вкладки в строке EQ (горит выбранная).
    static func tabButton(_ m: AppModel, _ k: Int) -> AnyView {
        return AnyView(EqTool(title: MonitorBar.tabs[k], enabled: true, active: m.monitor.tab == k) {
            m.setMonitor { $0.tab = k }
        })
    }

    /// CORRECTION — сила коррекции профилем, 0…100 %, 2 px на 1 %.
    private func correctionField(_ s: MonitorSettings) -> AnyView {
        let m: AppModel = model
        let t: String = String(format: "%.0f %%", s.strength * 100)
        return AnyView(EqField(label: "CORRECTION", value: t, pxPerUnit: 2,
                               get: { (m.monitor.strength * 100).rounded() },
                               set: { v in m.setMonitor { $0.strength = Swift.max(0, Swift.min(100, v)) / 100 } },
                               double: { m.setMonitor { $0.strength = 1 } }, model: m))
    }

    /// TRIM: 5 полос профиля (100 Гц…8 кГц, Q 1), 0,1 dB на 2 px, ±3 dB.
    static func trimFields(_ m: AppModel) -> [AnyView] {
        let t: [Double] = m.phonesTrim
        var items: [AnyView] = []
        for k in 0..<MonitorSpec.trimHz.count {
            let hz: Double = MonitorSpec.trimHz[k]
            let f: String = hz >= 1000 ? String(format: "%g kHz", hz / 1000) : String(format: "%.0f Hz", hz)
            items.append(AnyView(EqField(label: "TRIM " + f, value: String(format: "%+.1f dB", t[k]), pxPerUnit: 2,
                                         get: { (m.phonesTrim[k] * 10).rounded() },
                                         set: { v in m.setPhonesTrim(k, v / 10) },
                                         double: { m.setPhonesTrim(k, 0) }, model: m)))
        }
        return items
    }

    /// ANGLE Crossfeed, 10…60°, 4 px на градус.
    private func angleField(_ s: MonitorSettings) -> AnyView {
        let m: AppModel = model
        let t: String = String(format: "%.0f°", s.angle)
        return AnyView(EqField(label: "ANGLE", value: t, pxPerUnit: 4,
                               get: { m.monitor.angle.rounded() },
                               set: { v in m.setMonitor { $0.angle = Swift.max(MonitorSpec.angleMin, Swift.min(MonitorSpec.angleMax, v)) } },
                               double: { m.setMonitor { $0.angle = MonitorSpec.angleDef } }, model: m))
    }

    /// AMOUNT Crossfeed, 0…100 %, 2 px на 1 %.
    private func amountField(_ s: MonitorSettings) -> AnyView {
        let m: AppModel = model
        let t: String = String(format: "%.0f %%", s.amount * 100)
        return AnyView(EqField(label: "AMOUNT", value: t, pxPerUnit: 2,
                               get: { (m.monitor.amount * 100).rounded() },
                               set: { v in m.setMonitor { $0.amount = Swift.max(0, Swift.min(100, v)) / 100 } },
                               double: { m.setMonitor { $0.amount = MonitorSpec.amountDef } }, model: m))
    }

    /// TRANSLATION: палец вниз — следующий пресет, тап — меню пресетов.
    private var translationField: some View {
        let m: AppModel = model
        let names: [String] = m.translations.map { $0.name }
        let cur: String = names.contains(m.monitor.translation) ? m.monitor.translation : (names.first ?? "Off")
        return EqField(label: "TRANSLATION", value: cur, pxPerUnit: 30,
                       get: { -Double(names.firstIndex(of: m.monitor.translation) ?? 0) },
                       set: { v in
                           let n: Int = names.count
                           if n == 0 { return }
                           let i: Int = ((-Int(v)) % n + n) % n
                           m.setMonitor { $0.translation = names[i] }
                       },
                       tap: { f in m.translationMenu = m.translationMenu == nil ? f : nil }, model: m)
    }

    /// LEVEL: компенсация громкости цепочки (только показ).
    private var levelLabel: some View {
        let v: Double = model.monitorComp
        let t: String = abs(v) < 0.05 ? "0.0 dB" : String(format: "%+.1f dB", v)
        return VStack(alignment: .leading, spacing: 0) {
            Text("LEVEL").font(.system(size: 9)).tracking(0.8).foregroundStyle(theme.dim)
            Text(t).font(.system(size: 16)).lineLimit(1).minimumScaleFactor(0.7).foregroundStyle(theme.text)
        }
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }
}

/// Строка из имени (под именем канала EQ) и равных столбцов.
struct MonitorRow: View {
    let name: String
    let items: [AnyView]
    let height: CGFloat
    @Environment(\.theme) private var theme

    var body: some View {
        HStack(spacing: Layout.gap) {
            Text(name).font(.system(size: 11)).tracking(0.9).lineLimit(1).minimumScaleFactor(0.6)
                .foregroundStyle(theme.dim)
                .frame(width: EqBar.nameWidth)
            ForEach(items.indices, id: \.self) { i in
                items[i].frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .frame(height: height)
    }
}

/// Меню TRANSLATION: пресеты одним столбцом под полем (выбранный горит); тап мимо — закрыть.
struct TranslationMenu: View {
    static let width: CGFloat = 220
    let model: AppModel
    let anchor: CGRect
    @Environment(\.theme) private var theme

    var body: some View {
        let m: AppModel = model
        let cur: String = m.translationPreset?.name ?? (m.translations.contains { $0.name == m.monitor.translation } ? m.monitor.translation : "Off")
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { m.translationMenu = nil }
            VStack(alignment: .leading, spacing: 6) {
                Text("TRANSLATION").font(.system(size: 12, weight: .bold)).tracking(1.2).foregroundStyle(theme.text)
                ForEach(m.translations.indices, id: \.self) { i in
                    let name: String = m.translations[i].name
                    MenuItem(title: name.uppercased(), current: name == cur) {
                        m.setMonitor { $0.translation = name }
                        m.translationMenu = nil
                    }
                    .frame(height: 40)
                }
            }
            .padding(8)
            .frame(width: TranslationMenu.width)
            .modifier(MenuBox())
            .offset(x: anchor.minX, y: anchor.maxY + 4)
        }
    }
}
