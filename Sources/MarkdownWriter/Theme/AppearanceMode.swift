import AppKit
import SwiftUI

/// Three-way appearance control: follow the system, or pin light/dark.
enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: return "Auto"
        case .light: return "Light"
        case .dark: return "Dark"
        }
    }

    var symbol: String {
        switch self {
        case .system: return "circle.lefthalf.filled"
        case .light: return "sun.max"
        case .dark: return "moon"
        }
    }

    /// `nil` means "inherit from the system".
    var nsAppearance: NSAppearance? {
        switch self {
        case .system: return nil
        case .light: return NSAppearance(named: .aqua)
        case .dark: return NSAppearance(named: .darkAqua)
        }
    }
}

/// Single source of truth for user preferences that affect every window.
/// `@AppStorage` only publishes correctly from a `View`, so this keeps its own
/// `@Published` state backed by `UserDefaults`.
final class Preferences: ObservableObject {
    static let shared = Preferences()

    private enum Key {
        static let appearance = "appearanceMode"
        static let fontSize = "editorFontSize"
    }

    static let minFontSize: CGFloat = 13
    static let maxFontSize: CGFloat = 28
    static let defaultFontSize: CGFloat = 18

    @Published var appearance: AppearanceMode {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: Key.appearance)
            applyAppearance()
        }
    }

    @Published var fontSize: CGFloat {
        didSet {
            UserDefaults.standard.set(Double(fontSize), forKey: Key.fontSize)
        }
    }

    private init() {
        let stored = UserDefaults.standard.string(forKey: Key.appearance)
        appearance = stored.flatMap(AppearanceMode.init(rawValue:)) ?? .system

        let size = UserDefaults.standard.double(forKey: Key.fontSize)
        fontSize = size > 0 ? CGFloat(size) : Preferences.defaultFontSize
    }

    func applyAppearance() {
        NSApplication.shared.appearance = appearance.nsAppearance
    }

    func nudgeFontSize(by delta: CGFloat) {
        fontSize = min(Preferences.maxFontSize, max(Preferences.minFontSize, fontSize + delta))
    }

    func resetFontSize() {
        fontSize = Preferences.defaultFontSize
    }
}
