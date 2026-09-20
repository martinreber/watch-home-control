// BlindFlowExampleTests.swift
//
// Feature: apple-watch-home-control — example (unit) tests for the blind
// (Storen) command flow driven by BlindViewModel.
//
// These are deterministic example tests (not property tests): each case seeds a
// configurable MockAPIClient and asserts an exact BlindViewModel outcome
// (pending flag transitions + German feedback).
//
// Validates Requirements:
//   - 4.4  WHILE a blind command is in flight -> Pending_State is set (isPending == true).
//   - 4.5  success response -> clear Pending_State, re-enable, German success feedback.
//   - 4.6  error response   -> clear Pending_State, re-enable, German error feedback.
//   - 4.7  no completion within 10s (timeout) -> abort, clear Pending_State, German timeout feedback.
//
// BlindViewModel API driven:
//   - move(_:)     — sends POST /blind for .up ("Hoch") / .down ("Runter"),
//                    sets isPending for the duration, clears it on completion,
//                    and sets feedback (success / error / timeout).
//   - isPending    — the Pending_State flag both controls bind to (Req 4.4).
//   - feedback     — the German success/error/timeout banner (Req 4.5–4.7).
//
// Doubles (mirroring the sibling *ExampleTests / *PropertyTests convention): a
// configurable MockAPIClient whose `moveBlind` can succeed, throw a specific
// APIError, or block on a continuation so the in-flight Pending_State can be
// observed before the call completes. Every other APIClient method traps — the
// blind flow only touches `moveBlind`. No device, network, or Backend
// involvement; outcomes are exact and reproducible.

import Testing
import Foundation
@testable import WatchHomeControl_Watch_App

struct BlindFlowExampleTests {

    // MARK: - Test double

    /// An `APIClient` whose `moveBlind` behaviour is configurable per test.
    /// Only `moveBlind` is exercised by the blind flow; every other method
    /// traps to prove it is never reached.
    private final class MockAPIClient: APIClient, @unchecked Sendable {
        enum BlindBehavior {
            case success              // resolves without throwing (Req 4.5)
            case throwing(APIError)   // throws the given error (Req 4.6/4.7)
        }

        let behavior: BlindBehavior

        /// Records the last action passed to `moveBlind`, so tests can assert
        /// "Hoch" -> .up and "Runter" -> .down (Req 4.2/4.3 direction wiring).
        private(set) var lastAction: BlindAction?
        /// Number of times `moveBlind` was invoked.
        private(set) var moveCallCount = 0

        /// Optional gate: when set, `moveBlind` suspends on this stream until the
        /// test resumes it. Lets a test observe the in-flight Pending_State
        /// (Req 4.4) deterministically without sleeps.
        private let gate: AsyncStream<Void>?
        private let gateReady: (@Sendable () -> Void)?

        init(
            behavior: BlindBehavior,
            gate: AsyncStream<Void>? = nil,
            gateReady: (@Sendable () -> Void)? = nil
        ) {
            self.behavior = behavior
            self.gate = gate
            self.gateReady = gateReady
        }

        func moveBlind(_ action: BlindAction, timeout: Duration) async throws {
            moveCallCount += 1
            lastAction = action

            // If a gate is configured, signal that the call is now in flight and
            // wait for the test to release it before completing.
            if let gate {
                gateReady?()
                var iterator = gate.makeAsyncIterator()
                _ = await iterator.next()
            }

            switch behavior {
            case .success:
                return
            case .throwing(let error):
                throw error
            }
        }

