import SwiftUI

/// Раскладка ячейки MIX: слева метр, ручка громкости, справа столбик M, S, ● (как в вебе).
enum MixLayout {
    static let meterW: CGFloat = 21
    static let buttonW: CGFloat = 26
    static let label: CGFloat = 17

    static func cell(_ size: CGSize) -> CGSize {
        let s: CGFloat = KnobGrid.spacing
        return CGSize(width: (size.width - 3 * s) / 4, height: (size.height - 3 * s) / 4)
    }

    /// Кнопки M, S, ● в координатах ячейки.
    static func buttons(_ cell: CGSize) -> [CGRect] {
        let knobH: CGFloat = cell.height - label
        let bh: CGFloat = max(14, min(26, (knobH - 8) / 3))
        let total: CGFloat = 3 * bh + 8
        let y0: CGFloat = knobH / 2 - total / 2 + 2
        let x: CGFloat = cell.width - buttonW - 2
        return (0..<3).map { k in CGRect(x: x, y: y0 + CGFloat(k) * (bh + 4), width: buttonW, height: bh) }
    }

    /// Кнопка под пальцем (0 — M, 1 — S, 2 — ●) или nil; p — в координатах сетки.
    static func button(at p: CGPoint, slot: Int, size: CGSize) -> Int? {
        let c = cell(size)
        let s: CGFloat = KnobGrid.spacing
        let ox: CGFloat = CGFloat(slot % 4) * (c.width + s)
        let oy: CGFloat = CGFloat(slot / 4) * (c.height + s)
        let local = CGPoint(x: p.x - ox, y: p.y - oy)
        for (k, r) in buttons(c).enumerated() where r.insetBy(dx: -4, dy: -2).contains(local) { return k }
        return nil
    }
}

/// Ячейка MIX: метр дорожки, ручка громкости (подпись — имя дорожки), кнопки M, S, ●.
/// Дизайн кнопок — как REC: окантовка цветом (M и ● — красная, S — жёлтая), включена — горит этим цветом.
struct MixCell: View {
    let model: AppModel
    let slot: Int
    @Environment(\.theme) private var theme

    var body: some View {
        GeometryReader { geo in
            let exists: Bool = slot < model.project.tracks.count
            let frames: [CGRect] = MixLayout.buttons(geo.size)
            ZStack(alignment: .topLeading) {
                KnobView(state: model.knobState(slot))
                    .padding(.leading, MixLayout.meterW + 4)
                    .padding(.trailing, MixLayout.buttonW + 6)
                if exists {
                    meter(geo.size)
                    buttons(frames)
                }
            }
        }
    }

    /// Метр дорожки (как в вебе): после громкости, стерео — две полосы, моно — одна (у ручки); выше 0 dB — красная,
    /// заглушённая — серая, приглушение Sidechain — оранжевым сверху (24 dB — вся высота), пик-холд; без чисел.
    private func meter(_ size: CGSize) -> some View {
        let h: CGFloat = (size.height - MixLayout.label) * 0.8
        let t: Int = slot
        let stereo: Bool = model.trackStereo(t)
        let muted: Bool = !model.project.audible(t)
        // Значения кадра — параметрами вида (с временем кадра): иначе SwiftUI не перерисовывает Canvas.
        return TimelineView(.animation(minimumInterval: 1.0 / 60)) { tl in
            MixMeter(bars: model.meters.bars(t, stereo: stereo), duckDb: model.meters.duckDb(t), muted: muted,
                     now: tl.date)
        }
        .frame(width: MixLayout.meterW, height: h)
        .offset(x: 2, y: (size.height - MixLayout.label - h) / 2)
        .allowsHitTesting(false)
    }

    private func buttons(_ frames: [CGRect]) -> some View {
        let t: Track = model.project.tracks[slot]
        return ZStack(alignment: .topLeading) {
            small("M", on: t.mute, color: theme.rec, frame: frames[0])
            small("S", on: t.solo, color: theme.accent, frame: frames[1])
            dot(frames[2], on: model.stemLit(slot))
            if model.midiLearn.on {
                MidiSmallMark(model: model, target: .button("MUTE \(slot + 1)"), frame: frames[0])
                MidiSmallMark(model: model, target: .button("SOLO \(slot + 1)"), frame: frames[1])
                MidiSmallMark(model: model, target: .button("ARM \(slot + 1)"), frame: frames[2])
            }
        }
    }

