import SwiftUI

/// Строка Headphone Monitor под строкой EQ окна коррекции — где и на чём звучит: SPACE (пункт TRANSLATION — тембр и пространство
/// пункта; удержание пункта в меню — сохранить профиль), AMBIENCE (сколько пространства; у пунктов без него — серое), HEAD
/// (уши: та же комната с разными головами, 15.11; меню по тапу; одна голова — серое), EAR TONE
/// (окраска уха в прямом звуке), проверки MONO и SUB, HEAD TRACK (отслеживание головы).
/// Строка EQ — коррекция наушников: PHONE CURVE, CORRECT CURVE, CORRECTION, LEVEL, PRESETS, BYPASS (на две строки —
/// MonitorBypass; справа в строке монитора под него место; зазор EAR TONE | MONO — под чертой PHONE | CORRECT).
/// Поля — как у EQ:
/// палец вверх-вниз, двойной тап — значение по умолчанию.
struct MonitorBar: View {
    let model: AppModel
    /// Ширина и левый край строки («root») — места полей считаются от столбцов строки EQ (EqBar.slots).
    @State private var width: CGFloat = 0
    @State private var barX: CGFloat = 0

    var body: some View {
        let m: AppModel = model
        let s: MonitorSettings = m.monitor
        let items: [AnyView] = [
            MonitorBar.field(m, 0), MonitorBar.field(m, 5), MonitorBar.field(m, 7), MonitorBar.field(m, 6),
            AnyView(EqTool(title: "MONO", enabled: true, active: s.mono) { m.setMonitor { $0.mono.toggle() } }),
            AnyView(EqTool(title: "SUB", enabled: true, active: s.sub) { m.setMonitor { $0.sub.toggle() } }),
            AnyView(HeadButton(model: m)),
        ]
        let slots: [EqSlot] = MonitorBar.slots(width: width, barX: barX, top: m.topFrames)
        return ZStack(alignment: .topLeading) {
            ForEach(items.indices, id: \.self) { i in
                items[i].frame(width: slots[i].w, height: m.barH).offset(x: slots[i].x)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .frame(height: m.barH)
        .onGeometryChange(for: CGRect.self) { $0.frame(in: .named("root")) } action: { r in
            width = r.width
            barX = r.minX
        }
    }

    /// Места полей (15.11, решение пользователя): SPACE, AMBIENCE, HEAD, EAR TONE — поровну от края имени до черты
    /// между PHONE CURVE и CORRECT CURVE строки EQ; MONO, SUB, HEAD TRACK — поровну от неё до BYPASS (он на две строки).
    static func slots(width: CGFloat, barX: CGFloat, top: TopFrames) -> [EqSlot] {
        let g: CGFloat = Layout.gap
        let eq: [EqSlot] = EqBar.slots(width: width, barX: barX, top: top, phones: true)
        let x0: CGFloat = EqBar.nameWidth + g
        let split: CGFloat = eq[4].x + eq[4].w / 2
        let end: CGFloat = eq[EqBar.columns - 1].x - g
        return MonitorBar.row(x0, split - g / 2, 4) + MonitorBar.row(split + g / 2, end, 3)
    }

    /// n равных мест с зазорами между a и b.
    static func row(_ a: CGFloat, _ b: CGFloat, _ n: Int) -> [EqSlot] {
        let g: CGFloat = Layout.gap
        let w: CGFloat = max(0, (b - a - CGFloat(n - 1) * g) / CGFloat(n))
        return (0..<n).map { EqSlot(x: a + CGFloat($0) * (w + g), w: w) }
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

/// HEAD TRACK: отслеживание головы камерой — горит жёлтым, пока лицо видно; включён, а лица нет — серое с точкой (•); без
/// пространства или камеры — серая надпись. Тап — вкл./выкл., SHIFT + тап — CENTER.
struct HeadButton: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let enabled: Bool = m.headEnabled
        let lit: Bool = enabled && m.headOn && m.headFace
        let lost: Bool = enabled && m.headOn && !m.headFace
        let fg: Color = !enabled ? theme.off : (lit ? theme.onAccent : theme.text)
        return Text(lost ? "HEAD TRACK •" : "HEAD TRACK").font(.system(size: 12, weight: .bold)).tracking(0.8)
            .lineLimit(1).minimumScaleFactor(0.5)
            .foregroundStyle(fg)
        .tile(lit ? theme.accent : theme.panel2)
        .contentShape(Rectangle())
        .onTapGesture { m.headTap() }
    }
}

/// BYPASS окна коррекции (15.11, решение пользователя): одна высокая кнопка на строки EQ и MONITOR из двух половин —
/// верх выключает коррекцию наушников (PHONE CURVE и CORRECT CURVE), низ — пространство (SPACE); горит — в обходе;
/// обе — вся цепочка в обход.
struct MonitorBypass: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        return VStack(spacing: 0) {
            half("BYPASS\nPHONES", m.bypassCorrShown, true)
            Rectangle().fill(theme.line).frame(height: 1)
            half("BYPASS\nSPACE", m.bypassSpaceShown, false)
        }
        .background(theme.panel2)
        .clipShape(RoundedRectangle(cornerRadius: Layout.radius))
    }