        // Not part of the blind flow — never called here.
        func checkHealth(timeout: Duration) async throws -> Bool {
            Issue.record("checkHealth must not be called by the blind flow"); return true
        }
        func fetchLamps(timeout: Duration) async throws -> [LampDTO] {
            Issue.record("fetchLamps must not be called by the blind flow"); return []
        }
        func setLampState(id: String, power: Bool, timeout: Duration) async throws -> LampDTO {
            Issue.record("setLampState must not be called by the blind flow")
            throw APIError.decoding
        }
        func fetchSpeakers(timeout: Duration) async throws -> [SpeakerDTO] {
            Issue.record("fetchSpeakers must not be called by the blind flow"); return []
        }
        func playSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("playSpeaker must not be called by the blind flow")
            throw APIError.decoding
        }
        func pauseSpeaker(id: String, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("pauseSpeaker must not be called by the blind flow")
            throw APIError.decoding
        }
        func playRadio(id: String, request: RadioRequest, timeout: Duration) async throws -> SpeakerDTO {
            Issue.record("playRadio must not be called by the blind flow")
            throw APIError.decoding
        }
        func redeemPairingCode(_ code: String, timeout: Duration) async throws -> String {
            Issue.record("redeemPairingCode must not be called by the blind flow")
            throw APIError.unauthorized
        }
    }

    // MARK: - Success flow (Req 4.5)

    @Test("Req 4.5: sending Hoch (.up) succeeds -> calls moveBlind(.up), German success feedback, pending cleared")
    @MainActor
    func upSuccessSurfacesSuccessAndClearsPending() async {
        let api = MockAPIClient(behavior: .success)
        let model = BlindViewModel(api: api)

        await model.move(.up)

        #expect(api.moveCallCount == 1, "Hoch must issue exactly one POST /blind (Req 4.2)")
        #expect(api.lastAction == .up, "the Hoch control must send action .up (Req 4.2)")
        #expect(model.feedback == Feedback(kind: .success, message: Strings.commandSuccess),
                "a success response must surface German success feedback (Req 4.5)")
        #expect(model.isPending == false,
                "Pending_State must be cleared after completion so both controls re-enable (Req 4.5)")
    }

    @Test("Req 4.5: sending Runter (.down) succeeds -> calls moveBlind(.down), German success feedback, pending cleared")
    @MainActor
    func downSuccessSurfacesSuccessAndClearsPending() async {
        let api = MockAPIClient(behavior: .success)
        let model = BlindViewModel(api: api)

        await model.move(.down)

        #expect(api.moveCallCount == 1, "Runter must issue exactly one POST /blind (Req 4.3)")
        #expect(api.lastAction == .down, "the Runter control must send action .down (Req 4.3)")
        #expect(model.feedback == Feedback(kind: .success, message: Strings.commandSuccess),
                "a success response must surface German success feedback (Req 4.5)")
        #expect(model.isPending == false,
                "Pending_State must be cleared after completion so both controls re-enable (Req 4.5)")
    }

    // MARK: - Error flow (Req 4.6)

    @Test("Req 4.6: a failed command (non-timeout APIError) surfaces the German error feedback and clears pending")
    @MainActor
    func errorSurfacesErrorFeedbackAndClearsPending() async {
        // A generic backend failure (HTTP 500) — anything that is NOT .timeout
        // must map to the generic German error feedback (Req 4.6).
        let api = MockAPIClient(behavior: .throwing(.http(status: 500)))
        let model = BlindViewModel(api: api)

        await model.move(.up)

        #expect(api.moveCallCount == 1)
        #expect(model.feedback == Feedback(kind: .error, message: Strings.commandError),
                "an error response must surface German error feedback (Req 4.6)")
        #expect(model.isPending == false,
                "Pending_State must be cleared after a failure so both controls re-enable (Req 4.6)")
    }

    @Test("Req 4.6: a network failure surfaces German error feedback and clears pending (does not crash)")
    @MainActor
    func networkErrorSurfacesErrorFeedbackAndClearsPending() async {
        let api = MockAPIClient(behavior: .throwing(.network("connection refused")))
        let model = BlindViewModel(api: api)

        await model.move(.down)

        #expect(model.feedback == Feedback(kind: .error, message: Strings.commandError),
                "a network failure must surface German error feedback (Req 4.6)")
        #expect(model.isPending == false,
                "Pending_State must be cleared after a failure (Req 4.6)")
    }

    // MARK: - Timeout flow (Req 4.7)

    @Test("Req 4.7: a command that times out surfaces the German timeout feedback and clears pending")
    @MainActor
    func timeoutSurfacesTimeoutFeedbackAndClearsPending() async {
        let api = MockAPIClient(behavior: .throwing(.timeout))
        let model = BlindViewModel(api: api)

        await model.move(.up)

        #expect(model.feedback == Feedback(kind: .error, message: Strings.commandTimeout),
                "a timeout must surface the German timeout feedback (Req 4.7)")
        #expect(model.isPending == false,
                "Pending_State must be cleared after a timeout so both controls re-enable (Req 4.7)")
    }

    // MARK: - In-flight Pending_State (Req 4.4)

    @Test("Req 4.4: the Pending_State is set while the command is in flight and cleared afterward")
    @MainActor
    func pendingIsSetDuringFlightAndClearedAfter() async {
        // Gate the mock so `moveBlind` blocks until the test releases it. This
        // lets us observe `isPending == true` while the call is genuinely in
        // flight — a deterministic check with no sleeps.
        var continuation: AsyncStream<Void>.Continuation!
        let gate = AsyncStream<Void> { continuation = $0 }

        // Signalled (via a confirmation) once `moveBlind` has started and is
        // waiting on the gate.
        await confirmation("moveBlind reaches the in-flight gate") { inFlight in
            let api = MockAPIClient(behavior: .success, gate: gate, gateReady: { inFlight() })
            let model = BlindViewModel(api: api)

            // Precondition: nothing pending before we start.
            #expect(model.isPending == false)

            // Launch the command; it will suspend inside `moveBlind` on the gate.
            let task = Task { @MainActor in await model.move(.up) }

            // Yield until the model has entered its in-flight state. `move`
            // sets `isPending = true` synchronously before awaiting the client,
            // so once the task has had a chance to run this holds.
            while model.isPending == false {
                await Task.yield()
            }

            #expect(model.isPending == true,
                    "Pending_State must be set while the blind command is in flight (Req 4.4)")

            // Release the gate so the in-flight call can complete, then wait for
            // the command to finish.
            continuation.yield()
            continuation.finish()
            await task.value
        }

        // (Post-completion clearing is asserted by the success/error/timeout
        // cases above; here we only need the in-flight observation.)
    }
}
