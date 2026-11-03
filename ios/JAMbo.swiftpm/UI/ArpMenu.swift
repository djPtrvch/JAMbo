import SwiftUI

/// Раздел ARP в меню под CHORD (не на ударной дорожке): GATE; OCTAVES, RATE и LATCH — в окне CHORD в режиме ARP.
/// Настройки дорожки — в проекте, без записи UNDO (как ход игры).
struct ArpMenuSection: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            MenuHead(title: "ARP")
            ArpGateSlider(model: model)
        }
    }
}

/// GATE арпеджио: ползунок 10–100 %, палец вбок; двойной тап — 50 %.
struct ArpGateSlider: View {
    let model: AppModel
    @Environment(\.theme) private var theme

    var body: some View {
        let g: Double = model.track.arp.gate
        let pct: Int = Int((g * 100).rounded())
        let n: Double = (g - Arp.gateMin) / (1 - Arp.gateMin)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("GATE").font(.system(size: 13, weight: .bold)).foregroundStyle(theme.text)
                Spacer()
                Text("\(pct)%").font(.system(size: 13, weight: .bold)).monospacedDigit().foregroundStyle(theme.text)
            }
            GeometryReader { geo in
                bar(geo.size.width, n)
                    .contentShape(Rectangle())
                    .gesture(drag(geo.size.width))
                    // Двойной тап — значение по умолчанию (50 %).
                    .simultaneousGesture(TapGesture(count: 2).onEnded { model.setArpGate(TrackArp().gate) })
            }
            .frame(height: 24)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 6)
    }

    private func bar(_ w: CGFloat, _ n: Double) -> some View {
        let x: CGFloat = w * CGFloat(n)
        return ZStack(alignment: .leading) {
            Capsule().fill(theme.meterTrack).frame(height: 6)
            Capsule().fill(theme.accent).frame(width: max(6, x), height: 6)
            Circle().fill(Color.white).frame(width: 22, height: 22)
                .shadow(color: .black.opacity(0.3), radius: 2, y: 1)
                .offset(x: min(max(0, x - 11), w - 22))
        }
        .frame(maxHeight: .infinity)
    }

    private func drag(_ w: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { v in
                let n: Double = Double(min(max(0, v.location.x / max(1, w)), 1))
                let g: Double = Arp.gateMin + n * (1 - Arp.gateMin)
                model.setArpGate((g * 100).rounded() / 100)
            }
    }
}
