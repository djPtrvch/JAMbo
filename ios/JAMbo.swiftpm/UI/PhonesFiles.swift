import SwiftUI

/// Коррекция наушников: окно сохранения профиля в «Файлы» (EXPORT) и итог IMPORT (профилей и пакетов голов).
struct PhonesFiles: ViewModifier {
    let model: AppModel

    func body(content: Content) -> some View {
        content
            .fileMover(isPresented: exportShown, file: model.phonesExported) { _ in model.phonesExported = nil }
            .alert(model.headsNote ? "Head packs" : "Correct EQ profiles", isPresented: noteShown) {
                Button("OK", role: .cancel) { model.phonesNote = nil }
            } message: {
                Text(model.phonesNote ?? "")
            }
    }

    private var exportShown: Binding<Bool> {
        Binding(get: { model.phonesExported != nil }, set: { if !$0 { model.phonesExported = nil } })
    }

    private var noteShown: Binding<Bool> {
        Binding(get: { model.phonesNote != nil }, set: { if !$0 { model.phonesNote = nil } })
    }
}