    private func half(_ t: String, _ on: Bool, _ top: Bool) -> some View {
        let m: AppModel = model
        return Text(t).font(.system(size: 12, weight: .bold)).tracking(0.8).multilineTextAlignment(.center)
            .lineLimit(2).minimumScaleFactor(0.6)
            .foregroundStyle(on ? theme.onAccent : theme.text)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(on ? theme.accent : Color.clear)
            .contentShape(Rectangle())
            .onTapGesture { m.toggleMonitorBypass(top: top) }
    }
}

/// Пункт меню SPACE: тап — выбрать и закрыть меню, удержание 0,6 с — сохранить профиль. heads — пункт меню HEAD
/// (голова: тап — выбрать, без профиля).
struct SpaceItem: View {
    let model: AppModel
    let name: String
    let current: Bool
    var heads: Bool = false

    var body: some View {
        let m: AppModel = model
        let n: String = name
        let hd: Bool = heads
        let saved: Bool = !hd && m.spaceSaved == n
        let has: Bool = !hd && m.monitor.spaces[n] != nil
        let fg: Color = current ? theme.onAccent : theme.text
        let title: String = saved ? "SAVED" : (has ? n.uppercased() + " •" : n.uppercased())
        return Text(title).font(.system(size: 13, weight: .bold)).lineLimit(1).minimumScaleFactor(0.7)
        .foregroundStyle(fg)
        .frame(maxWidth: .infinity, minHeight: 40)
        .background(current || saved ? theme.accent : theme.panel, in: RoundedRectangle(cornerRadius: 8))
        .contentShape(Rectangle())
        .onTapGesture {
            if hd { m.setHead(n) } else { m.setTranslation(n) }
            m.translationMenu = nil
        }
        .onLongPressGesture(minimumDuration: 0.6) { if !hd { m.saveSpace(n) } }
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

/// Меню SPACE (пункты TRANSLATION): пункты одним столбцом под полем (Off — первым, выбранный горит); тап — выбрать
/// (с профилем пункта), удержание — сохранить в пункт текущие AMBIENCE, EAR TONE, CORRECTION и CORRECT CURVE (на секунду
/// SAVED; у пункта с профилем — точка •); тап мимо — закрыть. То же меню — HEAD: головы пространства, последним — IMPORT…
/// (пакет голов .zip); свайп влево по голове из пакета — корзина.
struct TranslationMenu: View {
    static let width: CGFloat = 220
    static let scrollHeight: CGFloat = 280
    let model: AppModel
    let anchor: CGRect

    var body: some View {
        let m: AppModel = model
        let hd: Bool = m.translationMenuHeads
        let names: [String] = hd ? m.roomHeads : m.translations.map { $0.name }
        let cur: String = hd ? (m.roomInfo?.headName ?? "") : (m.translationPreset?.name ?? "Off")
        return ZStack(alignment: .topLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { m.translationMenu = nil }
            VStack(alignment: .leading, spacing: 6) {
                Text(hd ? "HEAD" : "SPACE").font(.system(size: 12, weight: .bold)).tracking(1.2)
                    .foregroundStyle(theme.text)
                Text(hd ? "SWIPE IMPORTED LEFT TO DELETE" : "HOLD TO SAVE").font(.system(size: 9)).foregroundStyle(theme.dim)
                // Много голов (пакеты) — список прокручивается, низ меню — над кнопками дорожек.
                if names.count > 5 {
                    MenuScroll { items(m, names, cur, hd) }.frame(height: TranslationMenu.scrollHeight)
                } else {
                    items(m, names, cur, hd)
                }
            }
            .padding(8)
            .frame(width: TranslationMenu.width)
            .menuBox()
            .offset(x: anchor.minX, y: anchor.maxY + 4)
        }
    }

    /// Пункты: SPACE — SpaceItem; HEAD — головы сборки SpaceItem, из пакетов — SwipeRow (свайп влево — корзина), последним
    /// — IMPORT….
    private func items(_ m: AppModel, _ names: [String], _ cur: String, _ hd: Bool) -> some View {
        VStack(spacing: 6) {
            ForEach(names.indices, id: \.self) { i in
                let n: String = names[i]
                if hd && m.headImported(n) {
                    SwipeRow(title: n, current: n == cur, height: 40, tap: {
                        m.setHead(n)
                        m.translationMenu = nil
                    }, delete: { m.deleteHead(n) })
                } else {
                    SpaceItem(model: m, name: n, current: n == cur, heads: hd)
                }
            }
            if hd {
                Text("IMPORT…").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                    .frame(maxWidth: .infinity, minHeight: 40)
                    .background(theme.panel2, in: RoundedRectangle(cornerRadius: 8))
                    .contentShape(Rectangle())
                    .onTapGesture { m.chooseHeadFiles() }
            }
        }
    }
}
