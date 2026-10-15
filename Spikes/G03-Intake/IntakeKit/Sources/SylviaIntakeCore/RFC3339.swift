import Foundation

/// RFC 3339 `date-time` exactly as the contracts' JSON Schema `format: date-time` accepts it (G0.3 review R2-04).
///
/// The contract validator (`Scripts/validate-contracts.py`: jsonschema 4.26 with rfc3339-validator 0.1.4) uppercases the
/// value and then requires `YYYY-MM-DDTHH:MM:SS[.fraction](Z|+HH:MM|-HH:MM)` with ASCII digits, month 01-12, a day that
/// exists in that month (leap years included), year not 0000, hour 00-23, minute and second 00-59 (no leap second), a
/// fraction of one or more digits, and an offset of hours 00-23 and minutes 00-59. JSONDecoder's `.iso8601` strategy
/// disagreed in both directions (measured on macOS 26.6 by the differential check in
/// Spikes/G03-Intake/scripts/check-contract-instances.sh; evidence `contract-instances-before-fix.log`): it refused a
/// lowercase `t` and `z`, which the schema allows, and accepted 30 February, 29 February 2025, hour 24, second 60, year
/// 0000 and an offset without a colon, which the schema refuses. The manifests' readers therefore decode `created_at`
/// with `RFC3339.date(from:)`.
public enum RFC3339 {
    /// The instant the string denotes (proleptic Gregorian, as RFC 3339 and Python's datetime count it), or nil when the
    /// contract's `date-time` format refuses it. The differential check compares every instant it reads with Python's.
    public static func date(from string: String) -> Date? {
        // The schema check uppercases first, so "t" and "z" are accepted; anything outside ASCII cannot match.
        guard string.utf8.allSatisfy({ $0 < 0x80 }) else { return nil }
        let bytes = Array(string.uppercased().utf8)
        var index = 0

        func digits(_ count: Int) -> Int? {
            guard index + count <= bytes.count else { return nil }
            var value = 0
            for byte in bytes[index..<(index + count)] {
                guard (0x30...0x39).contains(byte) else { return nil }
                value = value * 10 + Int(byte - 0x30)
            }
            index += count
            return value
        }
        func expect(_ character: UInt8) -> Bool {
            guard index < bytes.count, bytes[index] == character else { return false }
            index += 1
            return true
        }

        guard let year = digits(4), expect(UInt8(ascii: "-")),
              let month = digits(2), expect(UInt8(ascii: "-")),
              let day = digits(2), expect(UInt8(ascii: "T")),
              let hour = digits(2), expect(UInt8(ascii: ":")),
              let minute = digits(2), expect(UInt8(ascii: ":")),
              let second = digits(2)
        else { return nil }
        var fraction = 0.0
        if expect(UInt8(ascii: ".")) {
            var scale = 0.1
            var count = 0
            while index < bytes.count, (0x30...0x39).contains(bytes[index]) {
                fraction += Double(bytes[index] - 0x30) * scale
                scale /= 10
                count += 1
                index += 1
            }
            guard count > 0 else { return nil }
        }
        var offsetSeconds = 0
        if expect(UInt8(ascii: "Z")) {
            offsetSeconds = 0
        } else if index < bytes.count, bytes[index] == UInt8(ascii: "+") || bytes[index] == UInt8(ascii: "-") {
            let sign = bytes[index] == UInt8(ascii: "+") ? 1 : -1
            index += 1
            guard let offsetHour = digits(2), expect(UInt8(ascii: ":")), let offsetMinute = digits(2),
                  (0...23).contains(offsetHour), (0...59).contains(offsetMinute) else { return nil }
            offsetSeconds = sign * (offsetHour * 3600 + offsetMinute * 60)
        } else {
            return nil
        }
        guard index == bytes.count else { return nil }
        guard year >= 1, (1...12).contains(month), (1...daysIn(month: month, year: year)).contains(day),
              (0...23).contains(hour), (0...59).contains(minute), (0...59).contains(second) else { return nil }

        // The instant, counted in the proleptic Gregorian calendar that the day check above, RFC 3339 and Python's
        // datetime use. Foundation's `Calendar(identifier: .gregorian)` is Julian before 1582-10-15, so the first version,
        // which converted with it, put 1582-10-10 ten days late (after 1582-10-15) and 0001-01-01 two days early (G0.3
        // review R4-03). Years 1 to 9999 and offsets below a day keep every value far inside Int.
        let days = daysFromCivil(year: year, month: month, day: day)
        let seconds = days * 86_400 + hour * 3_600 + minute * 60 + second - offsetSeconds
        return Date(timeIntervalSince1970: TimeInterval(seconds) + fraction)
    }

    /// Days from 1970-01-01 to a date of the proleptic Gregorian calendar (negative before it). Howard Hinnant's
    /// `days_from_civil` (chrono-Compatible Low-Level Date Algorithms): years are counted from March, so a leap day is the
    /// last day of its year, and a 400-year era has exactly 146,097 days.
    public static func daysFromCivil(year: Int, month: Int, day: Int) -> Int {
        let y = month <= 2 ? year - 1 : year
        let era = (y >= 0 ? y : y - 399) / 400
        let yearOfEra = y - era * 400                                                   // 0...399
        let dayOfYear = (153 * (month > 2 ? month - 3 : month + 9) + 2) / 5 + day - 1   // 0...365, from 1 March
        let dayOfEra = yearOfEra * 365 + yearOfEra / 4 - yearOfEra / 100 + dayOfYear    // 0...146096
        return era * 146_097 + dayOfEra - 719_468
    }

    /// Days in a month of the proleptic Gregorian calendar (as Python's calendar.monthrange).
    static func daysIn(month: Int, year: Int) -> Int {
        switch month {
        case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
        case 4, 6, 9, 11: 30
        default: 31
        }
    }

    /// A JSON date decoding strategy that accepts exactly the contract's `date-time` values.
    public static var decodingStrategy: JSONDecoder.DateDecodingStrategy {
        .custom { decoder in
            let container = try decoder.singleValueContainer()
            let string = try container.decode(String.self)
            guard let date = RFC3339.date(from: string) else {
                throw DecodingError.dataCorruptedError(in: container, debugDescription: "not an RFC 3339 date-time")
            }
            return date
        }
    }
}
