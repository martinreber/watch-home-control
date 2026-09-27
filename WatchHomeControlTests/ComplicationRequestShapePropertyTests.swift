// ComplicationRequestShapePropertyTests.swift
//
// Feature: tv-lamp-complication, Property 4: Complication requests are built
// by the shared builder with the key and body
//
// Validates Requirements 8.5, 8.6, 8.9, 10.4.
//
// Property statement (design › Correctness Properties, Property 4): for
// generated lamp ids and power values, the `GET /lamps` and
// `POST /lamps/{id}/state` requests produced through `RequestBuilder` carry the
// right method, path, `X-API-Key`, `Content-Type: application/json`, and
// `{"power": …}` body.
//
// Pure and deterministic: `RequestBuilder.build` performs no I/O. A
// self-contained RNG drives ≥100 generated (baseURL, apiKey, lamp id, power)
// tuples.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct ComplicationRequestShapePropertyTests {

    private struct SeededRNG: RandomNumberGenerator {
        private var state: UInt64
        init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }
        mutating func next() -> UInt64 {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }

    private static let baseURLs = [
        "https://192.168.1.122:8443",
        "http://10.0.0.5:8080",
        "https://pi.local:8443",
    ]

    private struct LampStateBody: Decodable { let power: Bool }

    @Test("Property 4: GET /lamps and POST /lamps/{id}/state carry the key, header, and body")
    func requestsCarryKeyHeaderAndBody() throws {
        var rng = SeededRNG(seed: 0x8410_D5A9_E7B0_0004)

        for _ in 0..<150 {
            let baseURL = URL(string: ComplicationRequestShapePropertyTests.baseURLs[
                Int.random(in: 0..<ComplicationRequestShapePropertyTests.baseURLs.count, using: &rng)])!
            let apiKey = "key-\(UInt32.random(in: 0...UInt32.max, using: &rng))"
            let lampID = "lamp-\(UInt32.random(in: 0...UInt32.max, using: &rng))"
            let power = Bool.random(using: &rng)

            let builder = RequestBuilder(baseURL: baseURL)

            // GET /lamps
            let lampsRequest = try builder.build(.lamps, apiKey: apiKey)
            #expect(lampsRequest.httpMethod == "GET")
            #expect(lampsRequest.url?.path == "/lamps")
            #expect(lampsRequest.value(forHTTPHeaderField: "X-API-Key") == apiKey)
            #expect(lampsRequest.httpBody == nil)

            // POST /lamps/{id}/state {"power": ...}
            let toggleRequest = try builder.build(.lampState(id: lampID, power: power), apiKey: apiKey)
            #expect(toggleRequest.httpMethod == "POST")
            #expect(toggleRequest.url?.path == "/lamps/\(lampID)/state")
            #expect(toggleRequest.value(forHTTPHeaderField: "X-API-Key") == apiKey)
            #expect(toggleRequest.value(forHTTPHeaderField: "Content-Type") == "application/json")

            let body = try #require(toggleRequest.httpBody)
            let decoded = try JSONDecoder().decode(LampStateBody.self, from: body)
            #expect(decoded.power == power)
        }
    }
}
