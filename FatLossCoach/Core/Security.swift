import Foundation
import Security

/// Minimal Keychain string store used for the local-data account-isolation marker.
///
/// The marker (the uid that owns the on-device `fatloss-data.json`) MUST live in the Keychain, not
/// UserDefaults: Keychain items with `kSecAttrAccessibleWhenUnlockedThisDeviceOnly` are not written
/// to iTunes/iCloud backups and cannot be edited by a filesystem/backup attacker to force the app to
/// adopt another account's residual data. (Mirrors the SurgiMD build-63 fix.)
enum Keychain {
    /// App-scoped service so the marker is namespaced to this app.
    private static let service = "com.MyFatLossCoach.app.isolation"

    @discardableResult
    static func set(_ value: String, for key: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(base as CFDictionary)
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        // ThisDeviceOnly: never migrates to a restored device / backup.
        add[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }

    static func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var out: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &out) == errSecSuccess,
              let data = out as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func delete(_ key: String) -> Bool {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        let status = SecItemDelete(query as CFDictionary)
        return status == errSecSuccess || status == errSecItemNotFound
    }
}
