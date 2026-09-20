import Foundation
import Testing
@testable import WatchHomeControl_Watch_App

/// Property-based tests for the Base_URL persistence layer (`LiveSettingsStore`).
///
/// Uses Swift Testing's generator-driven approach: a deterministic-but-varied
/// pseudo-random generator produces syntactically valid absolute http(s) URLs
/// (varying scheme, host, port, path, and query), and each generated case is
/// round-tripped through a freshly isolated `UserDefaults` suite. No third-party
/// property-testing engine is used.
struct SettingsStorePropertyTests {

    // MARK: - Generators

    /// A small, seedable linear-congruential generator so the ≥100 iterations are
    /// reproducible per run yet cover a varied input space across seeds.
    private struct SeededRandom {
        private var state: UInt64
        init(seed: UInt64) { self.state = seed &+ 0x9E3779B97F4A7C15 }

        mutating func next() -> UInt64 {
            // SplitMix64
            state = state &+ 0x9E3779B97F4A7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
            z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
            return z ^ (z >> 31)
        }

        mutating func int(in range: ClosedRange<Int>) -> Int {
            let span = UInt64(range.upperBound - range.lowerBound + 1)
            return range.lowerBound + Int(next() % span)
        }

        mutating func bool() -> Bool { next() & 1 == 0 }

        mutating func element<T>(_ items: [T]) -> T {
            items[int(in: 0...(items.count - 1))]
        }
    }

    /// Generates a syntactically valid absolute http(s) URL string with a host,
    /// varying scheme, host, optional port, optional path, and optional query.
    ///
    /// Only unreserved / path-safe characters are used so the produced string is
    /// guaranteed to parse via `URL(string:)` and survive an `absoluteString`
    /// round-trip without normalization surprises.
    private static func generateValidURLString(_ rng: inout SeededRandom) -> String {
        let scheme = rng.bool() ? "http" : "https"

        let hosts = [
            "192.168.1.122",
            "10.0.0.1",
            "localhost",
            "home.local",
            "pi.example.com",
            "api-server",
            "a.b.c.d.example",
        ]
        let host = rng.element(hosts)

        var url = "\(scheme)://\(host)"

        // Optional port.
        if rng.bool() {
            url += ":\(rng.int(in: 1...65535))"
        }

        // Optional path (one or more safe segments).
        if rng.bool() {
            let segments = ["", "api", "v1", "lamps", "sonos", "blind", "health", "a_b-c.d"]
            let count = rng.int(in: 1...3)
            for _ in 0..<count {
                url += "/" + rng.element(segments)
            }
        }

        // Optional query with safe key/value pairs.
        if rng.bool() {
            let keys = ["q", "id", "power", "action", "code"]
            let values = ["1", "up", "down", "true", "false", "abc123"]
            url += "?\(rng.element(keys))=\(rng.element(values))"
        }

        return url
    }

    // MARK: - Property 13

    /// Feature: apple-watch-home-control, Property 13: Base_URL persistence round-trips
    ///
    /// *For any* syntactically valid http(s) URL string, persisting it via the
    /// settings store and reading it back yields the same URL.
    ///
    /// **Validates: Requirements 1.6**
    @Test("Feature: apple-watch-home-control, Property 13: Base_URL persistence round-trips")
    func baseURLPersistenceRoundTrips() {
        let iterations = 200 // ≥100 generated cases.
        var rng = SeededRandom(seed: 0xC0FFEE)

        // A single isolated, uniquely-named suite for the whole test: it never
        // touches `.standard` and never collides with other tests. The key is
        // cleared between iterations so each case starts from a clean slate.
        // (Allocating a fresh suite per iteration is avoided — repeatedly
        // creating/tearing down hundreds of suites is expensive and unstable on
        // the watchOS simulator.)
        let suiteName = "test.settingsstore.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        for _ in 0..<iterations {
            let raw = Self.generateValidURLString(&rng)

            // Only exercise inputs that are genuine valid absolute http(s) URLs
            // (per the app's own validator), matching the property's precondition.
            guard case .success(let url) = URLValidator.validate(raw) else {
                continue
            }

            defaults.removeObject(forKey: "base_url")

            let store = LiveSettingsStore(defaults: defaults)
            store.setBaseURL(url)

            #expect(
                store.baseURL == url,
                "Round-trip mismatch for input \(raw): stored \(url), read back \(store.baseURL)"
            )

            // A freshly constructed store over the same defaults reads the same
            // persisted value (persistence survives store re-creation).
            let reopened = LiveSettingsStore(defaults: defaults)
            #expect(
                reopened.baseURL == url,
                "Reopened store mismatch for input \(raw): expected \(url), got \(reopened.baseURL)"
            )
        }
    }
}
