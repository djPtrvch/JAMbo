import SwiftUI

/// Строка Headphone Monitor под строкой EQ окна коррекции — где и на чём звучит: SPACE (пункт TRANSLATION — тембр и пространство
/// пункта), AMBIENCE (сколько пространства; у пунктов без него — серое), проверки MONO и SUB, HEAD TRACK (отслеживание головы).
/// Строка EQ — коррекция наушников: PHONE CURVE, CORRECT CURVE, CORRECTION, LEVEL, PRESETS, BYPASS. Поля — как у EQ:
/// палец вверх-вниз, двойной тап — значение по умолчанию.
struct MonitorBar: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let s: MonitorSettings = m.monitor
        let items: [AnyView] = [
            MonitorBar.field(m, 0), MonitorBar.field(m, 5),
            AnyView(EqTool(title: "MONO", enabled: true, active: s.mono) { m.setMonitor { $0.mono.toggle() } }),
            AnyView(EqTool(title: "SUB", enabled: true, active: s.sub) { m.setMonitor { $0.sub.toggle() } }),
            AnyView(HeadButton(model: m)),
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

/// HEAD TRACK: отслеживание головы камерой — горит жёлтым, пока лицо видно; включён, а лица нет — серое с точкой; без
/// пространства или камеры — серая надпись. Тап — вкл./выкл., SHIFT + тап — CENTER.
struct HeadButton: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let enabled: Bool = m.headEnabled
        let lit: Bool = enabled && m.headOn && m.headFace
        let lost: Bool = enabled && m.headOn && !m.headFace
        let fg: Color = !enabled ? theme.off : (lit ? theme.onAccent : theme.text)
        return HStack(spacing: 5) {
            Text("HEAD\nTRACK").font(.system(size: 11, weight: .bold)).tracking(0.6).multilineTextAlignment(.center)
                .lineLimit(2).minimumScaleFactor(0.6)
            if lost { Circle().fill(theme.accent).frame(width: 6, height: 6) }
        }
        .foregroundStyle(fg)
        .tile(lit ? theme.accent : theme.panel2)
        .contentShape(Rectangle())
        .onTapGesture { m.headTap() }
    }
}

/// LEVEL: компенсация громкости цепочки (только показ; в строке EQ окна коррекции).
struct MonitorLevel: View {
    let model: AppModel

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

/// Выбор кривой окна коррекции: одна кнопка из двух половин — PHONE CURVE | CORRECT CURVE (подписи в две строки,
/// между половинами — черта; выбранная горит); правится выбранная.
struct CurveSwitch: View {
    let model: AppModel

    var body: some View {
        let c: Bool = model.monitor.editCorrect
        return HStack(spacing: 0) {
            half("PHONE\nCURVE", !c, false)
            Rectangle().fill(theme.line).frame(width: 1)
            half("CORRECT\nCURVE", c, true)
        }
        .background(theme.panel2)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func half(_ t: String, _ on: Bool, _ correct: Bool) -> some View {
        let m: AppModel = model
        return Text(t).font(.system(size: 11, weight: .bold)).tracking(0.6).multilineTextAlignment(.center)
            .lineLimit(2).minimumScaleFactor(0.7)
            .foregroundStyle(on ? theme.onAccent : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.accent : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { m.setEditCorrect(correct) }
    }
}

/// Меню SPACE (пункты TRANSLATION): пункты одним столбцом под полем (Off — первым, выбранный горит); тап мимо — закрыть.
struct TranslationMenu: View {
    static let width: CGFloat = 220
    let model: AppModel
    let anchor: CGRect

    var body: some View {
        let m: AppModel = model
        let names: [String] = m.translations.map { $0.name }
        let cur: String = m.translationPreset?.name ?? "Off"
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { m.translationMenu = nil }
            VStack(alignment: .leading, spacing: 6) {
                Text("SPACE").font(.system(size: 12, weight: .bold)).tracking(1.2)
                    .foregroundStyle(theme.text)
                MenuChoiceColumn(items: names.map { (name: String) -> MenuChoice in
                    MenuChoice(title: name.uppercased(), current: name == cur) {
                        m.setTranslation(name)
                        m.translationMenu = nil
                    }
                })
            }
            .padding(8)
            .frame(width: TranslationMenu.width)
            .menuBox()
            .offset(x: anchor.minX, y: anchor.maxY + 4)
        }
    }
}
