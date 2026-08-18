import SwiftUI

/// How the panel looks and how it behaves as you go deeper, as options rather
/// than as a list of themes.
///
/// Every theme that existed was this panel with different knobs, so the knobs
/// are what the keymap sets. Two shapes could not be reduced to knobs — the
/// keyboard and the stack — and they stay as shapes.
struct Theme: Decodable {
    enum Shape: String, Decodable {
        /// Rows of keys.
        case list
        /// The layer lit on a drawing of the keyboard.
        case keyboard
        /// The layers walked through, kept behind the current one.
        case depth
    }

    enum Flow: String, Decodable {
        /// A layer takes the place of the one before it.
        case replace
        /// A layer is added to the right, and the ones before it stay.
        case columns
    }

    enum Key: String, Decodable {
        /// A column of its own, before the name.
        case column
        /// The initial of the name, which is the key anyway.
        case inline
    }

    var shape: Shape = .list
    var flow: Flow = .replace
    var key: Key = .column
    /// Between the key and the name. Nothing to draw when the key is inline.
    var arrow = true
    /// The road taken, over the panel: `sottomano › query`.
    var title = false
    /// Layers first, then what opens a search, then what acts and is done.
    var group = true

    /// Where the top edge sits, as a fraction of the screen from the top. The
    /// panel hangs from it and grows downwards, so this never moves as a layer
    /// changes the number of rows.
    var top: Double = 0.25

    var size: CGFloat = 19
    var padding: CGFloat = 24
    var radius: CGFloat = 12
    var borderWidth: CGFloat = 3
    /// Seconds. Zero turns every animation off.
    var animation: Double = 0.13

    /// A colour, or "glass" for the frosted material macOS draws behind a
    /// window. Anything else is #rgb, #rrggbb or #rrggbbaa.
    var background = "#000000"
    var border = "#ffffff66"
    var text = "#ffffff"
    /// Names that are not the point: a leaf action, a column left behind.
    var muted = "#ffffffae"
    var rule = "#ffffff40"
    var selection = "#ffffff1f"

    nonisolated(unsafe) static var current = Theme()

    var isGlass: Bool { background == "glass" }
}

extension Color {
    /// #rgb, #rrggbb or #rrggbbaa. An unreadable value is left black rather
    /// than crashing a panel over a typo in a config file.
    init(hex: String) {
        let digits = hex.hasPrefix("#") ? String(hex.dropFirst()) : hex
        let expanded = digits.count == 3 ? digits.map { "\($0)\($0)" }.joined() : digits

        guard let value = UInt64(expanded, radix: 16) else {
            self = .black
            return
        }

        let hasAlpha = expanded.count == 8
        let red = Double((value >> (hasAlpha ? 24 : 16)) & 0xFF) / 255
        let green = Double((value >> (hasAlpha ? 16 : 8)) & 0xFF) / 255
        let blue = Double((value >> (hasAlpha ? 8 : 0)) & 0xFF) / 255
        let alpha = hasAlpha ? Double(value & 0xFF) / 255 : 1

        self = Color(.sRGB, red: red, green: green, blue: blue, opacity: alpha)
    }
}
