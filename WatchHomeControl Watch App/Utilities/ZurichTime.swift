import Foundation

/// Formats instants for display in the Europe/Zurich timezone.
///
/// The Watch_App displays all time-of-day values in Europe/Zurich, applying
/// Central European Time (UTC+1) or Central European Summer Time (UTC+2)
/// automatically according to the date (Req 10.2). Values are rendered on the
/// 24-hour clock with two-digit hours and minutes (Req 10.3), and absent values
/// fall back to a fixed placeholder (Req 10.4).
enum ZurichTime {
    /// The placeholder shown when no valid instant is available (Req 10.4).
    static let placeholder = "--:--"

    /// A `DateFormatter` fixed to Europe/Zurich and the 24-hour `HH:mm` pattern.
    ///
    /// The formatter carries the Europe/Zurich timezone and a POSIX locale so the
    /// `HH:mm` template always yields a zero-padded, 24-hour result regardless of
    /// the device locale. Because the timezone (not a fixed offset) is attached,
    /// CET/CEST is selected per formatted date, including across DST transitions.
    private static let formatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: "Europe/Zurich")
        formatter.dateFormat = "HH:mm"
        return formatter
    }()

    /// Formats `date` as `HH:MM` in Europe/Zurich, or returns the placeholder for `nil`.
    ///
    /// - Parameter date: The instant to format, or `nil` when no value is available.
    /// - Returns: A `"HH:MM"` string in Europe/Zurich local time, or `"--:--"` when `date` is `nil`.
    static func hhmm(_ date: Date?) -> String {
        guard let date else { return placeholder }
        return formatter.string(from: date)
    }
}
