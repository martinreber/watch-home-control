import Foundation

/// German user-facing label constants for the entire app.
///
/// All strings the UI presents to the user are centralized here so the views,
/// view models, and error mappers reference a single source of truth. The app's
/// UI language is German (Requirement 10.1); the section titles and blind
/// controls "Storen", "Lampen", "Sonos", "Hoch", and "Runter" are the required
/// minimum, with the remaining strings covering setup, empty states, and
/// command/refresh feedback.
enum Strings {
    /// App title shown in the control screen / navigation.
    static let appTitle = "Home Control"

    // MARK: - Section titles (Requirement 10.1)

    /// Blind (roller shutter) section title — German for "blinds".
    static let sectionBlinds = "Storen"
    /// Lamp section title.
    static let sectionLamps = "Lampen"
    /// Speaker section title.
    static let sectionSpeakers = "Sonos"

    // MARK: - Blind controls (Requirement 4.1, 10.1)

    /// Raise the blinds ("up").
    static let blindUp = "Hoch"
    /// Lower the blinds ("down").
    static let blindDown = "Runter"

    // MARK: - Empty states (Requirements 5.6, 7.8)

    /// Shown when the lamp list is empty.
    static let lampsEmpty = "Keine Lampen gefunden"
    /// Shown when the speaker list is empty.
    static let speakersEmpty = "Keine Lautsprecher gefunden"

    // MARK: - Health / connectivity (Requirements 3.3, 3.4)

    /// Health check failed — Backend unreachable.
    static let backendUnreachable = "Backend nicht erreichbar"
    /// Retry affordance for a failed health check.
    static let retry = "Erneut versuchen"

    // MARK: - Authentication / setup errors (Requirements 1.5, 1.8, 2.3, 2.4)

    /// HTTP 401 — the stored credential was rejected; the user must re-pair
    /// (Auth_Error banner). Shown on the Setup_Screen, which is now a pairing
    /// screen, so the copy references re-pairing rather than an API key.
    static let pairingInvalid = "Kopplung ungültig - bitte neu koppeln"
    /// The submitted Base_URL was not a valid absolute http(s) URL.
    static let invalidURL = "Ungültige Adresse"

    // MARK: - Pairing-code setup errors (Requirements 1.5, 12.3–12.6)

    /// The submitted Pairing_Code was not exactly 6 digits (Req 1.5/12.3).
    static let codeMustBeSixDigits = "Code muss 6 Ziffern haben"
    /// Redeem rejected the code as invalid or expired (Req 12.4).
    static let codeInvalidOrExpired = "Code ungültig oder abgelaufen"
    /// Redeem was rate-limited (Req 12.5).
    static let tooManyAttempts = "Zu viele Versuche"
    /// Redeem exceeded its 10s deadline (Req 12.6).
    static let redeemTimeout = "Zeitüberschreitung beim Koppeln"
    /// Any other redeem failure.
    static let redeemFailed = "Koppeln fehlgeschlagen"

    // MARK: - Setup / config screen (Requirements 1.2, 1.3, 1.10)

    /// Setup screen title.
    static let setupTitle = "Einrichtung"
    /// Configuration screen title (reused for later config changes).
    static let configTitle = "Konfiguration"
    /// Base_URL input field label.
    static let baseURLLabel = "Serveradresse"
    /// API key input field label.
    static let apiKeyLabel = "API-Key"
    /// Pairing_Code input field label (Req 1.3).
    static let pairingCodeLabel = "Kopplungscode"
    /// Save / submit button label.
    static let save = "Speichern"
    /// Cancel the Setup_Screen and return to the control screen.
    static let cancel = "Abbrechen"
    /// Open configuration affordance in the control screen.
    static let openConfig = "Einstellungen"

    // MARK: - Command feedback (Requirements 4.5, 4.6, 4.7, 6.5, 6.6, 8.6)

    /// Generic success feedback after a command completes.
    static let commandSuccess = "Erledigt"
    /// Generic error feedback after a command fails.
    static let commandError = "Fehler"
    /// Feedback shown when a command exceeds its timeout deadline.
    static let commandTimeout = "Zeitüberschreitung"
    /// Non-blocking hint shown when a list refresh or poll fails.
    static let refreshFailed = "Aktualisierung fehlgeschlagen"

    // MARK: - Complication (Requirements 9.1, 9.2, 9.3)

    /// The Complication's on-face label, shown in every Complication_State.
    static let complicationLabel = "TV"
    /// Watch-face gallery display name for the Complication.
    static let complicationDisplayName = "TV-Lampe"
    /// Watch-face gallery description for the Complication.
    static let complicationDescription = "Zeigt den Status der TV-Lampe und schaltet sie ein oder aus."
}
