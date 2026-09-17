// Views/SetupView.swift — Setup_Screen for Base_URL + Pairing_Code entry.
//
// `SetupView` is the single screen used for the three setup situations the
// design calls out (design › Views table): initial configuration, a later
// Base_URL/Pairing_Code change via the config affordance, and re-pairing after
// an Auth_Error. It presents a Base_URL input pre-filled from
// `AppModel.baseURLField` (Req 1.2 / 1.7 / 1.10), a 6-digit numeric Pairing_Code
// input (Req 1.3), and a save action that validates the inputs and redeems the
// code via `AppModel.submitSetup` (Req 1.4–1.6, 1.8, 2.5, 12).
//
// Validation and redeem failures surface as inline German messages
// (Req 1.5 / 1.8 / 12.3–12.6):
//   - `.malformedCode`   → "Code muss 6 Ziffern haben"     (Strings.codeMustBeSixDigits)
//   - `.invalidURL`      → "Ungültige Adresse"             (Strings.invalidURL)
//   - `.codeInvalid`     → "Code ungültig oder abgelaufen" (Strings.codeInvalidOrExpired)
//   - `.tooManyAttempts` → "Zu viele Versuche"             (Strings.tooManyAttempts)
//   - `.redeemTimeout`   → "Zeitüberschreitung beim Koppeln" (Strings.redeemTimeout)
//   - `.redeemFailed`    → "Koppeln fehlgeschlagen"        (Strings.redeemFailed)
//
// When `AppModel.authErrorMessage` is set (HTTP 401 re-entry, Req 2.4), the
// German "API-Key ungültig" banner is shown at the top of the form so the screen
// can be reused for re-pairing after an Auth_Error (Req 2.4). On a successful
// submission `AppModel` clears that banner and routes to Control, so the view
// does not need to dismiss itself explicitly.

import SwiftUI

/// The Setup_Screen: Base_URL + Pairing_Code inputs with validation and save.
///
/// Reused for initial setup, config changes, and Auth_Error re-pairing. Local
/// `@State` backs the two text fields; the Base_URL field is seeded from
/// `AppModel.baseURLField` (the persisted/default value), while the Pairing_Code
/// field always starts empty — a code is short-lived and never surfaced back
/// into the UI (Req 2.2).
struct SetupView: View {
    /// The root view model. Bindable so `authErrorMessage`/`baseURLField`
    /// changes (e.g. from `openConfig()` / `handleAuthError()`) stay observed.
    @Bindable var model: AppModel

    /// Base_URL input, seeded from the persisted/default Base_URL (Req 1.2/1.7).
    @State private var baseURL: String

    /// Pairing_Code input buffer. Entered exclusively through the in-view number
    /// pad (`CodePad`), never a keyboard, so it can only ever contain decimal
    /// digits. A `String` (not an `Int`) so leading zeros are preserved verbatim
    /// (e.g. "000123"). Always starts empty — a code is short-lived and never
    /// surfaced back into the UI (Req 2.2).
    ///
    /// A number pad is used instead of a `TextField` because watchOS ignores
    /// `.keyboardType`/`.textContentType` and always opens the letter
    /// keyboard/Scribble for a text field, which cannot be forced to digits.
    @State private var code: String = ""

    /// Inline German validation/redeem error, or `nil` when the last submission
    /// was clean / not yet attempted (Req 1.5/1.8/12.3–12.6).
    @State private var errorMessage: String?

    /// A Pairing_Code is exactly six decimal digits, so the input is capped here.
    private static let codeLength = 6

    init(model: AppModel) {
        self.model = model
        _baseURL = State(initialValue: model.baseURLField)
    }

