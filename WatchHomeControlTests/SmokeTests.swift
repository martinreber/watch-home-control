// SmokeTests.swift
//
// Feature: apple-watch-home-control — smoke tests (Task 16.2).
//
// These are lightweight presence/regression guards (not property tests, no
// Property tag). They protect three cross-cutting invariants the UI depends on:
//
//   1. German labels (Req 10.1): the key user-facing German strings exist in
//      Strings.swift and hold their expected German values. This guards against
//      an accidental English string or a regression in the single source of
//      truth for UI copy.
//
//   2. ATS local-networking exception (Req 11.2): the app's Info.plist declares
//      NSAppTransportSecurity -> NSAllowsLocalNetworking = true, which is what
//      permits cleartext HTTP to the LAN Base_URL. Without it every Backend
//      request over http:// would be blocked by App Transport Security.
//
//   3. Setup presence (Req 1.3, 1.2): the Setup_Screen's key field/labels exist
//      — the Base_URL label and the Pairing_Code label (the Setup_Screen now
//      pairs with a 6-digit code rather than a raw API key, per Requirement 12),
//      plus the submit/cancel affordances. This reuses the Strings assertions.
//
// Framework: Swift Testing (matches every sibling test in this target).

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct SmokeTests {

    // MARK: - 1. German labels (Req 10.1)

    @Test("Req 10.1: the three section titles hold their German values (Storen / Lampen / Sonos)")
    func sectionTitlesAreGerman() {
        #expect(Strings.sectionBlinds == "Storen",
                "the blind section title must be the German 'Storen' (Req 10.1)")
        #expect(Strings.sectionLamps == "Lampen",
                "the lamp section title must be the German 'Lampen' (Req 10.1)")
        #expect(Strings.sectionSpeakers == "Sonos",
                "the speaker section title must be 'Sonos' (Req 10.1)")
    }

    @Test("Req 10.1: the blind controls hold their German values (Hoch / Runter)")
    func blindControlsAreGerman() {
        #expect(Strings.blindUp == "Hoch",
                "the raise-blinds control must be the German 'Hoch' (Req 10.1)")
        #expect(Strings.blindDown == "Runter",
                "the lower-blinds control must be the German 'Runter' (Req 10.1)")
    }

    @Test("Req 5.6 / 7.8: the empty-state messages hold their exact German values")
    func emptyStateMessagesAreGerman() {
        #expect(Strings.lampsEmpty == "Keine Lampen gefunden",
                "the empty lamp list message must be German (Req 5.6)")
        #expect(Strings.speakersEmpty == "Keine Lautsprecher gefunden",
                "the empty speaker list message must be German (Req 7.8)")
    }

    @Test("Req 3.3/3.4 & 2.3: unreachable and invalid-credential messages hold their German values")
    func statusAndCredentialMessagesAreGerman() {
        #expect(Strings.backendUnreachable == "Backend nicht erreichbar",
                "the unreachable-Backend message must be German (Req 3.3/3.4)")
        #expect(Strings.pairingInvalid == "Kopplung ungültig - bitte neu koppeln",
                "the invalid-credential / re-pair message must be German (Req 2.3)")
        #expect(Strings.invalidURL == "Ungültige Adresse",
                "the invalid-address message must be German (Req 1.8)")
    }

    // MARK: - 3. Setup presence (Req 1.3, 1.2)

    @Test("Req 1.2/1.3: the Setup_Screen labels exist in German (Einrichtung, Serveradresse, Kopplungscode, actions)")
    func setupScreenLabelsAreGerman() {
        // Setup screen title (Req 1.2/1.3) and the config-reuse title (Req 1.10).
        #expect(Strings.setupTitle == "Einrichtung",
                "the Setup_Screen title must be the German 'Einrichtung' (Req 1.2/1.3)")
        #expect(Strings.configTitle == "Konfiguration",
                "the configuration screen title must be German (Req 1.10)")
        // Base_URL field label (Req 1.2).
        #expect(Strings.baseURLLabel == "Serveradresse",
                "the Base_URL field must carry a German label (Req 1.2)")
        // Pairing_Code field label (Req 1.3) — the Setup_Screen pairs with a
        // 6-digit code, not a raw API key.
        #expect(Strings.pairingCodeLabel == "Kopplungscode",
                "the Pairing_Code field must carry the German label 'Kopplungscode' (Req 1.3)")
        // Submit / cancel affordances.
        #expect(Strings.save == "Speichern",
                "the submit affordance must be the German 'Speichern' (Req 1.3)")
        #expect(Strings.cancel == "Abbrechen",
                "the cancel affordance must be the German 'Abbrechen' (Req 1.10)")
    }

    // MARK: - 2. ATS local-networking exception (Req 11.2)

    @Test("Req 11.2: the app Info.plist declares NSAppTransportSecurity -> NSAllowsLocalNetworking = true")
    func atsAllowsLocalNetworking() throws {
        // Primary source: the test runs app-hosted, so Bundle.main is the app
        // bundle and its Info dictionary carries the compiled ATS keys. Fall
        // back to parsing the source Info.plist only if the bundle lookup is
        // unavailable (e.g. a differently configured host).
        let allowsLocalNetworking = try Self.bundleAllowsLocalNetworking()
            ?? Self.sourcePlistAllowsLocalNetworking()

        #expect(allowsLocalNetworking == true,
                "Info.plist must set NSAppTransportSecurity -> NSAllowsLocalNetworking = true so cleartext LAN HTTP is permitted (Req 11.2)")
    }

    /// Reads `NSAppTransportSecurity -> NSAllowsLocalNetworking` from the running
    /// app bundle's Info dictionary. Returns `nil` when the ATS dictionary or the
    /// key is absent from `Bundle.main` (so the caller can fall back to source).
    private static func bundleAllowsLocalNetworking() -> Bool? {
        guard
            let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any],
            let value = ats["NSAllowsLocalNetworking"] as? Bool
        else {
            return nil
        }
        return value
    }

    /// Fallback: locate the source `Info.plist` and read the same ATS key with
    /// `PropertyListSerialization`. Searches upward from this test file toward
    /// the target's `Info.plist` at "WatchHomeControl Watch App/Info.plist".
    private static func sourcePlistAllowsLocalNetworking() throws -> Bool {
        let fm = FileManager.default

        // Candidate roots: the repo root walked up from this source file.
        var searchDir = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
        let relative = "WatchHomeControl Watch App/Info.plist"

        var plistURL: URL?
        for _ in 0..<8 {
            let candidate = searchDir.appendingPathComponent(relative)
            if fm.fileExists(atPath: candidate.path) {
                plistURL = candidate
                break
            }
            searchDir.deleteLastPathComponent()
        }

        let url = try #require(plistURL,
                               "could not locate the source Info.plist at '\(relative)' to verify the ATS exception")

        let data = try Data(contentsOf: url)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)

        let root = try #require(plist as? [String: Any], "Info.plist root must be a dictionary")
        let ats = try #require(root["NSAppTransportSecurity"] as? [String: Any],
                               "Info.plist must contain an NSAppTransportSecurity dictionary (Req 11.2)")
        let value = try #require(ats["NSAllowsLocalNetworking"] as? Bool,
                                 "NSAppTransportSecurity must contain NSAllowsLocalNetworking (Req 11.2)")
        return value
    }
}
