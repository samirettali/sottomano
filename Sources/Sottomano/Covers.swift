import AppKit

/// Pictures that live on the internet — a playlist cover, an avatar — kept on
/// disk after the first look.
///
/// A list can name one in its fourth column, and only the rows on screen are
/// ever fetched: a list of a hundred and fifty playlists would otherwise open a
/// hundred and fifty connections to draw eight of them.
@MainActor
enum Covers {
    private static var memory: [String: NSImage] = [:]
    private static var fetching: Set<String> = []

    /// A site changes its icon now and then, so a copy is kept for a month and
    /// then asked for again. Nothing is thrown away first: the old one is shown
    /// while the new one is on its way, and replaced only when it arrives.
    private static let keepFor: TimeInterval = 30 * 24 * 3600

    private static let folder = FileManager.default
        .homeDirectoryForCurrentUser
        .appendingPathComponent(".cache/sottomano/covers")

    static func image(_ address: String?) -> NSImage? {
        guard let address else { return nil }

        if let ready = memory[address] { return ready }

        guard let image = NSImage(contentsOf: file(for: address)) else { return nil }

        memory[address] = image

        return image
    }

    /// Fetches whatever these rows are missing and calls back once each arrives,
    /// so the panel fills in rather than waiting to be complete.
    static func ensure(_ addresses: [String], then refresh: @MainActor @Sendable @escaping () -> Void) {
        for address in addresses where (image(address) == nil || isOld(address))
            && !fetching.contains(address) {
            guard let url = URL(string: address) else { continue }

            fetching.insert(address)

            URLSession.shared.dataTask(with: url) { data, _, _ in
                guard let data, let image = NSImage(data: data) else { return }

                Task { @MainActor in
                    try? FileManager.default.createDirectory(
                        at: folder,
                        withIntermediateDirectories: true
                    )

                    try? data.write(to: file(for: address))

                    memory[address] = image
                    fetching.remove(address)
                    refresh()
                }
            }
            .resume()
        }
    }

    private static func isOld(_ address: String) -> Bool {
        guard let written = try? FileManager.default
            .attributesOfItem(atPath: file(for: address).path)[.modificationDate] as? Date
        else { return true }

        return Date().timeIntervalSince(written) > keepFor
    }

    /// Named after the address, so the same cover is fetched once whatever list
    /// it turns up in.
    private static func file(for address: String) -> URL {
        folder.appendingPathComponent("\(abs(address.hashValue)).img")
    }
}
