import AppKit

enum Tool: String, CaseIterable {
    case arrow, rectangle, oval, highlighter, spotlight, pen, counter, text

    var key: String {
        switch self {
        case .arrow: return "a"
        case .rectangle: return "r"
        case .highlighter: return "h"
        case .spotlight: return "s"
        case .pen: return "p"
        case .oval: return "o"
        case .counter: return "n"
        case .text: return "t"
        }
    }

    var label: String {
        switch self {
        case .arrow: return "Flèche"
        case .rectangle: return "Rectangle"
        case .highlighter: return "Surligneur"
        case .spotlight: return "Projecteur"
        case .pen: return "Stylo"
        case .oval: return "Ovale"
        case .counter: return "Compteur"
        case .text: return "Texte"
        }
    }

    /// Short English label shown next to the menu-bar icon (≤ 6 chars).
    var shortLabel: String {
        switch self {
        case .arrow: return "Arrow"
        case .rectangle: return "Rect."
        case .highlighter: return "Hilite"
        case .spotlight: return "Spot"
        case .pen: return "Pen"
        case .oval: return "Oval"
        case .counter: return "Count"
        case .text: return "Text"
        }
    }

    var symbol: String {
        switch self {
        case .arrow: return "arrow.up.right"
        case .rectangle: return "rectangle"
        case .highlighter: return "highlighter"
        case .spotlight: return "flashlight.on.fill"
        case .pen: return "pencil.tip"
        case .oval: return "oval"
        case .counter: return "1.circle.fill"
        case .text: return "textformat"
        }
    }
}

struct InkColor {
    let name: String
    let color: NSColor

    init(_ name: String, _ hex: UInt32) {
        self.name = name
        self.color = NSColor(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
                             green: CGFloat((hex >> 8) & 0xFF) / 255,
                             blue: CGFloat(hex & 0xFF) / 255,
                             alpha: 1)
    }
}

let palette: [InkColor] = [
    InkColor("Rouge", 0xFF3B30),
    InkColor("Orange", 0xFF9500),
    InkColor("Jaune", 0xFFCC00),
    InkColor("Vert", 0x34C759),
    InkColor("Bleu", 0x0A84FF),
]

/// Persistent user preferences (UserDefaults).
final class Settings {
    static let shared = Settings()

    private let defaults = UserDefaults.standard
    private enum Key {
        static let tool = "tool", color = "colorIndex", width = "strokeWidth", clearOnExit = "clearOnExit"
    }

    static let minWidth: CGFloat = 1
    static let maxWidth: CGFloat = 24

    var tool: Tool { didSet { defaults.set(tool.rawValue, forKey: Key.tool) } }
    var colorIndex: Int { didSet { defaults.set(colorIndex, forKey: Key.color) } }
    var width: CGFloat { didSet { defaults.set(Double(width), forKey: Key.width) } }
    var clearOnExit: Bool { didSet { defaults.set(clearOnExit, forKey: Key.clearOnExit) } }

    var color: InkColor { palette[colorIndex] }

    private init() {
        defaults.register(defaults: [Key.tool: Tool.arrow.rawValue, Key.color: 0,
                                     Key.width: 4.0, Key.clearOnExit: false])
        tool = Tool(rawValue: defaults.string(forKey: Key.tool) ?? "") ?? .arrow
        let c = defaults.integer(forKey: Key.color)
        colorIndex = palette.indices.contains(c) ? c : 0
        let w = CGFloat(defaults.double(forKey: Key.width))
        width = min(max(w, Settings.minWidth), Settings.maxWidth)
        clearOnExit = defaults.bool(forKey: Key.clearOnExit)
    }
}
