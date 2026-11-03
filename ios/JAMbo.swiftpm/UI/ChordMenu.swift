import SwiftUI

/// Окно CHORD (долгое нажатие на CHORD; решения пользователя 3.11): типы аккорда, на ударной дорожке — стили ритма
/// (тап — выбор, окно закрывается), в режиме ARP — направление, RATE и OCTAVES (окно остаётся). Все три — от левого
/// нижнего угла первой клавиши до верха строки дорожек, кнопки одного размера (3 ряда); закрывается тапом мимо.
struct ChordMenu: View {
    let model: AppModel
    let layout: Layout
    let screen: CGSize
    @Environment(\.theme) private var theme

    var body: some View {
        let m: ChordMenuMetrics = ChordMenuMetrics(model: model, layout: layout, screen: screen)
        let arp: Bool = model.arpMode
        let width: CGFloat = arp ? m.arpWidth : m.width
        return ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.chordMenuOpen = false }
            content(m, arp)
                .padding(ChordMenuMetrics.pad)
                .frame(width: width, height: m.height, alignment: .topLeading)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .padding(.leading, m.x)
                .padding(.bottom, m.bottom)
        }
        .frame(width: screen.width, height: screen.height, alignment: .bottomLeading)
    }

    private func content(_ m: ChordMenuMetrics, _ arp: Bool) -> AnyView {
        if arp {
            return AnyView(HStack(alignment: .top, spacing: ChordMenuMetrics.section) {
                ArpWindowColumn(model: model, title: "DIRECTION", m: m, cols: 2, kind: 0)
                ArpWindowColumn(model: model, title: "RATE", m: m, cols: 2, kind: 1)
                ArpWindowColumn(model: model, title: "OCTAVES", m: m, cols: 1, kind: 2)
            })
        }
        let title: String = model.drumTrack ? "STYLE" : "CHORD"
        return AnyView(VStack(alignment: .leading, spacing: ChordMenuMetrics.gap) {
            FieldLabel(title: title).frame(height: ChordMenuMetrics.head, alignment: .bottomLeading)
            types(m.rowH)
        })
    }

    /// Ударная дорожка — стили ритма, иначе — типы аккорда (CHORD TYPE 1…6).
    private func types(_ rowH: CGFloat) -> some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: ChordMenuMetrics.gap), count: 2)
        let names: [String] = model.chordTypeNames
        let cur: Int = model.chordTypeIndex
        return LazyVGrid(columns: cols, spacing: ChordMenuMetrics.gap) {
            ForEach(0..<names.count, id: \.self) { c in
                InkButton(title: names[c], active: c == cur, height: rowH) {
                    if model.midiLearn.on {
                        model.learnTap(.button("CHORD TYPE \(c + 1)"))
                    } else {
                        model.chooseChordType(c)
                        model.chordMenuOpen = false
                    }
                }
                .midiMarks(model, [.button("CHORD TYPE \(c + 1)")])
            }
        }
    }
}

/// Размеры окна CHORD: высота — от низа клавиш до верха строки дорожек; ряд кнопок — треть остатка после подписи.
struct ChordMenuMetrics {
    static let pad: CGFloat = 10
    static let gap: CGFloat = 6
    static let head: CGFloat = 14
    static let section: CGFloat = 14
    let x: CGFloat
    let bottom: CGFloat
    let height: CGFloat
    let rowH: CGFloat
    /// Окно аккордов и стилей (2 столбца) и ширина одного столбца кнопок.
    let width: CGFloat
    let colW: CGFloat
    /// Окно ARP: 5 столбцов (направления 2, RATE 2, OCTAVES 1) с промежутками между разделами.
    let arpWidth: CGFloat

    init(model: AppModel, layout: Layout, screen: CGSize) {
        let keys: CGRect = model.keysFrame
        let tracks: CGRect = model.tracksFrame
        x = keys.width > 0 ? keys.minX : 12 + layout.step + Layout.stepGap
        bottom = keys.height > 0 ? max(0, screen.height - keys.maxY) : 8
        let top: CGFloat = tracks.height > 0 ? tracks.minY : screen.height - 240
        let low: CGFloat = keys.height > 0 ? keys.maxY : screen.height - 8
        height = max(160, low - top)
        let inner: CGFloat = height - 2 * ChordMenuMetrics.pad - ChordMenuMetrics.head - 3 * ChordMenuMetrics.gap
        rowH = max(28, inner / 3)
        let w4: CGFloat = 4 * layout.step + 3 * Layout.stepGap
        width = w4
        colW = (w4 - 2 * ChordMenuMetrics.pad - ChordMenuMetrics.gap) / 2
        let cols: CGFloat = 5 * colW + 2 * ChordMenuMetrics.gap + 2 * ChordMenuMetrics.section
        arpWidth = cols + 2 * ChordMenuMetrics.pad
    }
}

/// Раздел окна ARP: подпись и кнопки столбцами (kind 0 — направления, 1 — RATE, 2 — OCTAVES; окно не закрывается).
struct ArpWindowColumn: View {
    let model: AppModel
    let title: String
    let m: ChordMenuMetrics
    let cols: Int
    let kind: Int

    var body: some View {
        let names: [String] = ArpWindowColumn.names(kind)
        let cur: Int = ArpWindowColumn.current(model.track.arp, kind)
        let grid: [GridItem] = Array(repeating: GridItem(.fixed(m.colW), spacing: ChordMenuMetrics.gap), count: cols)
        let w: CGFloat = CGFloat(cols) * m.colW + CGFloat(cols - 1) * ChordMenuMetrics.gap
        return VStack(alignment: .leading, spacing: ChordMenuMetrics.gap) {
            FieldLabel(title: title).frame(height: ChordMenuMetrics.head, alignment: .bottomLeading)
            LazyVGrid(columns: grid, alignment: .leading, spacing: ChordMenuMetrics.gap) {
                ForEach(0..<names.count, id: \.self) { i in
                    button(names, i, cur)
                }
            }
        }
        .frame(width: w, alignment: .topLeading)
    }

    private func button(_ names: [String], _ i: Int, _ cur: Int) -> AnyView {
        if kind == 0 {
            return AnyView(InkButton(title: names[i], active: i == cur, height: m.rowH) {
                if model.midiLearn.on { model.learnTap(.button("CHORD TYPE \(i + 1)")) } else { model.setArpDir(i) }
            }
            .midiMarks(model, [.button("CHORD TYPE \(i + 1)")]))
        }
        return AnyView(InkButton(title: names[i], active: i == cur, height: m.rowH) {
            if kind == 1 { model.setArpRate(i) } else { model.setArpOctaves(i + 1) }
        })
    }

    static func names(_ kind: Int) -> [String] {
        if kind == 0 { return Arp.dirs }
        if kind == 1 { return Arp.rates }
        return (1...Arp.maxOctaves).map { "\($0)" }
    }

    static func current(_ a: TrackArp, _ kind: Int) -> Int {
        if kind == 0 { return a.dir }
        if kind == 1 { return a.rate }
        return a.octaves - 1
    }
}
