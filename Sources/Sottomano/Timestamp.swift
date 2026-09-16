import Foundation

/// A line of text that is a moment: an epoch in seconds, milliseconds,
/// microseconds or nanoseconds, or an ISO 8601 date. What an epoch is worth is
/// nothing at a glance — `1757068800000` has to be typed into something to be
/// read — so the clipboard says what it is beside it, and lays every form of
/// it out when the row is selected.
///
/// Only the clipboard reads it, on the main actor, which is what lets the
/// formatters be made once and kept.
@MainActor
struct Timestamp {
    let date: Date
    /// Whether there is anything under the second. A millisecond epoch that
    /// lands on a whole second is written back without `.000`.
    var fractional: Bool {
        let seconds = date.timeIntervalSince1970

        return (seconds * 1_000).rounded() != seconds.rounded(.down) * 1_000
    }

    /// A digit count is the unit: an epoch in seconds has ten digits from 2001
    /// to 2286, and every unit is three more. Nine digits would reach back to
    /// 1973, and would also take most of the numbers that are not dates.
    private static let units: [Int: Double] = [10: 1, 13: 1_000, 16: 1_000_000, 19: 1_000_000_000]

    /// The forms tried, in the order they are likely. ISO 8601 first, since it
    /// is the one most things print; then the same with a space instead of the
    /// T, which is how a database and a log line write it.
    private static let iso: [ISO8601DateFormatter] = {
        let fractional = ISO8601DateFormatter()
        fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let whole = ISO8601DateFormatter()
        whole.formatOptions = [.withInternetDateTime]

        let spaced = ISO8601DateFormatter()
        spaced.formatOptions = [.withInternetDateTime, .withSpaceBetweenDateAndTime]

        let spacedFractional = ISO8601DateFormatter()
        spacedFractional.formatOptions = [
            .withInternetDateTime, .withFractionalSeconds, .withSpaceBetweenDateAndTime,
        ]

        return [fractional, whole, spacedFractional, spaced]
    }()

    /// `2026-09-05 15:26:37 UTC` and `2026-09-05 15:26:37`, which is what the
    /// row itself says and what a log without a zone says. Read as UTC: a log
    /// line that does not name a zone is a server's, and a server runs on UTC.
    private static let plain: [DateFormatter] = {
        ["yyyy-MM-dd HH:mm:ss.SSS zzz", "yyyy-MM-dd HH:mm:ss zzz", "yyyy-MM-dd HH:mm:ss.SSS", "yyyy-MM-dd HH:mm:ss"].map {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = $0

            return formatter
        }
    }()

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count <= 40 else { return nil }

        if trimmed.allSatisfy(\.isNumber), let unit = Timestamp.units[trimmed.count],
           let value = Double(trimmed) {
            let seconds = value / unit

            // ten digits reach 2286, and an Italian mobile number read as
            // seconds lands between 2065 and 2099: neither is a date anyone
            // has on the clipboard, and the years before 2000 are cut for
            // the same reason at the other end
            guard let year = Timestamp.calendar.dateComponents([.year], from: Date(timeIntervalSince1970: seconds)).year,
                  (2000...2060).contains(year)
            else { return nil }

            date = Date(timeIntervalSince1970: seconds)

            return
        }

        // a number that is not one of those is not a date either, and the
        // formatters are not cheap enough to try on every row of the clipboard
        guard trimmed.first?.isNumber == true, trimmed.count >= 19 else { return nil }

        for formatter in Timestamp.iso {
            if let found = formatter.date(from: trimmed) {
                date = found

                return
            }
        }

        for formatter in Timestamp.plain {
            if let found = formatter.date(from: trimmed) {
                date = found

                return
            }
        }

        return nil
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        return calendar
    }()

    private static func formatter(_ format: String, zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format

        return formatter
    }

    /// `2025-09-05 10:40:00 UTC`, what the row says beside the number.
    var utc: String {
        Timestamp.formatter(fractional ? "yyyy-MM-dd HH:mm:ss.SSS 'UTC'" : "yyyy-MM-dd HH:mm:ss 'UTC'", zone: TimeZone(identifier: "UTC")!)
            .string(from: date)
    }

    /// Every form of the same moment, for the panel beside the list. The
    /// epochs go down to microseconds — nanoseconds are wider than anything
    /// else in the table, and nothing here hands them out.
    var details: [Detail] {
        let utcZone = TimeZone(identifier: "UTC")!
        let local = TimeZone.current
        let seconds = date.timeIntervalSince1970

        let iso = ISO8601DateFormatter()
        iso.formatOptions = fractional ? [.withInternetDateTime, .withFractionalSeconds] : [.withInternetDateTime]

        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "en_US")
        relative.unitsStyle = .full

        let week = Timestamp.calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
        let day = Timestamp.calendar.ordinality(of: .day, in: .year, for: date) ?? 0

        return [
            Detail("UTC", utc),
            Detail(
                "Local",
                Timestamp.formatter(fractional ? "yyyy-MM-dd HH:mm:ss.SSS" : "yyyy-MM-dd HH:mm:ss", zone: local).string(from: date)
                    + " " + (local.abbreviation(for: date) ?? local.identifier)
            ),
            Detail("ISO 8601", iso.string(from: date)),
            Detail("Relative", relative.localizedString(for: date, relativeTo: Date())),
            Detail("Epoch (s)", String(Int64(seconds.rounded(.down)))),
            Detail("Epoch (ms)", String(Int64((seconds * 1_000).rounded()))),
            Detail("Epoch (µs)", String(Int64((seconds * 1_000_000).rounded()))),
            Detail("Weekday", Timestamp.formatter("EEEE", zone: utcZone).string(from: date) + " (UTC)"),
            Detail("ISO week", String(format: "%04d-W%02d", week.yearForWeekOfYear ?? 0, week.weekOfYear ?? 0)),
            Detail("Day of year", String(day)),
        ]
    }
}

/// One line of the table shown beside a row that stands for data rather than
/// for a picture: a label and what it is worth.
struct Detail: Identifiable {
    let label: String
    let value: String

    var id: String { label }

    init(_ label: String, _ value: String) {
        self.label = label
        self.value = value
    }
}
