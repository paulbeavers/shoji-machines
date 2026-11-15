import AppKit

extension Notification.Name {
    static let configDidChange = Notification.Name("ShojiMachinesConfigDidChange")
}

extension NSColor {
    /// Create a color from a 0xRRGGBB value.
    convenience init(hex: UInt32, alpha: CGFloat = 1.0) {
        self.init(srgbRed: CGFloat((hex >> 16) & 0xFF) / 255, green: CGFloat((hex >> 8) & 0xFF) / 255,
                  blue: CGFloat(hex & 0xFF) / 255, alpha: alpha)
    }

    /// Parses "#RRGGBB" or "#RRGGBBAA".
    convenience init?(hexString: String) {
        var h = hexString.trimmingCharacters(in: .whitespaces)
        if h.hasPrefix("#") { h.removeFirst() }
        guard h.count == 6 || h.count == 8, let v = UInt64(h, radix: 16) else { return nil }
        let rgba = h.count == 6 ? (v << 8) | 0xFF : v
        self.init(srgbRed: CGFloat((rgba >> 24) & 0xFF) / 255, green: CGFloat((rgba >> 16) & 0xFF) / 255,
                  blue: CGFloat((rgba >> 8) & 0xFF) / 255, alpha: CGFloat(rgba & 0xFF) / 255)
    }
}

/// What Shoji Machines needs from Shoji's settings: the theme. It reads Shoji's
/// ~/.config/shoji/settings.json (the theme picked in Shoji), and Shoji posts
/// `changedAcrossApps` whenever it saves, so the Machines window recolours live. VMs also live
/// under ~/.config/shoji (vms/).
@MainActor
final class Config {
    static let shared = Config()

    /// ~/.config/shoji — shared with Shoji.
    nonisolated static var directory: URL {
        if let dir = ProcessInfo.processInfo.environment["SHOJI_CONFIG_DIR"] { return URL(fileURLWithPath: dir) }
        return URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent(".config/shoji")
    }

    /// Posted (distributed) by Shoji when it saves its settings.
    nonisolated static let changedAcrossApps = Notification.Name("dev.shoji.settingsChanged")

    var themeID = "catppuccin-mocha"
    var palette = Palette.mocha

    var isLight: Bool { palette.isLight }
    var appearance: NSAppearance { NSAppearance(named: isLight ? .aqua : .darkAqua)! }
    var base: NSColor { palette.base }
    var mantle: NSColor { palette.mantle }
    var crust: NSColor { palette.crust }
    var surface0: NSColor { palette.surface0 }
    var surface1: NSColor { palette.surface1 }
    var overlay0: NSColor { palette.overlay }
    var text: NSColor { palette.text }
    var subtext: NSColor { palette.subtext }
    var accent: NSColor { palette.mauve }
    var accent2: NSColor { palette.green }
    var red: NSColor { palette.red }
    var yellow: NSColor { palette.yellow }

    func uiFont(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont { .systemFont(ofSize: size, weight: weight) }
    func monoUIFont(_ size: CGFloat, weight: NSFont.Weight = .medium) -> NSFont { .monospacedSystemFont(ofSize: size, weight: weight) }

    func notifyChanged() { NotificationCenter.default.post(name: .configDidChange, object: self) }

    /// The theme from Shoji's settings (Lucent's default if Shoji hasn't saved one).
    func load() {
        let url = Self.directory.appendingPathComponent("settings.json")
        let saved = (try? Data(contentsOf: url))
            .flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }?["theme"] as? String
        let theme = ThemeLibrary.theme(saved ?? ThemeLibrary.defaultID) ?? ThemeLibrary.theme(ThemeLibrary.defaultID)
        if let theme {
            themeID = theme.id
            palette = theme.palette
        }
    }
}

final class FlippedView: NSView {
    var onLayout: (() -> Void)?
    override var isFlipped: Bool { true }
    override func layout() {
        super.layout()
        onLayout?()
    }
    override func setFrameSize(_ newSize: NSSize) {
        super.setFrameSize(newSize)
        needsLayout = true
    }
}
