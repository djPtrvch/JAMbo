import SwiftUI

/// Системные окна ввода и сообщения — общими функциями с AnyView (18.11, объём сборки в Playgrounds): .alert на месте
/// даёт каждому окну свой обобщённый тип и его функции, здесь тип один на все окна.
extension View {
    /// Поле ввода: OK — ok, Cancel — закрыть; extra — ещё одна кнопка перед Cancel (FILE BPM — AUTO).
    func inputAlert(_ title: String, shown: Binding<Bool>, text: Binding<String>, keyboard: UIKeyboardType = .default,
                    extra: String? = nil, extraAction: @escaping () -> Void = {}, ok: @escaping () -> Void) -> AnyView {
        let base: AnyView = AnyView(self)
        return AnyView(base.alert(title, isPresented: shown) {
            TextField(title, text: text).keyboardType(keyboard)
            Button("OK", action: ok)
            if let e = extra { Button(e, action: extraAction) }
            Button("Cancel", role: .cancel) {}
        })
    }

    /// Сообщение с кнопкой OK (cancel — роль .cancel, как было на месте); message — текст под заголовком.
    func noticeAlert(_ title: String, shown: Binding<Bool>, message: String? = nil, cancel: Bool = true,
                     ok: @escaping () -> Void = {}) -> AnyView {
        let base: AnyView = AnyView(self)
        let role: ButtonRole? = cancel ? .cancel : nil
        return AnyView(base.alert(title, isPresented: shown) {
            Button("OK", role: role, action: ok)
        } message: {
            if let m = message { Text(m) }
        })
    }
}
