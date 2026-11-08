import SwiftUI

/// Строка Headphone Monitor под строкой EQ окна коррекции — проверки и эмуляция прослушивания: TRANSLATION, MONO,
/// SUB, затем (справа, над значком колонок) ROOM, AMBIENCE, ANGLE и AMOUNT (Crossfeed; при комнате — серые, «ROOM»).
/// Строка EQ — коррекция наушников: кривая (PHONE | CORRECT), CORRECTION, LEVEL, PRESETS, BYPASS. Поля — как у EQ:
/// палец вверх-вниз, двойной тап — значение по умолчанию.
struct MonitorBar: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let s: MonitorSettings = m.monitor
        let items: [AnyView] = [
            MonitorBar.field(m, 0),
            AnyView(EqTool(title: "MONO", enabled: true, active: s.mono) { m.setMonitor { $0.mono.toggle() } }),
            AnyView(EqTool(title: "SUB", enabled: true, active: s.sub) { m.setMonitor { $0.sub.toggle() } }),
            MonitorBar.field(m, 4), MonitorBar.field(m, 5), MonitorBar.field(m, 2), MonitorBar.field(m, 3),
        ]
        return MonitorRow(name: "MONITOR", items: items, height: m.barH)
    }

    /// Поле монитора k (AppModel.monitorField): одни замыкания на все поля (объём сборки).
    static func field(_ m: AppModel, _ k: Int) -> AnyView {
        let f: MonitorFieldInfo = m.monitorField(k)
        return AnyView(EqField(label: f.label, value: f.value, enabled: f.enabled, pxPerUnit: f.px,
                               get: { m.monitorUnits(k) },
                               set: { v in m.setMonitorUnits(k, v) },
                               tap: { r in m.monitorFieldTap(k, r) },
                               double: { m.resetMonitorField(k) }, model: m))
    }
}

/// LEVEL: компенсация громкости цепочки (только показ; в строке EQ окна коррекции).
struct MonitorLevel: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
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

/// Выбор кривой окна коррекции: подпись CURVE и два сегмента PHONE | CORRECT (выбранный горит); правится выбранная.
struct CurveSwitch: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let c: Bool = model.monitor.editCorrect
        return VStack(alignment: .leading, spacing: 2) {
            Text("CURVE").font(.system(size: 9)).tracking(0.8).foregroundStyle(theme.dim).padding(.leading, 12)
            HStack(spacing: 4) {
                segment("PHONE", !c, false)
                segment("CORRECT", c, true)
            }
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 4)
        .modifier(Tile(theme.panel, alignment: .leading))
    }

    private func segment(_ t: String, _ on: Bool, _ correct: Bool) -> some View {
        let m: AppModel = model
        return Text(t).font(.system(size: 12, weight: .bold)).tracking(0.6).lineLimit(1).minimumScaleFactor(0.6)
            .foregroundStyle(on ? theme.onAccent : theme.text)
            .modifier(Tile(on ? theme.accent : theme.panel2))
            .contentShape(Rectangle())
            .onTapGesture { m.setEditCorrect(correct) }
    }
}

/// Меню TRANSLATION или ROOM (monitorMenuRoom): пункты одним столбцом под полем (выбранный горит); тап мимо — закрыть.
struct TranslationMenu: View {
    static let width: CGFloat = 220
    let model: AppModel
    let anchor: CGRect
    @Environment(\.theme) private var theme

    var body: some View {
        let m: AppModel = model
        let room: Bool = m.monitorMenuRoom
        let names: [String] = room ? ["Off"] + m.rooms.map { $0.name } : m.translations.map { $0.name }
        let cur: String = room ? (m.roomOn ? m.monitor.room : "Off") : (m.translationPreset?.name ?? "Off")
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { m.translationMenu = nil }
            VStack(alignment: .leading, spacing: 6) {
                Text(room ? "ROOM" : "TRANSLATION").font(.system(size: 12, weight: .bold)).tracking(1.2)
                    .foregroundStyle(theme.text)
                MenuChoiceColumn(items: names.map { (name: String) -> MenuChoice in
                    MenuChoice(title: name.uppercased(), current: name == cur) {
                        if room { m.setRoom(name) } else { m.setMonitor { $0.translation = name } }
                        m.translationMenu = nil
                    }
                })
            }
            .padding(8)
            .frame(width: TranslationMenu.width)
            .modifier(MenuBox())
            .offset(x: anchor.minX, y: anchor.maxY + 4)
        }
    }
}
