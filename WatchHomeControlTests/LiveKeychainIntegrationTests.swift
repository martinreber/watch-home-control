// LiveKeychainIntegrationTests.swift — Task 7.5 (optional integration test).
//
// Exercises the concrete `SecItem`-based `LiveKeychainStore` save/read/delete
// life cycle against the real Security framework on the watchOS Simulator
// (Req 2.2). Unlike the Property 15 round-trip test — which runs off-device via
// the `InMemoryKeychainStore` double — this test verifies that the actual
// `SecItemAdd`/`SecItemCopyMatching`/`SecItemUpdate`/`SecItemDelete` wiring
// behaves as expected on a real Keychain backing store.
//
// The test uses a UNIQUE, UUID-based service/account so it is fully isolated
// from the real app credential (service `ch.reber.watchhomecontrol`,
// account `api_key`) and from any other run: it never reads, mutates, or
// deletes the production item.
//
// Keychain access on the watchOS Simulator generally works, but a Simulator
// environment can occasionally reject `SecItem*` calls with an entitlement
// error (e.g. `errSecMissingEntitlement` / -34018) when the test host lacks a
// keychain-access-group entitlement. Because this task is explicitly optional,
// the test detects that specific unrecoverable condition and skips gracefully
// (via a recorded reason) rather than leaving a hard failure.

import Foundation
import Security
import Testing
@testable import WatchHomeControl_Watch_App

struct LiveKeychainIntegrationTests {

    /// `OSStatus` values that indicate the Simulator/host environment cannot
    /// service Keychain calls at all (missing entitlement / no keychain
    /// available). When we hit one of these we skip rather than fail, since the
    /// on-device integration test is optional.
    private static let environmentBlockingStatuses: Set<OSStatus> = [
        errSecMissingEntitlement, // -34018: host lacks keychain-access-group entitlement
        -25291,                   // errSecNotAvailable: no keychain is available
    ]

    /// Probe whether the Keychain is usable in this environment by attempting a
    /// harmless add + delete of a throwaway item. Returns the blocking
    /// `OSStatus` if the environment refuses Keychain access, else `nil`.
    private func keychainBlockingStatus(service: String, account: String) -> OSStatus? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: Data("probe".utf8),
        ]
        let addStatus = SecItemAdd(query as CFDictionary, nil)
        if addStatus == errSecSuccess || addStatus == errSecDuplicateItem {
            // Clean up the probe item; environment is usable.
            SecItemDelete([
                kSecClass as String: kSecClassGenericPassword,
                kSecAttrService as String: service,
                kSecAttrAccount as String: account,
            ] as CFDictionary)
            return nil
        }
        return addStatus
    }

    @Test("LiveKeychainStore round-trips save/read/update/delete against the real Keychain")
    func liveKeychainLifecycle() throws {
        // Unique service/account so this test is isolated from the real app
        // credential and from any concurrent/previous run.
        let unique = UUID().uuidString
        let service = "ch.reber.watchhomecontrol.test.\(unique)"
        let account = "api_key.test.\(unique)"

        // Gracefully handle a Simulator/host environment that refuses Keychain
        // access. This task is optional, so an unrecoverable environment block
        // (missing entitlement / no keychain) must NOT leave a hard failure: we
        // return early after recording the reason as a comment, letting the
        // test pass as effectively skipped. Any OTHER unexpected probe failure
        // is still surfaced via Issue.record.
        if let blocking = keychainBlockingStatus(service: service, account: account) {
            if Self.environmentBlockingStatuses.contains(blocking) {
                // Return early (test passes as effectively skipped). The reason
                // is printed to the test log for visibility.
                print("[LiveKeychainIntegrationTests] Skipping optional on-device Keychain test: environment refused Keychain access with OSStatus \(blocking) (e.g. errSecMissingEntitlement/-34018). Run on a signed watchOS Simulator/device to exercise it.")
                return
            }
            // A different unexpected probe failure — surface it as a real issue.
            Issue.record("Keychain probe failed with unexpected OSStatus \(blocking)")
            return
        }

        let store = LiveKeychainStore(service: service, account: account)

        // Guarantee cleanup even if an assertion below throws.
        defer { try? store.deleteAPIKey() }

        // 1. Absent initially.
        #expect(store.readAPIKey() == nil)

        // 2. Save then read back (add path).
        try store.saveAPIKey("abc")
        #expect(store.readAPIKey() == "abc")

        // 3. Save a different value then read back (update path).
        try store.saveAPIKey("def")
        #expect(store.readAPIKey() == "def")

        // 4. Delete then read back nil.
        try store.deleteAPIKey()
        #expect(store.readAPIKey() == nil)

        // 5. Delete again is idempotent — errSecItemNotFound must not throw.
        try store.deleteAPIKey()
        #expect(store.readAPIKey() == nil)
    }
}
