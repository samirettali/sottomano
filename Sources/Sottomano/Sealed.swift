import CryptoKit
import Foundation
import Security

/// The clipboard history at rest. Two hundred lines of what was copied is a
/// fair sample of a person's day, and it sat in a JSON file that anything
/// running as the user could read. Now it is sealed with a key the keychain
/// holds, so the file on its own says nothing and the key never sits beside
/// it.
///
/// AES-GCM through CryptoKit: authenticated, so a file that was tampered
/// with does not decode to something plausible. The key is a generic
/// password in the login keychain, made once and kept; the signed app is the
/// one that made it, so there is no prompt.
enum Sealed {
    private static let service = "com.samirettali.sottomano"
    private static let account = "clipboard-key"

    /// Read once per run: the keychain is a round trip through securityd.
    nonisolated(unsafe) private static var cached: SymmetricKey?

    static func seal(_ data: Data) -> Data? {
        guard let key else { return nil }

        return try? AES.GCM.seal(data, using: key).combined
    }

    static func open(_ data: Data) -> Data? {
        guard let key, let box = try? AES.GCM.SealedBox(combined: data) else { return nil }

        return try? AES.GCM.open(box, using: key)
    }

    private static var key: SymmetricKey? {
        if let cached { return cached }

        if let found = read() {
            cached = found

            return found
        }

        let made = SymmetricKey(size: .bits256)

        guard write(made) else { return nil }

        cached = made

        return made
    }

    private static func read() -> SymmetricKey? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?

        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data
        else { return nil }

        return SymmetricKey(data: data)
    }

    private static func write(_ key: SymmetricKey) -> Bool {
        let data = key.withUnsafeBytes { Data($0) }

        // this device only, and never in an iCloud keychain: the file it
        // opens is on this disk and nowhere else
        let attributes: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrLabel as String: "Sottomano clipboard history",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecValueData as String: data,
        ]

        return SecItemAdd(attributes as CFDictionary, nil) == errSecSuccess
    }
}
