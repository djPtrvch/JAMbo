import SwiftUI

/// Строка Headphone Monitor в окне коррекции наушников (под строкой EQ): TRANSLATION (меню профилей прослушивания),
/// CORRECTION (сила коррекции профилем наушников), ANGLE и AMOUNT (Crossfeed), MONO, SUB (проверки). Поля — как у EQ:
/// палец вверх-вниз, двойной тап — значение по умолчанию. В строке EQ (на месте M/S, DYN, LISTEN) — PHONE CURVE и
/// CORRECT CURVE (какую кривую править) и LEVEL.
struct MonitorBar: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let m: AppModel = model
        let s: MonitorSettings = m.monitor
        let items: [AnyView] = [
            AnyView(translationField), correctionField(s), angleField(s), amountField(s),
            AnyView(EqTool(title: "MONO", enabled: true, active: s.mono) { m.setMonitor { $0.mono.toggle() } }),
            AnyView(EqTool(title: "SUB", enabled: true, active: s.sub) { m.setMonitor { $0.sub.toggle() } }),
        ]
        return MonitorRow(name: "MONITOR", items: items, height: m.barH)
    }

    /// PHONE CURVE / CORRECT CURVE в строке EQ: выбранная горит.
    static func curveButton(_ m: AppModel, _ correct: Bool) -> AnyView {
        return AnyView(EqTool(title: correct ? "CORRECT CURVE" : "PHONE CURVE", enabled: true,
                              active: m.monitor.editCorrect == correct) { m.setEditCorrect(correct) })
    }

    /// CORRECTION — сила коррекции профилем наушников, 0…100 %, 2 px на 1 %.
    private func correctionField(_ s: MonitorSettings) -> AnyView {
        let m: AppModel = model
        let t: String = String(format: "%.0f %%", s.strength * 100)
        return AnyView(EqField(label: "CORRECTION", value: t, pxPerUnit: 2,
                               get: { (m.monitor.strength * 100).rounded() },
                               set: { v in m.setMonitor { $0.strength = Swift.max(0, Swift.min(100, v)) / 100 } },
                               double: { m.setMonitor { $0.strength = 1 } }, model: m))
    }

    /// ANGLE Crossfeed, 10…60°, 4 px на градус.
    private func angleField(_ s: MonitorSettings) -> AnyView {
        let m: AppModel = model
        let t: String = String(format: "%.0f°", s.angle)
        // Room включена — Crossfeed заменён комнатой (связь каналов — в её импульсах).
        return AnyView(EqField(label: "ANGLE", value: t, enabled: !m.roomOn, pxPerUnit: 4,
                               get: { m.monitor.angle.rounded() },
                               set: { v in m.setMonitor { $0.angle = Swift.max(MonitorSpec.angleMin, Swift.min(MonitorSpec.angleMax, v)) } },
                               double: { m.setMonitor { $0.angle = MonitorSpec.angleDef } }, model: m))
    }

    /// AMOUNT Crossfeed, 0…100 %, 2 px на 1 %.
    private func amountField(_ s: MonitorSettings) -> AnyView {
        let m: AppModel = model
        let t: String = String(format: "%.0f %%", s.amount * 100)
        return AnyView(EqField(label: "AMOUNT", value: t, enabled: !m.roomOn, pxPerUnit: 2,
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
                       tap: { f in
                           m.monitorMenuRoom = false
                           m.translationMenu = m.translationMenu == nil ? f : nil
                       }, model: m)
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

/// Строка ROOM (фаза 2): комната (тап — меню, палец вниз — следующая), AMBIENCE (громкость хвоста, −∞…0 dB,
/// 0,5 dB на 2 px, двойной тап — −6 dB) и пояснение: пока комната включена, Crossfeed заменён ею.
struct MonitorRoomBar: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let m: AppModel = model
        let names: [String] = ["Off"] + m.rooms.map { $0.name }
        let cur: String = m.roomOn ? m.monitor.room : "Off"
        let room = EqField(label: "ROOM", value: cur, pxPerUnit: 30,
                           get: { -Double(names.firstIndex(of: m.monitor.room) ?? 0) },
                           set: { v in
                               let n: Int = names.count
                               let i: Int = ((-Int(v)) % n + n) % n
                               if names[i] != m.monitor.room { m.setRoom(names[i]) }
                           },
                           tap: { f in
                               m.monitorMenuRoom = true
                               m.translationMenu = m.translationMenu == nil ? f : nil
                           }, model: m)
        let db: Double = m.monitor.ambienceDb
        let t: String = db <= MonitorSpec.ambienceMin ? "−∞ dB" : String(format: "%.1f dB", db)
        let amb = EqField(label: "AMBIENCE", value: t, enabled: m.roomOn, pxPerUnit: 2,
                          get: { (m.monitor.ambienceDb * 2).rounded() },
                          set: { v in m.setMonitor { $0.ambienceDb = Swift.max(MonitorSpec.ambienceMin, Swift.min(0, v / 2)) } },
                          double: { m.setMonitor { $0.ambienceDb = -6 } }, model: m)
        let note: String = m.roomOn ? "Crossfeed is replaced by the room" : "Room off: crossfeed works"
        let label = Text(note).font(.system(size: 12)).foregroundStyle(theme.dim).lineLimit(2)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading).padding(.horizontal, 12)
        return MonitorRow(name: "ROOM", items: [AnyView(room), AnyView(amb), AnyView(label)], height: m.barH)
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
                ForEach(names.indices, id: \.self) { i in
                    let name: String = names[i]
                    MenuItem(title: name.uppercased(), current: name == cur) {
                        if room { m.setRoom(name) } else { m.setMonitor { $0.translation = name } }
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
