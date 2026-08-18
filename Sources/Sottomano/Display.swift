import CoreGraphics

/// The three monitor arrangements, moved over from display.lua. macOS makes the
/// display sitting at the origin the primary one, so placing the external there
/// is what promotes it.
enum Display {
    static func arrange(_ layout: String) -> String {
        let displays = active()
        let builtin = displays.first(where: { CGDisplayIsBuiltin($0) != 0 })
        let external = displays.first(where: { CGDisplayIsBuiltin($0) == 0 })

        guard let external else { return "no external display" }

        switch layout {
        case "external":
            return configure { config in
                CGConfigureDisplayOrigin(config, external, 0, 0)

                // mirroring the built-in panel is what "external only" means
                // here: macOS has no way to switch a display off
                if let builtin {
                    CGConfigureDisplayMirrorOfDisplay(config, builtin, external)
                }
            }

        case "docked":
            guard let builtin else { return "no built-in display" }

            return configure { config in
                CGConfigureDisplayMirrorOfDisplay(config, builtin, kCGNullDirectDisplay)
                CGConfigureDisplayOrigin(config, external, 0, 0)

                // centred under the external one
                let offset = Int32(width(external) / 2) - Int32(width(builtin) / 2)
                CGConfigureDisplayOrigin(config, builtin, offset, Int32(height(external)))
            }

        case "side-by-side":
            guard let builtin else { return "no built-in display" }

            return configure { config in
                CGConfigureDisplayMirrorOfDisplay(config, builtin, kCGNullDirectDisplay)
                CGConfigureDisplayOrigin(config, external, 0, 0)
                CGConfigureDisplayOrigin(
                    config,
                    builtin,
                    -Int32(width(external)),
                    Int32(height(external)) - Int32(height(builtin))
                )
            }

        default:
            return "unknown layout \(layout)"
        }
    }

    private static func active() -> [CGDirectDisplayID] {
        var count: UInt32 = 0
        CGGetActiveDisplayList(0, nil, &count)

        var displays = [CGDirectDisplayID](repeating: 0, count: Int(count))
        CGGetActiveDisplayList(count, &displays, &count)

        return displays
    }

    /// Every move goes in one transaction, so the screens rearrange once rather
    /// than shuffling through the intermediate positions.
    private static func configure(_ body: (CGDisplayConfigRef?) -> Void) -> String {
        var config: CGDisplayConfigRef?

        guard CGBeginDisplayConfiguration(&config) == .success else {
            return "could not start the display configuration"
        }

        body(config)

        guard CGCompleteDisplayConfiguration(config, .permanently) == .success else {
            CGCancelDisplayConfiguration(config)

            return "could not apply the display configuration"
        }

        return "done"
    }

    private static func width(_ display: CGDirectDisplayID) -> Int {
        CGDisplayPixelsWide(display)
    }

    private static func height(_ display: CGDirectDisplayID) -> Int {
        CGDisplayPixelsHigh(display)
    }
}
