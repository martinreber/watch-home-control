// RequestBuilderPropertyTests.swift
//
// Feature: apple-watch-home-control, Property 1: Request building maps every
// endpoint to the correct URL, method, path, body, and Content-Type.
//
// Validates Requirements 4.2, 4.3, 6.1, 6.2, 11.1, 11.3.
//
// Uses Swift Testing (Apple's first-party framework) with a generator-driven
// approach: a deterministic, seedable splitmix64 RNG samples the full space of
// (Base_URL × Endpoint) ≥100 times. For each sample the test asserts that the
// `URLRequest` produced by `RequestBuilder` has:
//   - an absolute URL beginning with the configured Base_URL,
//   - the endpoint's exact path,
//   - the endpoint's exact HTTP method,
//   - for body-bearing endpoints: a JSON body decoding back to the payload and a
//     `Content-Type: application/json` header,
//   - for bodyless endpoints: no `Content-Type: application/json` header and no body.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct RequestBuilderPropertyTests {

    // MARK: - Deterministic pseudo-random generator

    /// A tiny, self-contained splitmix64-style generator so cases are
    /// reproducible and require no third-party dependency. Conforms to
    /// `RandomNumberGenerator` so it can drive `randomElement(using:)`.
    private struct RNG: RandomNumberGenerator {
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

    // MARK: - Base_URL generators

    /// A pool of plausible Base_URLs: LAN IPs, host names, ports, and Base_URLs
    /// that themselves carry a trailing path (to exercise relative resolution).
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

    // MARK: - Endpoint model

    /// Description of an endpoint's expected wire shape, used as an independent
    /// oracle against the built `URLRequest`.
    private struct Expectation {
        let endpoint: Endpoint
        let method: String
        /// The endpoint's decoded (semantic) path — what `URL.path` returns after
        /// percent-decoding, e.g. `/sonos/speakers/id with space/play`.
        let path: String
        /// The percent-encoded path as it appears on the wire (in
        /// `URL.absoluteString`), e.g. `/sonos/speakers/id%20with%20space/play`.
        let encodedPath: String
        /// When non-nil, the endpoint carries a JSON body equal to this value
        /// (compared by re-decoding the built request's body).
        let bodyCheck: (Data) -> Bool
        /// Whether a body (and `Content-Type: application/json`) is expected.
        let hasBody: Bool
    }

    /// Sonos-style ids and lamp ids, including ones needing percent-encoding.
    /// (A literal `/` is intentionally excluded: it is a path separator, not a
    /// character an id would legitimately contain.)
    private static let ids = [
        "lamp1", "kitchen", "RINCON_1234567890AB01400",
        "wohnzimmer", "id with space", "äöü-umlaut"
    ]

    /// Generates a random endpoint together with its expected wire shape.
    private static func makeEndpoint(_ rng: inout RNG) -> Expectation {
        enum Kind: CaseIterable {
            case health, blind, lamps, lampState, speakers
            case speakerPlay, speakerPause, speakerRadio, redeem
        }

        switch rng.pick(Kind.allCases) {
        case .health:
            return Expectation(
                endpoint: .health,
                method: "GET",
                path: "/health",
                encodedPath: "/health",
                bodyCheck: { $0.isEmpty },
                hasBody: false
            )

        case .blind:
            let action: BlindAction = rng.bool() ? .up : .down
            return Expectation(
                endpoint: .blind(action),
                method: "POST",
                path: "/blind",
                encodedPath: "/blind",
                bodyCheck: { data in
                    guard let obj = try? JSONDecoder().decode([String: String].self, from: data) else { return false }
                    return obj == ["action": action.rawValue]
                },
                hasBody: true
            )

        case .lamps:
            return Expectation(
                endpoint: .lamps,
                method: "GET",
                path: "/lamps",
                encodedPath: "/lamps",
                bodyCheck: { $0.isEmpty },
                hasBody: false
            )

        case .lampState:
            let id = rng.pick(ids)
            let power = rng.bool()
            return Expectation(
                endpoint: .lampState(id: id, power: power),
                method: "POST",
                path: "/lamps/\(id)/state",
                encodedPath: "/lamps/\(pathEscaped(id))/state",
                bodyCheck: { data in
                    guard let obj = try? JSONDecoder().decode([String: Bool].self, from: data) else { return false }
                    return obj == ["power": power]
                },
                hasBody: true
            )

        case .speakers:
            return Expectation(
                endpoint: .speakers,
                method: "GET",
                path: "/sonos/speakers",
                encodedPath: "/sonos/speakers",
                bodyCheck: { $0.isEmpty },
                hasBody: false
            )

        case .speakerPlay:
            let id = rng.pick(ids)
            return Expectation(
                endpoint: .speakerPlay(id: id),
                method: "POST",
                path: "/sonos/speakers/\(id)/play",
                encodedPath: "/sonos/speakers/\(pathEscaped(id))/play",
                bodyCheck: { $0.isEmpty },
                hasBody: false
            )

        case .speakerPause:
            let id = rng.pick(ids)
            return Expectation(
                endpoint: .speakerPause(id: id),
                method: "POST",
                path: "/sonos/speakers/\(id)/pause",
                encodedPath: "/sonos/speakers/\(pathEscaped(id))/pause",
                bodyCheck: { $0.isEmpty },
                hasBody: false
            )

        case .speakerRadio:
            let id = rng.pick(ids)
            let request = RadioRequest.radioBern1
            return Expectation(
                endpoint: .speakerRadio(id: id, request),
                method: "POST",
                path: "/sonos/speakers/\(id)/radio",
                encodedPath: "/sonos/speakers/\(pathEscaped(id))/radio",
                bodyCheck: { data in
                    guard let decoded = try? JSONDecoder().decode(RadioRequest.self, from: data) else { return false }
                    return decoded == request
                },
                hasBody: true
            )

        case .redeem:
            let code = String(format: "%06d", rng.int(0..<1_000_000))
            return Expectation(
                endpoint: .redeem(code: code),
                method: "POST",
                path: "/pairing/redeem",
                encodedPath: "/pairing/redeem",
                bodyCheck: { data in
                    guard let obj = try? JSONDecoder().decode([String: String].self, from: data) else { return false }
                    return obj == ["code": code]
                },
                hasBody: true
            )
        }
    }

    /// Mirrors `RequestBuilder.pathEscaped` so the oracle predicts the exact
    /// percent-encoded path segment.
    private static func pathEscaped(_ segment: String) -> String {
        segment.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? segment
    }

    // MARK: - Property 1

    @Test("Property 1: request building maps every endpoint to the correct URL, method, path, body, and Content-Type")
    func mapsEveryEndpointCorrectly() throws {
        var rng = RNG(seed: 0x0001_ACE0_BEEF_CAFE)
        let iterations = 200
        var checked = 0

        for _ in 0..<iterations {
            let baseURLString = Self.baseURLStrings.randomElement(using: &rng)!
            let baseURL = try #require(URL(string: baseURLString), "invalid Base_URL fixture \(baseURLString)")
            let expectation = Self.makeEndpoint(&rng)

            let builder = RequestBuilder(baseURL: baseURL)
            let request = try builder.build(expectation.endpoint, apiKey: "dummy-key")

            // The request must carry an absolute URL.
            let url = try #require(request.url, "expected a URL for \(expectation.path)")

            // The absolute URL begins with the Base_URL: same scheme, host, and
            // port form the shared prefix (a trailing slash on the Base_URL is
            // absorbed by relative resolution).
            let origin = "\(baseURL.scheme ?? "")://\(baseURL.host ?? "")" +
                (baseURL.port.map { ":\($0)" } ?? "")
            #expect(url.absoluteString.hasPrefix(origin),
                    "expected \(url.absoluteString) to begin with Base_URL origin \(origin)")

            // Absolute URL begins with the Base_URL's scheme + host (+ port).
            #expect(url.scheme?.lowercased() == baseURL.scheme?.lowercased(),
                    "scheme mismatch for \(url.absoluteString)")
            #expect(url.host == baseURL.host, "host mismatch for \(url.absoluteString)")
            #expect(url.port == baseURL.port, "port mismatch for \(url.absoluteString)")

            // Exact path: `URL.path` returns the percent-decoded (semantic) path.
            #expect(url.path == expectation.path,
                    "path mismatch: got \(url.path), expected \(expectation.path) (url=\(url.absoluteString))")

            // On the wire, the path is percent-encoded within the absolute URL.
            #expect(url.absoluteString.contains(expectation.encodedPath),
                    "expected \(url.absoluteString) to contain encoded path \(expectation.encodedPath)")

            // Exact HTTP method.
            #expect(request.httpMethod == expectation.method,
                    "method mismatch for \(expectation.path): got \(String(describing: request.httpMethod)), expected \(expectation.method)")

            // Body + Content-Type handling.
            let contentType = request.value(forHTTPHeaderField: "Content-Type")
            let body = request.httpBody ?? Data()

            if expectation.hasBody {
                #expect(contentType == "application/json",
                        "expected application/json Content-Type for \(expectation.path), got \(String(describing: contentType))")
                #expect(!body.isEmpty, "expected a non-empty JSON body for \(expectation.path)")
                #expect(expectation.bodyCheck(body),
                        "body did not decode back to the expected payload for \(expectation.path)")
            } else {
                #expect(contentType != "application/json",
                        "did not expect a JSON Content-Type for bodyless \(expectation.path), got \(String(describing: contentType))")
                #expect(body.isEmpty, "expected no body for \(expectation.path)")
            }

            checked += 1
        }

        #expect(checked >= 100, "expected at least 100 property iterations, ran \(checked)")
    }
}
