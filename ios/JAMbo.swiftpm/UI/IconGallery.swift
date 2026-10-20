import SwiftUI

#if DEBUG
/// ICONS (отладочная сборка): превью-иконки движков 16–24 на четырёх наборах ручек, тёмная и светлая темы рядом —
/// сверка с docs/icons/prototype/engine-previews-prototype.html (кнопка Reset там — первый набор).
struct IconGallery: View {
    /// Набор: ручки 1.1–1.4 и Decay.
    private struct Preset {
        let name: String
        let v: [Double]
    }

    /// Значения по умолчанию прототипа (h, t, m, q, d) по движку.
    private static let defaults: [Int: [Double]] = [
        16: [0.5, 0.5, 0.3, 0.5, 0.5], 17: [0, 0, 0.3, 0.5, 0.5], 18: [0.5, 0.4, 0.5, 0.5, 0.5],
        19: [0.3, 0, 0, 0.35, 0.5], 20: [0.5, 0.5, 0.5, 0.4, 0.5], 21: [0.5, 0.5, 0.5, 0.2, 0.4],
        22: [0.5, 0.6, 0.5, 0.5, 0.5], 23: [0.5, 0.3, 0.3, 0.5, 0.5], 24: [0.5, 0.4, 0.25, 0.2, 0.5],
    ]
    private static let engines: [Int] = [16, 20, 21, 22, 23, 17, 18, 19, 24]

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(IconGallery.engines, id: \.self) { e in
                    HStack(spacing: 16) {
                        Text(SynthEngines.engine(e)?.name ?? "").font(.system(size: 12, weight: .bold)).frame(width: 64, alignment: .leading)
                        strip(e, Theme.dark)
                        strip(e, Theme.light)
                    }
                }
            }
        }
    }

    private func presets(_ e: Int) -> [Preset] {
        return [Preset(name: "default", v: IconGallery.defaults[e] ?? [0.5, 0.5, 0.5, 0.5, 0.5]),
                Preset(name: "0", v: [0, 0, 0, 0, 0]), Preset(name: "1", v: [1, 1, 1, 1, 1]),
                Preset(name: "mix", v: [0.25, 0.75, 0.2, 0.6, 0.3])]
    }

    private func strip(_ e: Int, _ theme: Theme) -> some View {
        HStack(spacing: 6) {
            ForEach(presets(e), id: \.name) { p in
                let v = IconValues(h: p.v[0], t: p.v[1], m: p.v[2], q: p.v[3], d: p.v[4])
                let els: [IconElement] = EngineIcons.elements(e, v)
                Canvas { ctx, size in SynthIcon.draw(ctx, size, els, theme.icon, theme.icon2) }
                    .frame(width: 72, height: 72)
                    .padding(6)
                    .background(theme.panel, in: RoundedRectangle(cornerRadius: 8))
            }
        }
    }
}
#endif
