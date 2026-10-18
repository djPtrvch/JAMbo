import Foundation

// Ввод числом в полях окон модулей мастера (удержание поля, как numInputIn веба): текст для окна ввода и разбор
// введённого — «auto» (RELEASE), «off» (BASS, FOCUS, SC HPF), «1.2 s» у времени, «1.5k» у частоты, имя пункта у TYPE;
// значение — в пределах параметра, с его шагом.

public enum MasterInput {
    /// Параметр — время в мс (ATTACK, RELEASE, LOOKAHEAD).
    static func isTime(_ p: ParamDef) -> Bool {
        return p.id.hasSuffix(".attack") || p.id.hasSuffix(".release") || p.id.hasSuffix(".lookahead")
    }

    /// Параметр — частота с OFF у нижнего края (FOCUS, SC HPF) или OFF в начале хода (BASS).
    static func offValue(_ p: ParamDef) -> Double? {
        if p.offBottom != nil { return 0 }
        if p.id == "sat.focus" || p.id == "cmp.schpf" { return p.min }
        return nil
    }

    /// Текст в окне ввода: текущее значение.
    public static func text(_ p: ParamDef, _ v: Double) -> String {
        if !p.options.isEmpty { return p.format(v) }
        if p.autoTop != nil && v >= MasterChain.autoValue { return "auto" }
        if let off = offValue(p), v <= off + 0.5 { return "off" }
        if let st = p.step, st < 0.1 { return String(format: "%.2f", v) }
        if p.step != nil || abs(v) < 10 { return String(format: "%.1f", v) }
        return "\(Int(v.rounded()))"
    }

    /// Разбор введённого; nil — не число (значение не меняется).
    public static func parse(_ p: ParamDef, _ text: String) -> Double? {
        let s: String = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: ".")
        if !p.options.isEmpty {
            if let k = p.options.firstIndex(where: { $0.lowercased() == s }) { return Double(k) }
        }
        if p.autoTop != nil && s.hasPrefix("auto") { return MasterChain.autoValue }
        if let off = offValue(p), s == "off" { return off }
        var digits: String = ""
        var rest: Substring = Substring(s)
        if let c = rest.first, c == "-" || c == "+" {
            digits.append(c)
            rest = rest.dropFirst()
        }
        while let c = rest.first, c.isNumber || c == "." {
            digits.append(c)
            rest = rest.dropFirst()
        }
        guard var v = Double(digits) else { return nil }
        let unit: String = rest.trimmingCharacters(in: .whitespaces)
        if isTime(p) && unit.hasPrefix("s") { v *= 1000 }
        if unit.hasPrefix("k") { v *= 1000 }
        return clamp(p, v)
    }

    /// Значение в пределах параметра (OFF и AUTO — как есть), с шагом параметра.
    public static func clamp(_ p: ParamDef, _ v: Double) -> Double {
        if p.autoTop != nil && v >= MasterChain.autoValue { return MasterChain.autoValue }
        if p.offBottom != nil && v <= 0 { return 0 }
        var x: Double = Swift.min(p.max, Swift.max(p.min, v))
        if p.kind == .stepped { x = x.rounded() }
        if let st = p.step { x = (x / st).rounded() * st }
        return x
    }
}
