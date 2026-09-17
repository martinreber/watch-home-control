// Persistence/KeychainStore.swift — secure API_Key persistence.
//
// The API_Key is a secret and lives ONLY in the watchOS Keychain (Req 2.2). This
// file defines the `KeychainStore` seam, a concrete `LiveKeychainStore` wrapping
// the Security-framework `SecItem*` APIs for a single generic-password item, and
// an in-memory `InMemoryKeychainStore` double so the Keychain round-trip property
// (Property 15) can run without a device (Req 1.4, 2.2, 2.5).

import Foundation
import Security

/// Persists and reads the secret API_Key.
///
/// Implementations store the key in a secure, per-app location. `readAPIKey`
/// returns `nil` when no key has been stored; `saveAPIKey` creates or replaces the
/// stored key; `deleteAPIKey` removes it. Save/delete throw on an unexpected
/// backing-store failure so callers can surface an error rather than silently
/// losing the credential.
protocol KeychainStore: Sendable {
    /// The stored API_Key, or `nil` when none has been persisted.
    func readAPIKey() -> String?

    /// Creates or replaces the stored API_Key (Req 1.4, 2.5).
    func saveAPIKey(_ key: String) throws

    /// Removes the stored API_Key, if any.
    func deleteAPIKey() throws
}

/// An error raised by `LiveKeychainStore` when a `SecItem*` call fails with an
/// unexpected `OSStatus`. `errSecItemNotFound` is handled internally (treated as
/// "absent") and never surfaces as an error.
struct KeychainError: Error, Equatable {
    /// The `OSStatus` returned by the failing Security-framework call.
    let status: OSStatus
}

/// `Keychain`-backed `KeychainStore`.
///
/// Wraps `SecItemAdd` / `SecItemCopyMatching` / `SecItemUpdate` / `SecItemDelete`
/// for a single generic-password item identified by
/// service `"ch.reber.watchhomecontrol"` and account `"api_key"`. The key is
/// stored UTF-8 encoded in the item's `kSecValueData`.
final class LiveKeychainStore: KeychainStore, @unchecked Sendable {
    /// Keychain generic-password service identifier for this app's credential.
    static let service = "ch.reber.watchhomecontrol"
    /// Keychain generic-password account identifier for the API_Key item.
    static let account = "api_key"

    private let service: String
    private let account: String

    init(service: String = LiveKeychainStore.service,
         account: String = LiveKeychainStore.account) {
        self.service = service
        self.account = account
    }

    /// Query matching exactly this app's single generic-password item.
    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }

    func readAPIKey() -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        guard status == errSecSuccess,
              let data = item as? Data,
              let key = String(data: data, encoding: .utf8)
        else {
            return nil
        }
        return key
    }

    func saveAPIKey(_ key: String) throws {
        let data = Data(key.utf8)

        // Update in place if the item already exists; otherwise add it.
        let updateStatus = SecItemUpdate(
            baseQuery as CFDictionary,
            [kSecValueData as String: data] as CFDictionary
        )

        switch updateStatus {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var addQuery = baseQuery
            addQuery[kSecValueData as String] = data
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError(status: addStatus)
            }
        default:
            throw KeychainError(status: updateStatus)
        }
    }

    func deleteAPIKey() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

/// In-memory `KeychainStore` double for tests.
///
/// Provides the same create/replace/read/delete semantics as `LiveKeychainStore`
/// without touching the Security framework, so the Keychain round-trip property
/// (Property 15) and view-model tests run deterministically off-device.
final class InMemoryKeychainStore: KeychainStore, @unchecked Sendable {
    private let lock = NSLock()
    private var storedKey: String?

    init(initialKey: String? = nil) {
        self.storedKey = initialKey
    }

    func readAPIKey() -> String? {
        lock.lock()
        defer { lock.unlock() }
        return storedKey
    }

    func saveAPIKey(_ key: String) throws {
        lock.lock()
        defer { lock.unlock() }
        storedKey = key
    }

    func deleteAPIKey() throws {
        lock.lock()
        defer { lock.unlock() }
        storedKey = nil
    }
}