    var body: some View {
        Form {
            // Auth_Error banner: shown when re-pairing was triggered by an HTTP
            // 401 (Req 2.3/2.4). Sits above the inputs so it is visible first and
            // lets this screen double as the re-pair surface.
            if let authError = model.authErrorMessage {
                Section {
                    Text(authError)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            // Base_URL input, pre-filled with the current/default value.
            Section(Strings.baseURLLabel) {
                TextField(Strings.baseURLLabel, text: $baseURL)
                    .textContentType(.URL)
                    .autocorrectionDisabled()
            }

            // Pairing_Code input: a 6-digit code entered via an in-view number
            // pad (Req 1.3). A custom pad is used instead of a `TextField`
            // because watchOS always opens the letter keyboard/Scribble for a
            // text field and ignores `.keyboardType`/`.textContentType`, so a
            // digits-only keyboard cannot be requested. The pad appends digits and
            // supports delete, capping the buffer at six digits, so `code` only
            // ever holds a well-formed prefix of a Pairing_Code.
            Section(Strings.pairingCodeLabel) {
                CodePad(code: $code, length: Self.codeLength)
            }

            // Inline validation / redeem error (malformed code, invalid URL,
            // rejected / rate-limited / timed-out / failed redeem).
            if let errorMessage {
                Section {
                    Text(errorMessage)
                        .font(.footnote)
                        .foregroundStyle(.red)
                }
            }

            Section {
                Button(Strings.save, action: save)

                // Cancel is only offered once a credential is already stored, so
                // the user can back out of a config change / re-pair without
                // altering anything. On the very first launch there is no
                // configured control screen to return to, so the button is hidden
                // and the user must complete pairing.
                if model.canCancelSetup {
                    Button(Strings.cancel, role: .cancel) {
                        model.cancelSetup()
                    }
                }
            }
        }
        .navigationTitle(Strings.setupTitle)
    }

    /// Validates the entered Base_URL + Pairing_Code and redeems the code via
    /// `AppModel.submitSetup`. On failure the matching German message is shown
    /// inline; on success the error is cleared (routing to Control is handled by
    /// `AppModel`).
    private func save() {
        // `code` comes straight from the number pad, so it is already a
        // digits-only string with leading zeros preserved. `AppModel.submitSetup`
        // remains the single source of truth for validation (exactly 6 digits).
        Task {
            switch await model.submitSetup(baseURL: baseURL, code: code) {
            case .success:
                errorMessage = nil
            case .failure(let error):
                errorMessage = Self.message(for: error)
            }
        }
    }

    /// Maps a `SetupError` to its German inline message (Req 1.5/1.8, 12.3–12.6).
    private static func message(for error: SetupError) -> String {
        switch error {
        case .malformedCode:
            return Strings.codeMustBeSixDigits
        case .invalidURL:
            return Strings.invalidURL
        case .codeInvalid:
            return Strings.codeInvalidOrExpired
        case .tooManyAttempts:
            return Strings.tooManyAttempts
        case .redeemTimeout:
            return Strings.redeemTimeout
        case .redeemFailed:
            return Strings.redeemFailed
        }
    }
}

/// A digits-only entry pad for the Pairing_Code.
///
/// watchOS opens the letter keyboard/Scribble for any `TextField` and ignores
/// `.keyboardType`, so a code that must be numeric is entered here instead. The
/// pad shows the current entry as a fixed row of `length` slots, a 1–9 / 0 grid,
/// and a delete key. Digits are appended to `code` until it reaches `length`
/// digits; delete removes the last one. Because entry is button-driven, `code`
/// can only ever contain decimal digits, and leading zeros are preserved.
private struct CodePad: View {
    /// The bound code buffer. Only ever mutated to a digits-only string of at
    /// most `length` characters.
    @Binding var code: String

    /// The exact number of digits a complete code has (6).
    let length: Int

    // Key-pad sizing. The digit keys are reduced ~20% from the original 32pt
    // height so more of the pad and the entry slots fit on the watch screen.
    // The `.bordered` style adds its own padding, so the keys use a custom
    // background with a controlled height/padding to make the reduction real.
    private static let keyHeight: CGFloat = 26      // was 32 (~20% smaller)
    private static let keyFontSize: CGFloat = 17    // was ~20 (.title3) (~15% smaller)
    private static let keySpacing: CGFloat = 5      // was 6
    private static let slotHeight: CGFloat = 22     // entry slots kept at original size

    /// The pad layout: rows of digit labels; "" is a spacer, "⌫" is delete.
    private let rows: [[String]] = [
        ["1", "2", "3"],
        ["4", "5", "6"],
        ["7", "8", "9"],
        ["", "0", "⌫"],
    ]

    var body: some View {
        VStack(spacing: 6) {
            // Current entry: one box per slot, filled left-to-right as digits are
            // entered. Shows the digits in plain text (a Pairing_Code is not
            // secret once displayed on the create call) so the user can verify it.
            HStack(spacing: 4) {
                ForEach(0..<length, id: \.self) { index in
                    let digit = index < code.count
                        ? String(Array(code)[index])
                        : ""
                    Text(digit)
                        .font(.system(.body, design: .monospaced))
                        .frame(maxWidth: .infinity, minHeight: Self.slotHeight)
                        .background(.gray.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
                }
            }

            // Digit grid + delete.
            ForEach(rows.indices, id: \.self) { rowIndex in
                HStack(spacing: Self.keySpacing) {
                    ForEach(rows[rowIndex].indices, id: \.self) { colIndex in
                        let label = rows[rowIndex][colIndex]
                        keyButton(label)
                    }
                }
            }
        }
        .padding(.vertical, 3)
    }

    /// Builds one pad key. Empty labels render as an invisible spacer so the grid
    /// stays aligned; "⌫" deletes the last digit; a digit label appends.
    @ViewBuilder
    private func keyButton(_ label: String) -> some View {
        if label.isEmpty {
            // Spacer cell keeps the 0 centered in the last row.
            Color.clear
                .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
        } else {
            Button {
                if label == "⌫" {
                    deleteLast()
                } else {
                    append(label)
                }
            } label: {
                // A `.plain` button with an explicit background gives full
                // control over the key footprint; `.bordered` adds its own
                // padding which prevents the height reduction from taking effect.
                Text(label)
                    .font(.system(size: Self.keyFontSize, design: .rounded))
                    .minimumScaleFactor(0.7)
                    .frame(maxWidth: .infinity, minHeight: Self.keyHeight)
                    .background(.gray.opacity(0.3), in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(RoundedRectangle(cornerRadius: 6))
            }
            .buttonStyle(.plain)
        }
    }

    /// Appends a single digit while the buffer is short of `length` digits.
    private func append(_ digit: String) {
        guard code.count < length else { return }
        code.append(digit)
    }

    /// Removes the last entered digit, if any.
    private func deleteLast() {
        guard !code.isEmpty else { return }
        code.removeLast()
    }
}
