import SwiftUI

/// Окно CHORD (долгое нажатие на CHORD): 6 типов аккорда (выбор сразу, окно остаётся). Как меню бутерброда под
/// CHORD: правее кнопки, снизу вверх, шириной 4 шага; закрывается тапом мимо окна.
struct ChordMenu: View {
    let model: AppModel
    let layout: Layout
    let screen: CGSize
    @Environment(\.theme) private var theme

    var body: some View {
        let width: CGFloat = 4 * layout.step + 3 * Layout.stepGap
        // Левый нижний угол меню — у левого нижнего угла первой клавиши.
        let keys: CGRect = model.keysFrame
        let x: CGFloat = keys.width > 0 ? keys.minX : 12 + layout.step + Layout.stepGap
        let bottom: CGFloat = keys.height > 0 ? max(0, screen.height - keys.maxY) : 8
        return ZStack(alignment: .bottomLeading) {
            Color.black.opacity(0.001).ignoresSafeArea().onTapGesture { model.chordMenuOpen = false }
            types
                .padding(10)
                .frame(width: width)
                .background(theme.bg, in: RoundedRectangle(cornerRadius: Layout.radius))
                .overlay(RoundedRectangle(cornerRadius: Layout.radius).stroke(theme.line, lineWidth: 1))
                .shadow(color: .black.opacity(0.5), radius: 12, y: 4)
                .padding(.leading, x)
                .padding(.bottom, bottom)
        }
        .frame(width: screen.width, height: screen.height, alignment: .bottomLeading)
    }

    private var types: some View {
        let cols: [GridItem] = Array(repeating: GridItem(.flexible(), spacing: 6), count: 2)
        let cur: Int = model.chordKind[model.selectedTrack]
        return LazyVGrid(columns: cols, spacing: 6) {
            ForEach(0..<Scales.chordKinds.count, id: \.self) { c in
                InkButton(title: Scales.chordKinds[c], active: c == cur, height: 44) {
                    if model.midiLearn.on { model.learnTap(.button("CHORD TYPE \(c + 1)")) } else { model.setChordKind(c) }
                }
                .midiMarks(model, [.button("CHORD TYPE \(c + 1)")])
            }
        }
    }
}
