import AppKit

/// The colour under the pointer, on the pasteboard. macOS draws the loupe and
/// magnifies the pixels itself, so all that is left is the conversion and the
/// copy.
@MainActor
enum Sampler {
    static func pick() {
        NSColorSampler().show { chosen in
            guard let chosen else { return }

            // the loupe calls back on the main thread but says nothing about it
            MainActor.assumeIsolated {
                let hex = hex(of: chosen)

                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(hex, forType: .string)

                Toast.show(hex, seconds: 1)
            }
        }
    }

    /// Through sRGB: a colour picked off the screen carries the display's own
    /// space, and its raw components mean nothing outside it.
    private static func hex(of color: NSColor) -> String {
        guard let rgb = color.usingColorSpace(.sRGB) else { return "" }

        let channels = [rgb.redComponent, rgb.greenComponent, rgb.blueComponent]

        return "#" + channels.map { String(format: "%02X", Int(($0 * 255).rounded())) }.joined()
    }
}
