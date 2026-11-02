import SwiftUI

/// Окно CHORD (долгое нажатие на CHORD): TYPE — 6 типов аккорда (выбор сразу, окно остаётся), PROGRESSIONS — пресеты
/// с аккордами для текущей гаммы и корня (тап — 4 аккорда на шаги 1, 5, 9, 13 текущей страницы), CLEAR CHORDS.
/// Правее кнопки CHORD, снизу вверх; закрывается тапом мимо окна.
struct ChordMenu: View {
    let model: AppModel
    let layout: Layout
    let screen: CGSize
    @Environment(\.theme) private var theme

    private static let rowH: CGFloat = 48
    private static let chipH: CGFloat = 40
    /// Высота содержимого: заголовки, 2 ряда типов, 6 пресетов, CLEAR CHORDS и зазоры.
    private static let contentH: CGFloat = 2 * 16 + 2 * chipH + 6 + 6 * rowH + 5 * 4 + chipH + 4 * 8 + 20

    var body: some View {
        let width: CGFloat = 6 * layout.step + 5 * Layout.stepGap
        let x: CGFloat = 12 + layout.step + Layout.stepGap
        let h: CGFloat = min(ChordMenu.contentH, max(200, screen.height - 300))
        return ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.chordMenuOpen = false }
            MenuScroll { content.padding(10) }
                .frame(width: width, height: h)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .padding(.leading, x)
                .padding(.bottom, 8)
        }
        .frame(width: screen.width, height: screen.height, alignment: .bottomLeading)
    }

    private var content: some View {
        VStack(alignment: .leading, spacing: 8) {
            MenuHead(title: "TYPE")
            types
            MenuHead(title: "PROGRESSIONS")
            VStack(spacing: 4) {
                ForEach(0..<Chords.progressions.count, id: \.self) { i in row(Chords.progressions[i]) }
            }
            InkButton(title: "CLEAR CHORDS", height: ChordMenu.chipH) { model.clearProgression() }
        }
    }

    private var types: some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 3)
        let cur: Int = model.chordKind[model.selectedTrack]
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<Scales.chordKinds.count, id: \.self) { c in
                InkButton(title: Scales.chordKinds[c], active: c == cur, height: ChordMenu.chipH) {
                    if model.midiLearn.on { model.learnTap(.button("CHORD TYPE \(c + 1)")) } else { model.setChordKind(c) }
                }
                .midiMarks(model, [.button("CHORD TYPE \(c + 1)")])
            }
        }
    }

    private func row(_ p: ChordProgression) -> some View {
        Button(action: { model.writeProgression(p.degrees) }) {
            HStack(spacing: 8) {
                Text(p.name).font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                Spacer(minLength: 4)
                Text(model.progressionNames(p)).font(.system(size: 12)).foregroundStyle(theme.dim)
                    .lineLimit(1).minimumScaleFactor(0.7)
            }
            .padding(.horizontal, 10)
            .frame(maxWidth: .infinity, minHeight: ChordMenu.rowH)
            .background(theme.panel, in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