    private func small(_ title: String, on: Bool, color: Color, frame r: CGRect) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .bold))
            .foregroundStyle(on ? theme.onAccent : color)
            .frame(width: r.width, height: r.height)
            .background(on ? color : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: 1))
            .offset(x: r.minX, y: r.minY)
    }

    /// ● — запись стема (S11d): горит красным, пока дорожка готова к записи или пишется.
    private func dot(_ r: CGRect, on: Bool) -> some View {
        Circle().fill(on ? Color.white : theme.rec).frame(width: 8, height: 8)
            .frame(width: r.width, height: r.height)
            .background(on ? theme.rec : Color.clear, in: RoundedRectangle(cornerRadius: 5))
            .overlay(RoundedRectangle(cornerRadius: 5).stroke(theme.rec, lineWidth: 1))
            .offset(x: r.minX, y: r.minY)
    }
}

/// Меню дорожки у ручки громкости (MIX): COPY, PASTE, DELETE TRACK, RENAME; у серой ручки — ADD TRACK.
/// RENAME — поле ввода имени на месте подписи под ручкой.
struct TrackMenus: View {
    let model: AppModel
    let size: CGSize
    @State private var name: String = ""
    @FocusState private var focused: Bool
    @Environment(\.theme) private var theme

    var body: some View {
        ZStack(alignment: .topLeading) {
            if let m = model.trackMenu {
                Color.black.opacity(0.001)
                    .frame(width: size.width, height: size.height)
                    .onTapGesture { model.trackMenu = nil }
                menu(m).offset(menuOffset(m.slot))
            }
            if let k = model.renaming, k < model.project.tracks.count {
                renameField(k)
            }
        }
    }

    private func menu(_ m: TrackMenuState) -> some View {
        VStack(spacing: 6) {
            if m.add {
                MenuItem(title: "ADD TRACK") { run { model.addTrack() } }
            } else {
                MenuItem(title: "COPY") { run { model.copyTrack(m.slot) } }
                MenuItem(title: "PASTE", enabled: model.hasTrackClip) { run { model.pasteTrack(m.slot) } }
                MenuItem(title: "DELETE TRACK", enabled: model.project.canDeleteTrack(m.slot), red: true) {
                    run { model.deleteTrack(m.slot) }
                }
                MenuItem(title: "RENAME") {
                    run {
                        name = model.project.tracks[m.slot].name
                        model.renaming = m.slot
                        focused = true
                    }
                }
            }
        }
        .frame(width: 180)
        .modifier(MenuPanel())
    }

    private func menuOffset(_ slot: Int) -> CGSize {
        let c = KnobGrid.center(slot, size)
        let rows: CGFloat = model.trackMenu?.add == true ? 1 : 4
        let h: CGFloat = rows * 46 + 10
        let x: CGFloat = min(max(0, c.x - 98), size.width - 196)
        let cellH: CGFloat = MixLayout.cell(size).height
        let below: CGFloat = c.y + cellH / 2
        let y: CGFloat = below + h < size.height ? below : max(0, c.y - cellH / 2 - h)
        return CGSize(width: x, height: y)
    }

    private func renameField(_ k: Int) -> some View {
        let c = KnobGrid.center(k, size)
        let cell = MixLayout.cell(size)
        return TextField("", text: $name)
            .font(.system(size: 13))
            .multilineTextAlignment(.center)
            .focused($focused)
            .submitLabel(.done)
            .tint(theme.text)
            .padding(.horizontal, 6)
            .frame(width: cell.width - 20, height: 26)
            .background(theme.bg, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).stroke(theme.text, lineWidth: 1))
            .position(x: c.x, y: c.y + cell.height / 2 - 10)
            .onChange(of: name) { _, v in if v.count > 12 { name = String(v.prefix(12)) } }
            .onAppear { focused = true }
            .onSubmit { finish(k) }
            .onChange(of: focused) { _, f in if !f { finish(k) } }
    }

    private func finish(_ k: Int) {
        guard model.renaming == k else { return }
        model.renaming = nil
        model.renameTrack(k, name)
    }

    private func run(_ f: () -> Void) {
        model.trackMenu = nil
        f()
    }
}

/// Метр ячейки MIX: полосы у ручки (справа), приглушение Sidechain от −0,1 dB (24 dB — вся высота).
struct MixMeter: View {
    let bars: [(level: Float, hold: Float)]
    let duckDb: Float
    let muted: Bool
    let now: Date
    @Environment(\.theme) private var theme

    var body: some View {
        Canvas { ctx, sz in
            let w: CGFloat = MeterBars.span(bars.count)
            let gr: CGFloat = duckDb <= -0.1 ? CGFloat(-duckDb / 24) : 0
            MeterBars.draw(ctx, CGRect(x: sz.width - w, y: 0, width: w, height: sz.height), bars, theme: theme,
                           muted: muted, gr: gr)
        }
    }
}
