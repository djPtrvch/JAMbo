import SwiftUI

/// Строки Headphone Monitor в окне коррекции наушников (под строкой EQ): MONITOR — STRENGTH, ANGLE и AMOUNT
/// (Crossfeed), TRANSLATION, MONO, SUB, TRIM (раскрыть строку TRIM), LEVEL (компенсация громкости, только показ);
/// TRIM — 5 полос ±3 dB профиля. Поля — как у EQ: палец вверх-вниз, двойной тап — значение по умолчанию.
struct MonitorBar: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let m: AppModel = model
        let s: MonitorSettings = m.monitor
        let items: [AnyView] = [
            strengthField(s), angleField(s), amountField(s), AnyView(translationField),
            AnyView(EqTool(title: "MONO", enabled: true, active: s.mono) { m.setMonitor { $0.mono.toggle() } }),
            AnyView(EqTool(title: "SUB", enabled: true, active: s.sub) { m.setMonitor { $0.sub.toggle() } }),
            AnyView(EqTool(title: "TRIM", enabled: true, active: s.trimOpen) { m.setMonitor { $0.trimOpen.toggle() } }),
            AnyView(levelLabel),
        ]
        return MonitorRow(name: "MONITOR", items: items, height: m.barH)
    }

    /// STRENGTH коррекции, 0…100 %, 2 px на 1 %.
    private func strengthField(_ s: MonitorSettings) -> AnyView {
        let m: AppModel = model
        let t: String = String(format: "%.0f %%", s.strength * 100)
        return AnyView(EqField(label: "STRENGTH", value: t, pxPerUnit: 2,
                               get: { (m.monitor.strength * 100).rounded() },
                               set: { v in m.setMonitor { $0.strength = Swift.max(0, Swift.min(100, v)) / 100 } },
                               double: { m.setMonitor { $0.strength = 1 } }, model: m))
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

    /// TRANSLATION: палец вниз — следующий пресет, тап — следующий.
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
                       tap: { _ in m.stepTranslation(1) }, model: m)
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

/// Строка TRIM: 5 полос профиля (100 Гц…8 кГц, Q 1), 0,1 dB на 2 px, ±3 dB.
struct MonitorTrimBar: View {
    let model: AppModel

    var body: some View {
        let m: AppModel = model
        let t: [Double] = m.phonesTrim
        var items: [AnyView] = []
        for k in 0..<MonitorSpec.trimHz.count {
            let hz: Double = MonitorSpec.trimHz[k]
            let label: String = hz >= 1000 ? String(format: "%g kHz", hz / 1000) : String(format: "%.0f Hz", hz)
            items.append(AnyView(EqField(label: label, value: String(format: "%+.1f dB", t[k]), pxPerUnit: 2,
                                         get: { (m.phonesTrim[k] * 10).rounded() },
                                         set: { v in m.setPhonesTrim(k, v / 10) },
                                         double: { m.setPhonesTrim(k, 0) }, model: m)))
        }
        for _ in 0..<3 { items.append(AnyView(Color.clear)) }
        return MonitorRow(name: "TRIM", items: items, height: m.barH)
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
