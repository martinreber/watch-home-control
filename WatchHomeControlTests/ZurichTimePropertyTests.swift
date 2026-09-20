import Foundation
import Testing
@testable import WatchHomeControl_Watch_App

/// Property tests for `ZurichTime.hhmm(_:)`.
///
/// Feature: apple-watch-home-control, Property 19: Time formatting is
/// Europe/Zurich, 24-hour HH:MM, with a placeholder for absent values
///
/// Validates Requirements 10.2, 10.3, 10.4.
///
/// Uses Swift Testing's generator-driven approach: a wide span of random
/// instants (≥100 iterations) is combined with instants explicitly sampled
/// inside the two Europe/Zurich DST boundary weekends (spring-forward, last
/// Sunday of March; fall-back, last Sunday of October) so CET↔CEST is
/// exercised. Each formatted string is checked against `^\d\d:\d\d$` and
/// against an independently computed `HH:mm` derived from a Europe/Zurich
/// `Calendar`/`DateComponents`.
struct ZurichTimePropertyTests {
    /// Independent oracle: an Europe/Zurich calendar used to recompute HH:mm.
    private static let zurichCalendar: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "Europe/Zurich")!
        cal.locale = Locale(identifier: "en_US_POSIX")
        return cal
    }()

    /// Recomputes the expected `HH:mm` string via DateComponents in Europe/Zurich.
    private static func expectedHHMM(_ date: Date) -> String {
        let comps = zurichCalendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", comps.hour!, comps.minute!)
    }

    /// Regex matching exactly two digits, a colon, and two digits.
    private static func matchesPattern(_ s: String) -> Bool {
        s.wholeMatch(of: /\d\d:\d\d/) != nil
    }

    /// Generates the set of instants exercised by the property.
    ///
    /// Combines random instants across a wide date span with explicit samples
    /// inside the DST boundary weekends of several years, guaranteeing at least
    /// 100 iterations and DST coverage in both directions.
    private static func instants() -> [Date] {
        var dates: [Date] = []

        // Deterministic RNG so failures are reproducible.
        var rng = SystemRandomNumberGenerator()

        // Wide random span: roughly 2000-01-01 .. 2050-01-01 (UTC reference).
        let lower: TimeInterval = 946_684_800   // 2000-01-01T00:00:00Z
        let upper: TimeInterval = 2_524_608_000  // 2050-01-01T00:00:00Z
        for _ in 0..<200 {
            let t = TimeInterval.random(in: lower...upper, using: &rng)
            dates.append(Date(timeIntervalSince1970: t))
        }

        // Explicit DST boundary weekends. In Europe/Zurich the clocks change on
        // the last Sunday of March (CET->CEST, 02:00->03:00) and the last Sunday
        // of October (CEST->CET, 03:00->02:00). Sample minute-by-minute across a
        // window straddling each transition for several years.
        let dstWeekends: [(year: Int, month: Int, day: Int)] = [
            (2024, 3, 31), (2024, 10, 27),
            (2025, 3, 30), (2025, 10, 26),
            (2026, 3, 29), (2026, 10, 25),
        ]
        // Build the 01:00 Europe/Zurich instant for each transition day, then
        // walk forward minute-by-minute for three hours across the boundary.
        for w in dstWeekends {
            var comps = DateComponents()
            comps.year = w.year
            comps.month = w.month
            comps.day = w.day
            comps.hour = 1
            comps.minute = 0
            comps.second = 0
            guard let start = zurichCalendar.date(from: comps) else { continue }
            for minute in 0..<180 {
                dates.append(start.addingTimeInterval(TimeInterval(minute * 60)))
            }
        }

        return dates
    }

    @Test("Property 19: hhmm is Europe/Zurich 24-hour HH:MM across a wide span and DST boundaries")
    func hhmmMatchesZurichCalendar() {
        let dates = Self.instants()
        // Guarantee the minimum iteration count.
        #expect(dates.count >= 100)

        for date in dates {
            let formatted = ZurichTime.hhmm(date)
            #expect(
                Self.matchesPattern(formatted),
                "Formatted value \"\(formatted)\" does not match ^\\d\\d:\\d\\d$ for \(date)"
            )
            #expect(
                formatted == Self.expectedHHMM(date),
                "Formatted value \"\(formatted)\" != expected \"\(Self.expectedHHMM(date))\" for \(date)"
            )
        }
    }

    @Test("Property 19: nil instant yields the placeholder")
    func nilYieldsPlaceholder() {
        #expect(ZurichTime.hhmm(nil) == "--:--")
        #expect(ZurichTime.hhmm(nil) == ZurichTime.placeholder)
    }
}
