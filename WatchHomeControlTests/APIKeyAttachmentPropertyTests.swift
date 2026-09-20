// APIKeyAttachmentPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 2: The API key is attached to
// exactly the authenticated endpoints.
//
// Validates Requirements 2.1, 3.1.
//
// For any Endpoint and any stored API_Key, RequestBuilder attaches the
// `X-API-Key` header (equal to the stored key) to exactly the authenticated
// endpoints, and omits it from the unauthenticated ones. Per the pairing design
// (RequestBuilder.swift), the unauthenticated endpoints are `.health` and
// `.redeem`; every other endpoint carries the key. The oracle below mirrors
// that mapping.
//
// Uses Swift Testing (Apple's first-party framework) with a self-contained,
// deterministic splitmix64 generator so cases are reproducible and require no
// third-party dependency. Each property runs a minimum of 100 generated
// iterations.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct APIKeyAttachmentPropertyTests {

    // MARK: - Deterministic pseudo-random generator

    /// A tiny, self-contained splitmix64-style generator (matches the
    /// convention used by the other *PropertyTests.swift files).
    private struct RNG {
        private var state: UInt64
        init(seed: UInt64) { state = seed }

        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }

        mutating func int(_ range: Range<Int>) -> Int {
            let span = UInt64(range.count)
            return range.lowerBound + Int(next() % span)
        }

        mutating func bool() -> Bool { next() & 1 == 0 }

        mutating func pick<T>(_ items: [T]) -> T { items[int(0..<items.count)] }
    }

    // MARK: - Generators

    private static let baseURLs = [
        "http://192.168.1.122:8080", "http://10.0.0.1:8082",
        "https://home-control.local", "http://localhost:8080",
        "https://example.com"
    ]

    /// A spread of API keys, including edge shapes (short, long, symbols,
    /// unicode). The header value must round-trip exactly.
    private static let apiKeys = [
        "k", "abc123", "sk-XYZ_9876543210", "A-VERY-LONG-KEY-0000000000000000",
        "key.with.dots", "üñïçödé-key", "0000", "spaces are odd but stored",
        "!@#$%^&*()", String(repeating: "z", count: 128)
    ]

    private static let ids = [
        "1", "42", "RINCON_ABCDEF0123450",
        "lamp-ceiling", "living room", "ünïd", "id/with/slash"
    ]

    /// Builds a random endpoint. Returns whether it is one of the authenticated
    /// endpoints (everything except `.health` and `.redeem`).
    private static func makeEndpoint(_ rng: inout RNG) -> (endpoint: Endpoint, isAuthenticated: Bool) {
        switch rng.int(0..<9) {
        case 0:
            return (.health, false)
        case 1:
            return (.blind(rng.bool() ? .up : .down), true)
        case 2:
            return (.lamps, true)
        case 3:
            return (.lampState(id: rng.pick(ids), power: rng.bool()), true)
        case 4:
            return (.speakers, true)
        case 5:
            return (.speakerPlay(id: rng.pick(ids)), true)
        case 6:
            return (.speakerPause(id: rng.pick(ids)), true)
        case 7:
            return (.speakerRadio(id: rng.pick(ids), .radioBern1), true)
        default:
            return (.redeem(code: String(format: "%06d", rng.int(0..<1_000_000))), false)
        }
    }

    // MARK: - Property 2

    @Test("Property 2: X-API-Key is attached to exactly the authenticated endpoints")
    func apiKeyAttachedToExactlyAuthenticatedEndpoints() throws {
        var rng = RNG(seed: 0x2AB1_0A77_ACED_9701)
        var checked = 0
        var sawAuthenticated = false
        var sawUnauthenticated = false

        for _ in 0..<200 {
            let base = APIKeyAttachmentPropertyTests.baseURLs[rng.int(0..<APIKeyAttachmentPropertyTests.baseURLs.count)]
            guard let baseURL = URL(string: base) else {
                Issue.record("bad base URL fixture \(base)")
                continue
            }
            let builder = RequestBuilder(baseURL: baseURL)
            let key = APIKeyAttachmentPropertyTests.apiKeys[rng.int(0..<APIKeyAttachmentPropertyTests.apiKeys.count)]
            let (endpoint, isAuthenticated) = APIKeyAttachmentPropertyTests.makeEndpoint(&rng)

            let request = try builder.build(endpoint, apiKey: key)
            let header = request.value(forHTTPHeaderField: "X-API-Key")

            if isAuthenticated {
                sawAuthenticated = true
                #expect(header == key,
                        "authenticated endpoint must carry X-API-Key equal to the stored key; got \(String(describing: header))")
            } else {
                sawUnauthenticated = true
                #expect(header == nil,
                        "unauthenticated endpoint must not carry X-API-Key; got \(String(describing: header))")
            }
            checked += 1
        }

        #expect(checked >= 100)
        // Both branches of the property should have been exercised.
        #expect(sawAuthenticated)
        #expect(sawUnauthenticated)
    }

    @Test("Property 2: authenticated endpoints omit X-API-Key when no key is stored")
    func authenticatedEndpointOmitsHeaderWithNilKey() throws {
        // Reinforces that the header value tracks the stored key: with a nil
        // key even an authenticated endpoint has no X-API-Key header, while the
        // unauthenticated endpoints remain header-free regardless.
        var rng = RNG(seed: 0x2AB1_0FF0_11AB_C0DE)
        var checked = 0
        for _ in 0..<120 {
            let base = APIKeyAttachmentPropertyTests.baseURLs[rng.int(0..<APIKeyAttachmentPropertyTests.baseURLs.count)]
            guard let baseURL = URL(string: base) else {
                Issue.record("bad base URL fixture \(base)")
                continue
            }
            let builder = RequestBuilder(baseURL: baseURL)
            let (endpoint, _) = APIKeyAttachmentPropertyTests.makeEndpoint(&rng)

            let request = try builder.build(endpoint, apiKey: nil)
            #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil,
                    "no stored key => no X-API-Key header on any endpoint")
            checked += 1
        }
        #expect(checked >= 100)
    }
}
