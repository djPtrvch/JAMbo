import Foundation

// Огибающая голоса синта на кусок (вызов раз на кусок из SynthVoices.renderChunk; цикл по отсчётам — здесь же).

extension SynthVoices {
    /// Огибающая куска в gBuf: атака линейно (с env0 — у моно с текущего уровня), удержание, затем Decay как Release
    /// (τ = Decay/4); · Level · затухание кражи. Голос остановился (stopAt) — дальше нули, возвращает true.
    func envelope(_ v: Int, _ frame0: Int64, _ m: Int, _ lv: Float) -> Bool {
        // Состояние голоса — в локальных переменных на кусок, кадр и время от начала ноты — счётчиками:
        // в отладочной сборке (Playgrounds) преобразования Int64 → Double и обращения к указателям-свойствам
        // на каждом отсчёте заметно дороже самой арифметики.
        let stop = stopAt[v], hold = holdEnd[v], fadeFrom = fadeAt[v], att = attackF[v]
        let keepEnv = keep[v] != 0
        let decaying = selfDecay[v] != 0
        let e0v = env0[v]
        let dk = decayK[v], fadeKV = fadeK[v]
        var envV = env[v], fadeV = fadeG[v], rel = released[v] != 0
        let gb = gBuf
        var frame = frame0
        var tt = Double(frame0 - start[v])
        var j = 0
        var stopped = false
        while j < m {
            if frame >= stop {
                stopped = true
                break
            }
            var g: Float
            if keepEnv {
                // Затухающий сам с короткой атакой: огибающая не обнуляется.
                g = 1
            } else if decaying {
                // Только атака, дальше 1 — затухает сам движок.
                g = tt < att ? Float(tt / att) : 1
            } else if frame >= hold {
                if !rel {
                    rel = true
                    envV = tt < att ? e0v + (1 - e0v) * Float(tt / att) : 1
                }
                envV *= dk
                g = envV
            } else {
                g = tt < att ? e0v + (1 - e0v) * Float(tt / att) : 1
                envV = g
            }
            if frame >= fadeFrom { fadeV *= fadeKV }
            gb[j] = g * lv * fadeV
            frame += 1
            tt += 1
            j += 1
        }
        while j < m {
            gb[j] = 0
            j += 1
        }
        env[v] = envV
        fadeG[v] = fadeV
        released[v] = rel ? 1 : 0
        return stopped
    }
}
