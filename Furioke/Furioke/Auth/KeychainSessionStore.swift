import Foundation
import Security
import Supabase

/// Backs supabase-swift's session persistence with the iOS Keychain. Items are
/// written with `kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly`: readable in
/// the background after the first post-boot unlock, never synced off-device.
///
/// Stored via delete-then-add so the accessibility class is reasserted on every
/// write rather than inherited from a stale item.
struct KeychainSessionStore: AuthLocalStorage {
  enum KeychainError: Error {
    case unexpectedStatus(OSStatus)
  }

  let service: String

  init(service: String = "com.magicparklabs.Furioke.supabase-session") {
    self.service = service
  }

  nonisolated func store(key: String, value: Data) throws {
    try remove(key: key)
    let attributes: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecValueData as String: value,
      kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
    ]
    let status = SecItemAdd(attributes as CFDictionary, nil)
    guard status == errSecSuccess else { throw KeychainError.unexpectedStatus(status) }
  }

  nonisolated func retrieve(key: String) throws -> Data? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
      kSecReturnData as String: true,
      kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    var result: CFTypeRef?
    let status = SecItemCopyMatching(query as CFDictionary, &result)
    switch status {
    case errSecSuccess:
      return result as? Data
    case errSecItemNotFound:
      return nil
    default:
      throw KeychainError.unexpectedStatus(status)
    }
  }

  nonisolated func remove(key: String) throws {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: service,
      kSecAttrAccount as String: key,
    ]
    let status = SecItemDelete(query as CFDictionary)
    guard status == errSecSuccess || status == errSecItemNotFound else {
      throw KeychainError.unexpectedStatus(status)
    }
  }
}
