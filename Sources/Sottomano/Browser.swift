import AppKit

/// Walking the filesystem from the keyboard, one directory at a time.
///
/// Not a search over everything: a place you are standing in, which is what a
/// file manager is for and what a fuzzy finder over the whole disk is not. The
/// query filters where you are; return goes in; delete on an empty query comes
/// back out.
@MainActor
enum Browser {
    /// Directories before files, and each alphabetically. Dotfiles are left out:
    /// on this machine they are configuration, and configuration is reached by
    /// its own means.
    static func read(_ directory: URL) -> [Choice] {
        let keys: [URLResourceKey] = [.isDirectoryKey, .fileSizeKey, .contentModificationDateKey]

        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory,
            includingPropertiesForKeys: keys,
            options: [.skipsHiddenFiles]
        )) ?? []

        let entries = contents.map { url -> (url: URL, isDirectory: Bool) in
            let values = try? url.resourceValues(forKeys: Set(keys))

            return (url, values?.isDirectory ?? false)
        }

        return entries
            .sorted { first, second in
                if first.isDirectory != second.isDirectory { return first.isDirectory }

                return first.url.lastPathComponent.localizedStandardCompare(
                    second.url.lastPathComponent
                ) == .orderedAscending
            }
            .map { entry in
                Choice(
                    value: entry.url.path,
                    name: entry.url.lastPathComponent,
                    subtitle: subtitle(entry.url, isDirectory: entry.isDirectory),
                    boost: Frecency.shared.score(entry.url.path),
                    icon: NSWorkspace.shared.icon(forFile: entry.url.path),
                    isDirectory: entry.isDirectory
                )
            }
    }

    /// `~` for home, and the home prefix folded back to `~` on the way out, so
    /// the header reads the way a shell prompt does.
    static func expand(_ path: String) -> URL {
        URL(fileURLWithPath: (path as NSString).expandingTildeInPath).standardizedFileURL
    }

    static func shorten(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path

        return url.path.hasPrefix(home) ? "~" + url.path.dropFirst(home.count) : url.path
    }

    private static func subtitle(_ url: URL, isDirectory: Bool) -> String {
        if isDirectory {
            let children = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []

            return "\(children.count) items"
        }

        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0

        return ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file)
    }
}
