import SwiftUI

/// Строка меню-формы (SETTINGS, SYNC и т. п.): подпись поля, пояснение, ряд кнопок, рычажок или свой вид.
/// Меню собираются списком строк — у компилятора один тип на все формы вместо отдельной цепочки видов на каждое меню
/// (S14: сборка в Playgrounds упирается в объём кода).
enum FormRow {
    case head(String)
    case label(String)
    case note(String)
    case choices([MenuChoice])
    case toggle(String, Bool, (Bool) -> Void)
    case view(AnyView)
}

/// Строки формы столбиком с зазором 8 (как VStack(alignment: .leading, spacing: 8) прежних меню).
struct FormRows: View {
    let rows: [FormRow]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(rows.indices, id: \.self) { i in
                FormRowView(row: rows[i])
            }
        }
    }
}

/// Одна строка формы.
struct FormRowView: View {
    let row: FormRow

    var body: some View {
        switch row {
        case .head(let t): MenuHead(title: t)
        case .label(let t): FieldLabel(title: t)
        case .note(let t): SettingsNote(text: t)
        case .choices(let items): MenuChoiceButtons(items: items)
        case .toggle(let t, let on, let change): ToggleRow(title: t, isOn: on, change: change)
        case .view(let v): v
        }
    }
}
