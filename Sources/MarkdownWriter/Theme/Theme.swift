import AppKit

/// Colors are dynamic `NSColor`s, so they resolve against whatever appearance
/// the view is drawing in. That means a light/dark switch needs no re-theming
/// of the attributed string — only a redraw.
enum Palette {
    static func dynamic(light: NSColor, dark: NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? dark : light
        }
    }

    private static func hex(_ value: UInt32) -> NSColor {
        NSColor(
            srgbRed: CGFloat((value >> 16) & 0xFF) / 255,
            green: CGFloat((value >> 8) & 0xFF) / 255,
            blue: CGFloat(value & 0xFF) / 255,
            alpha: 1
        )
    }

    /// Warm off-white / near-black rather than pure #FFF / #000. Pure white is
    /// harsh under long writing sessions; pure black crushes antialiasing.
    static let background = dynamic(light: hex(0xFCFBF8), dark: hex(0x1B1B1D))
    static let text = dynamic(light: hex(0x2B2A28), dark: hex(0xE6E3DD))

    /// Syntax markers (`#`, `**`, list bullets). Present but recessive.
    static let marker = dynamic(light: hex(0xB9B3A8), dark: hex(0x5F5C57))
    static let secondary = dynamic(light: hex(0x84807A), dark: hex(0x9A958E))

    static let accent = dynamic(light: hex(0xB0532F), dark: hex(0xE08B62))
    /// Underlines and ornaments that shouldn't compete with the text.
    static let accentFaded = dynamic(light: hex(0xE0BCAC), dark: hex(0x8A5540))
    static let bullet = dynamic(light: hex(0xB9A99A), dark: hex(0x7A6C60))
    static let codeText = dynamic(light: hex(0x4A4642), dark: hex(0xCFC9C0))
    static let codeBackground = dynamic(light: hex(0xF2EFE9), dark: hex(0x252528))
    static let quoteBar = dynamic(light: hex(0xDDD7CB), dark: hex(0x3C3B3E))
    static let rule = dynamic(light: hex(0xE2DDD2), dark: hex(0x36353A))
    static let insertionPoint = dynamic(light: hex(0xB0532F), dark: hex(0xE08B62))
    static let selection = dynamic(light: hex(0xE9E2D4), dark: hex(0x36343A))
}

/// The body typefaces on offer. All of them ship with macOS, and each falls
/// back to the matching system design if the family is ever missing.
enum EditorFont: String, CaseIterable, Identifiable {
    case newYork
    case system
    case avenir
    case iowan
    case mono

    var id: String { rawValue }

    var label: String {
        switch self {
        case .newYork: return "New York"
        case .system: return "San Francisco"
        case .avenir: return "Avenir Next"
        case .iowan: return "Iowan Old Style"
        case .mono: return "SF Mono"
        }
    }

    var note: String {
        switch self {
        case .newYork: return "Apple's serif — warm, bookish"
        case .system: return "The system sans — neutral, very legible"
        case .avenir: return "Humanist sans — geometric, airy"
        case .iowan: return "Book serif — sturdier than New York"
        case .mono: return "Monospaced, iA Writer style"
        }
    }

    /// `nil` means "use the system face for `design`".
    fileprivate var familyName: String? {
        switch self {
        case .newYork, .system: return nil
        case .avenir: return "Avenir Next"
        case .iowan: return "Iowan Old Style"
        case .mono: return nil
        }
    }

    fileprivate var design: NSFontDescriptor.SystemDesign {
        switch self {
        case .newYork, .iowan: return .serif
        case .system, .avenir: return .default
        case .mono: return .monospaced
        }
    }

    /// Sans faces need a touch more leading than serifs at the same size to
    /// read comfortably; mono needs the most.
    fileprivate var lineHeightMultiple: CGFloat {
        switch self {
        case .newYork, .iowan: return 1.50
        case .system, .avenir: return 1.55
        case .mono: return 1.62
        }
    }

    /// Measure is a count of characters, not a width. Wider faces need a wider
    /// column to land on the same ~68 characters.
    fileprivate var measureScale: CGFloat {
        switch self {
        case .newYork, .iowan: return 1.0
        case .system: return 1.04
        case .avenir: return 1.08
        case .mono: return 1.22
        }
    }
}

/// Typography derived from a single base size, so ⌘+/⌘- scales the whole
/// hierarchy proportionally.
struct Typography: Equatable {
    let base: CGFloat
    var family: EditorFont = .newYork

    private func resolve(size: CGFloat, weight: NSFont.Weight) -> NSFont {
        if let name = family.familyName,
           let named = NSFont(name: name, size: size) {
            guard weight >= .semibold else { return named }
            return NSFontManager.shared.convert(named, toHaveTrait: .boldFontMask)
        }
        let system = NSFont.systemFont(ofSize: size, weight: weight)
        guard let descriptor = system.fontDescriptor.withDesign(family.design),
              let font = NSFont(descriptor: descriptor, size: size)
        else { return system }
        return font
    }

    private static func mono(size: CGFloat) -> NSFont {
        NSFont.monospacedSystemFont(ofSize: size, weight: .regular)
    }

    var body: NSFont { resolve(size: base, weight: .regular) }
    /// Code is always monospaced, whatever the prose face.
    var code: NSFont { Self.mono(size: base * 0.88) }

    /// Level 1...6.
    func heading(_ level: Int) -> NSFont {
        let scale: CGFloat
        switch level {
        case 1: scale = 1.72
        case 2: scale = 1.42
        case 3: scale = 1.22
        case 4: scale = 1.10
        default: scale = 1.0
        }
        return resolve(size: (base * scale).rounded(), weight: level <= 2 ? .bold : .semibold)
    }

    var lineHeightMultiple: CGFloat { family.lineHeightMultiple }
    var paragraphSpacing: CGFloat { base * 0.62 }

    /// Roughly 68 characters at the current size — the comfortable measure that
    /// Bear, iA Writer and Medium all land near.
    var maxMeasure: CGFloat { (base * 34 * family.measureScale).rounded() }
    var verticalPadding: CGFloat { 96 }
}
