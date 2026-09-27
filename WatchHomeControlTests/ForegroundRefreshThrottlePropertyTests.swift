// ForegroundRefreshThrottlePropertyTests.swift
//
// Feature: tv-lamp-complication, Property 7: Foreground refresh is emitted
// only on change and at most once per interval
//
// Validates Requirements 3.14, 7.12, 7.13.
//
// Property statement (design › Correctness Properties, Property 7): for
// generated sequences of (timestamp, power) samples, `ComplicationPublisher`
// triggers no reload when the power is unchanged, and never more than one
// reload per 10-second window; each observed change eventually produces
// exactly one reload.
//
// Deterministic: a virtual clock (`currentTime`, advanced by the test rather
// than by sleeping) drives `ComplicationPublisher`'s injected `now`. A
// self-contained RNG drives ≥100 generated samples per run across several
// independent runs.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct ForegroundRefreshThrottlePropertyTests {

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

    /// Records the simulated `now()` at every `reload()` call.
    private final class TimestampedSpy: ComplicationRefreshing, @unchecked Sendable {
        private(set) var reloadTimes: [Date] = []
        let now: () -> Date
        init(now: @escaping () -> Date) { self.now = now }
        func reload() { reloadTimes.append(now()) }
    }

    private static func randomPower(_ rng: inout SeededRNG) -> Bool? {
        switch Int.random(in: 0..<3, using: &rng) {
        case 0: return true
        case 1: return false
        default: return nil
        }
    }

    @Test("Property 7: no reload on unchanged power, never more than one reload per 10s window")
    @MainActor
    func throttlesToAtMostOnePerIntervalAndOnlyOnChange() {
        var rng = SeededRNG(seed: 0x7EF7_E5F7_04D7_0007)

        for run in 0..<10 {
            var currentTime = Date(timeIntervalSince1970: 1_700_000_000 + Double(run) * 100_000)
            let spy = TimestampedSpy(now: { currentTime })
            let publisher = ComplicationPublisher(
                refresher: spy, minimumInterval: .seconds(10), now: { currentTime })

            var lastSample: Bool?
            var everChanged = false

            for _ in 0..<150 {
                // Advance the virtual clock by 0...15s per sample so both
                // within-window and past-window gaps are exercised.
                currentTime = currentTime.addingTimeInterval(Double(Int.random(in: 0...15, using: &rng)))
                let sample = ForegroundRefreshThrottlePropertyTests.randomPower(&rng)
                if sample != lastSample { everChanged = true }
                lastSample = sample

                publisher.publish(tvLampPower: sample)
            }

            // Let a throttled trailing change settle: keep reporting the final
            // sample while advancing the clock past the interval, exactly as
            // the real 5s Poll_Cycle would on subsequent calls.
            for _ in 0..<3 {
                currentTime = currentTime.addingTimeInterval(10)
                publisher.publish(tvLampPower: lastSample)
            }

            // No two reloads occur within the same 10-second window.
            for i in 1..<spy.reloadTimes.count {
                let gap = spy.reloadTimes[i].timeIntervalSince(spy.reloadTimes[i - 1])
                #expect(gap >= 10, "reloads \(i - 1) and \(i) are only \(gap)s apart in run \(run)")
            }

            // Every observed change is eventually reflected: once the sequence
            // settles, the publisher's tracked state matches the final sample.
            #expect(publisher.lastPublishedPower == lastSample)

            // If the power ever changed, at least one reload must have fired.
            if everChanged {
                #expect(!spy.reloadTimes.isEmpty, "expected at least one reload in run \(run)")
            }
        }
    }

    @Test("Property 7: a stable, unchanging power after the first publish triggers no further reloads")
    @MainActor
    func stablePowerReloadsExactlyOnce() {
        var currentTime = Date(timeIntervalSince1970: 1_700_000_000)
        let spy = SpyComplicationRefresher()
        let publisher = ComplicationPublisher(
            refresher: spy, minimumInterval: .seconds(10), now: { currentTime })

        for _ in 0..<20 {
            currentTime = currentTime.addingTimeInterval(5)
            publisher.publish(tvLampPower: true)
        }

        // The first call always reaches the face; every later call reports the
        // same value, so no further reload is ever needed.
        #expect(spy.reloadCount == 1)
    }
}
