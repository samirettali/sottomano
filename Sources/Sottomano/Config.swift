import Foundation

/// Watches the keymap and hands over a new one as soon as it is written.
///
/// The reading happens when the file changes rather than when the panel opens,
/// so trying a colour costs a save and nothing is added to the path between the
/// hotkey and the first frame.
@MainActor
final class Config {
    static let shared = Config()

    private var source: DispatchSourceFileSystemObject?
    private var onChange: ((Keymap) -> Void)?

    func watch(_ onChange: @escaping (Keymap) -> Void) {
        self.onChange = onChange
        arm()
    }

    private func arm() {
        source?.cancel()

        let descriptor = open(Keymap.url.path, O_EVTONLY)

        guard descriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: descriptor,
            eventMask: [.write, .extend, .delete, .rename],
            queue: .main
        )

        source.setEventHandler { [weak self] in
            MainActor.assumeIsolated {
                self?.reload()
            }
        }

        source.setCancelHandler {
            close(descriptor)
        }

        source.resume()
        self.source = source
    }

    private func reload() {
        // an editor saves by writing a new file over the name, so the descriptor
        // is now watching something that no longer has it: follow the name
        arm()

        // a half-written file does not decode, and the write that finishes it
        // will arrive right after
        guard let keymap = try? Keymap.load() else { return }

        onChange?(keymap)
    }
}
