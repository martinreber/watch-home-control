// RedeemRequestShapePropertyTests.swift
//
// Feature: apple-watch-home-control, Property 20: The redeem request carries the
// code body and no API key header.
//
// Validates Requirements 11.1, 11.3, 12.1.
//
// For any 6-digit Pairing_Code and any Base_URL, the URLRequest built by
// RequestBuilder for `Endpoint.redeem(code:)`:
//   - is a POST to <baseURL>/pairing/redeem,
//   - has `Content-Type: application/json`,
//   - has a JSON body decoding to exactly {"code": <code>}, and
//   - carries NO `X-API-Key` header — even when a key is passed to build().
//
// This complements RequestBuilderPropertyTests (Property 1, general mapping) and
// APIKeyAttachmentPropertyTests (Property 2, key attachment) by focusing on the
// exact redeem body and the no-key guarantee under both a nil and a non-nil key
// argument.
//
// Uses Swift Testing (Apple's first-party framework) with a self-contained,
// deterministic splitmix64 generator so cases are reproducible and require no
// third-party dependency. Runs a minimum of 100 generated iterations.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct RedeemRequestShapePropertyTests {

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

    /// Base_URLs spanning http/https, LAN IPs, ports, host names, and both with
    /// and without a trailing slash (to exercise relative-path resolution).
    private static let baseURLStrings = [
        "http://192.168.1.122:8080",
        "http://192.168.1.122:8080/",
        "https://example.com",
        "https://example.com/",
        "http://10.0.0.1:80",
        "http://home-control.local:8082",
        "https://sub.example.org:65535",
        "http://127.0.0.1:8080",
        "http://server123:1"
    ]

    /// API keys to pass to build() — the redeem request must omit X-API-Key
    /// regardless of these. Includes edge shapes.
    private static let apiKeys = [
        "k", "abc123", "sk-XYZ_9876543210",
        "A-VERY-LONG-KEY-0000000000000000", "üñïçödé-key",
        "!@#$%^&*()", String(repeating: "z", count: 128)
    ]

    /// A 6-digit code, matching the Pairing_Code shape (Req 1.5).
    private static func makeCode(_ rng: inout RNG) -> String {
        String(format: "%06d", rng.int(0..<1_000_000))
    }

    /// Independent oracle: the redeem body must decode to exactly {"code": code}.
    private static func bodyIsExactlyCode(_ data: Data, _ code: String) -> Bool {
        guard let obj = try? JSONDecoder().decode([String: String].self, from: data) else { return false }
        return obj == ["code": code]
    }

    // MARK: - Property 20

    @Test("Property 20: the redeem request carries the code body and no API key header (nil key)")
    func redeemShapeWithNilKey() throws {
        var rng = RNG(seed: 0x2ED0_C0DE_0001_0020)
        var checked = 0

        for _ in 0..<120 {
            let baseString = Self.baseURLStrings[rng.int(0..<Self.baseURLStrings.count)]
            let baseURL = try #require(URL(string: baseString), "invalid Base_URL fixture \(baseString)")
            let code = Self.makeCode(&rng)

            let builder = RequestBuilder(baseURL: baseURL)
            let request = try builder.build(.redeem(code: code), apiKey: nil)

            try assertRedeemShape(request, code: code, baseURL: baseURL)
            checked += 1
        }

        #expect(checked >= 100, "expected at least 100 property iterations, ran \(checked)")
    }

    @Test("Property 20: the redeem request omits X-API-Key even when a key is passed to build()")
    func redeemShapeWithKeyPresent() throws {
        var rng = RNG(seed: 0x2ED0_C0DE_0002_0020)
        var checked = 0

        for _ in 0..<120 {
            let baseString = Self.baseURLStrings[rng.int(0..<Self.baseURLStrings.count)]
            let baseURL = try #require(URL(string: baseString), "invalid Base_URL fixture \(baseString)")
            let code = Self.makeCode(&rng)
            let key = Self.apiKeys[rng.int(0..<Self.apiKeys.count)]

            let builder = RequestBuilder(baseURL: baseURL)
            // Contrast case: a non-nil key is supplied, yet redeem must stay
            // unauthenticated (Req 12.1) — no X-API-Key header appears.
            let request = try builder.build(.redeem(code: code), apiKey: key)

            try assertRedeemShape(request, code: code, baseURL: baseURL)
            checked += 1
        }

        #expect(checked >= 100, "expected at least 100 property iterations, ran \(checked)")
    }

    // MARK: - Shared assertions

    /// Asserts the full redeem request shape: POST /pairing/redeem against the
    /// Base_URL origin, JSON Content-Type, body == {"code": code}, and no key.
    private func assertRedeemShape(_ request: URLRequest, code: String, baseURL: URL) throws {
        // POST.
        #expect(request.httpMethod == "POST",
                "redeem must be POST, got \(String(describing: request.httpMethod))")

        // URL: <baseURL origin>/pairing/redeem.
        let url = try #require(request.url, "expected a URL for redeem")
        let origin = "\(baseURL.scheme ?? "")://\(baseURL.host ?? "")" +
            (baseURL.port.map { ":\($0)" } ?? "")
        #expect(url.absoluteString.hasPrefix(origin),
                "expected \(url.absoluteString) to begin with Base_URL origin \(origin)")
        #expect(url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
                "scheme mismatch for \(url.absoluteString)")
        #expect(url.host == baseURL.host, "host mismatch for \(url.absoluteString)")
        #expect(url.port == baseURL.port, "port mismatch for \(url.absoluteString)")
        #expect(url.path == "/pairing/redeem",
                "path mismatch: got \(url.path) (url=\(url.absoluteString))")

        // Content-Type: application/json.
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json",
                "redeem must set Content-Type application/json, got \(String(describing: request.value(forHTTPHeaderField: "Content-Type")))")

        // Body decodes to exactly {"code": code}.
        let body = try #require(request.httpBody, "expected a JSON body for redeem")
        #expect(Self.bodyIsExactlyCode(body, code),
                "redeem body did not decode to {\"code\": \(code)}")

        // No X-API-Key header, ever.
        #expect(request.value(forHTTPHeaderField: "X-API-Key") == nil,
                "redeem must not carry X-API-Key; got \(String(describing: request.value(forHTTPHeaderField: "X-API-Key")))")
    }
}
