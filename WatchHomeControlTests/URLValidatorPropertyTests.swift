// URLValidatorPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 14: URL validation accepts valid
// http(s) URLs and rejects the rest.
//
// Validates Requirements 1.8.
//
// Uses Swift Testing (Apple's first-party framework) with a generator-driven
// approach: custom pseudo-random generators produce a large sample of both
// valid absolute http(s) URLs (varying scheme, host, port, path, query) and a
// variety of invalid inputs (missing scheme, non-http schemes, empty host,
// garbage). Each property runs a minimum of 100 generated iterations.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct URLValidatorPropertyTests {

    // MARK: - Deterministic pseudo-random generator

    /// A tiny, self-contained splitmix64-style generator so cases are
    /// reproducible and require no third-party dependency.
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

    private static let hosts = [
        "192.168.1.122", "10.0.0.1", "example.com", "sub.example.org",
        "home-control.local", "a.b.c.d.example", "localhost", "127.0.0.1",
        "my-pi", "server123", "x.io"
    ]

    private static let paths = [
        "", "/", "/health", "/lamps", "/sonos/speakers",
        "/pairing/redeem", "/a/b/c", "/path-with-dash"
    ]

    private static let queries = ["", "?a=1", "?x=1&y=2", "?flag", "?q=hello%20world"]

    private static let ports: [Int?] = [nil, 80, 443, 8080, 8082, 1, 65535]

    private static let httpSchemes = ["http", "https", "HTTP", "HTTPS", "HttP", "hTTps"]

    /// Produces a syntactically valid absolute http/https URL string with a host.
    private static func makeValidURLString(_ rng: inout RNG) -> String {
        let scheme = rng.pick(httpSchemes)
        let host = rng.pick(hosts)
        let port = rng.pick(ports)
        let path = rng.pick(paths)
        let query = rng.pick(queries)

        var s = "\(scheme)://\(host)"
        if let port { s += ":\(port)" }
        s += path
        s += query
        return s
    }

    private static let nonHTTPSchemes = ["ftp", "file", "mailto", "ssh", "ws", "wss", "tel", "data"]

    private enum InvalidKind: CaseIterable {
        case noScheme
        case nonHTTPScheme
        case emptyHost
        case garbage
        case schemeOnly
    }

    /// Produces an input that must be rejected with `.invalidURL`.
    private static func makeInvalidURLString(_ rng: inout RNG) -> String {
        switch rng.pick(InvalidKind.allCases) {
        case .noScheme:
            // A bare host / path without any scheme.
            let host = rng.pick(hosts)
            let path = rng.pick(paths)
            return host + path
        case .nonHTTPScheme:
            let scheme = rng.pick(nonHTTPSchemes)
            let host = rng.pick(hosts)
            return "\(scheme)://\(host)"
        case .emptyHost:
            // Valid http scheme but no host (authority absent).
            let scheme = rng.pick(["http", "https"])
            let path = rng.pick(["", "/", "/health", "/x"])
            return "\(scheme):\(path)"
        case .garbage:
            let bits = ["", " ", "not a url", "://", "http//host", "12345",
                        "http:// space.com", "???", "\n", "http:"]
            return rng.pick(bits)
        case .schemeOnly:
            let scheme = rng.pick(["http", "https"])
            return "\(scheme)://"
        }
    }

    // MARK: - Property 14

    @Test("Property 14: valid absolute http(s) URLs with a host are accepted")
    func acceptsValidHTTPURLs() {
        var rng = RNG(seed: 0xF14_ACCE_9701_1DEA)
        var checked = 0
        for _ in 0..<150 {
            let raw = URLValidatorPropertyTests.makeValidURLString(&rng)
            checked += 1
            switch URLValidator.validate(raw) {
            case .success(let url):
                // The parsed URL preserves an http(s) scheme and a host.
                let scheme = url.scheme?.lowercased()
                #expect(scheme == "http" || scheme == "https",
                        "expected http(s) scheme for \(raw), got \(String(describing: url.scheme))")
                #expect(!(url.host?.isEmpty ?? true),
                        "expected non-empty host for \(raw)")
            case .failure(let error):
                Issue.record("expected success for valid URL \(raw), got .failure(\(error))")
            }
        }
        #expect(checked >= 100)
    }

    @Test("Property 14: inputs without a valid http(s) scheme+host are rejected")
    func rejectsInvalidInputs() {
        var rng = RNG(seed: 0xBAD_C0DE_1408_F00D)
        var checked = 0
        for _ in 0..<150 {
            let raw = URLValidatorPropertyTests.makeInvalidURLString(&rng)
            checked += 1
            switch URLValidator.validate(raw) {
            case .success(let url):
                Issue.record("expected .invalidURL for \(raw), got .success(\(url))")
            case .failure(let error):
                #expect(error == .invalidURL,
                        "expected .invalidURL for \(raw), got \(error)")
            }
        }
        #expect(checked >= 100)
    }
}
