import CoreAudioKit
import UIKit

/// Bluetooth MIDI (S13f): системные окна CoreAudioKit поверх приложения. CONNECT — поиск и подключение
/// BLE MIDI-устройств (CABTMIDICentralViewController; тап по подключённому — отключить), ADVERTISE — iPad
/// виден другим как Bluetooth MIDI-устройство (CABTMIDILocalPeripheralViewController). Подключённое
/// устройство появляется в CoreMIDI само — MidiHost подхватывает его по msgSetupChanged.
enum BluetoothMidi {
    /// Без ключа Bluetooth в Info.plist (Capabilities → Bluetooth в Playgrounds) поиск роняет приложение —
    /// тогда кнопки неактивны.
    static var available: Bool {
        return Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") != nil
    }

    static func connect() {
        guard available else { return }
        present(CABTMIDICentralViewController(), title: "BLUETOOTH MIDI")
    }

    static func advertise() {
        guard available else { return }
        present(CABTMIDILocalPeripheralViewController(), title: "ADVERTISE")
    }

    /// Окно — в навигации со своим ✕ справа (правило окон), листом поверх верхнего контроллера.
    private static func present(_ vc: UIViewController, title: String) {
        guard let top = topController() else { return }
        let nav: UINavigationController = UINavigationController(rootViewController: vc)
        vc.title = title
        let close: UIAction = UIAction { [weak nav] _ in nav?.dismiss(animated: true) }
        let item: UIBarButtonItem = UIBarButtonItem(image: UIImage(systemName: "xmark"), primaryAction: close)
        vc.navigationItem.rightBarButtonItem = item
        nav.modalPresentationStyle = .formSheet
        top.present(nav, animated: true)
    }

    private static func topController() -> UIViewController? {
        let scenes: [UIWindowScene] = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let windows: [UIWindow] = scenes.flatMap { $0.windows }
        let win: UIWindow? = windows.first { $0.isKeyWindow } ?? windows.first
        var c: UIViewController? = win?.rootViewController
        while let p = c?.presentedViewController { c = p }
        return c
    }
}
