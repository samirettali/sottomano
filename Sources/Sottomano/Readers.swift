import Foundation

/// A Mongo ObjectId: twenty-four hex digits, the first eight of which are
/// the second it was made. That is the useful part — an id off a document
/// says when the document was written.
struct ObjectId {
    let made: Date
    let machine: String
    let counter: Int

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count == 24, trimmed.allSatisfy(\.isHexDigit),
              let seconds = UInt32(trimmed.prefix(8), radix: 16),
              let counter = Int(trimmed.suffix(6), radix: 16)
        else { return nil }

        made = Date(timeIntervalSince1970: TimeInterval(seconds))
        machine = String(trimmed.dropFirst(8).prefix(10))
        self.counter = counter
    }

    var summary: String { "ObjectId · " + Readers.utc(made) }

    var details: [Detail] {
        [
            Detail("Made", Readers.utc(made)),
            Detail("Local", Readers.local(made)),
            Detail("Relative", Readers.relative(made)),
            Detail("Epoch (s)", String(Int(made.timeIntervalSince1970))),
            Detail("Process", machine),
            Detail("Counter", String(counter)),
        ]
    }
}

/// A UUID, with what its version says: v1 and v7 carry the moment they were
/// made, v4 is random and says nothing.
struct UUIDReader {
    let uuid: UUID
    let version: Int
    let made: Date?

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.count == 36, let uuid = UUID(uuidString: trimmed) else { return nil }

        let bytes = withUnsafeBytes(of: uuid.uuid) { Array($0) }

        self.uuid = uuid
        version = Int(bytes[6] >> 4)

        switch version {
        case 7:
            // the first 48 bits are milliseconds since the epoch
            let ms = bytes.prefix(6).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }

            made = Date(timeIntervalSince1970: TimeInterval(ms) / 1_000)
        case 1:
            // 100-nanosecond ticks since 1582-10-15, time_low then mid then
            // the high twelve bits
            let low = bytes.prefix(4).reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let mid = bytes[4..<6].reduce(UInt64(0)) { $0 << 8 | UInt64($1) }
            let high = bytes[6..<8].reduce(UInt64(0)) { $0 << 8 | UInt64($1) } & 0x0fff
            let ticks = high << 48 | mid << 32 | low

            made = Date(timeIntervalSince1970: TimeInterval(ticks) / 10_000_000 - 12_219_292_800)
        default:
            made = nil
        }
    }

    var summary: String {
        "UUID v\(version)" + (made.map { " · " + Readers.utc($0) } ?? "")
    }

    var details: [Detail] {
        var out = [
            Detail("Version", String(version)),
            Detail("Lowercase", uuid.uuidString.lowercased()),
            Detail("Uppercase", uuid.uuidString),
            Detail("Bare", uuid.uuidString.lowercased().replacingOccurrences(of: "-", with: "")),
        ]

        if let made {
            out.append(Detail("Made", Readers.utc(made)))
            out.append(Detail("Local", Readers.local(made)))
            out.append(Detail("Relative", Readers.relative(made)))
        }

        return out
    }
}

/// Twenty bytes of hex are an address and thirty-two a hash, on any chain
/// that runs the EVM. The address is written back with its EIP-55 checksum,
/// and both get a link to an explorer that indexes every chain rather than
/// one that presumes mainnet.
struct EVM {
    enum What {
        case address
        case hash
    }

    let what: What
    let hex: String

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)

        guard trimmed.hasPrefix("0x") || trimmed.hasPrefix("0X") else { return nil }

        let digits = String(trimmed.dropFirst(2)).lowercased()

        guard digits.allSatisfy(\.isHexDigit) else { return nil }

        switch digits.count {
        case 40: what = .address
        case 64: what = .hash
        default: return nil
        }

        hex = digits
    }

    /// The address with capitals where the keccak of its lowercase says.
    var checksummed: String {
        let hash = Keccak.hash(Array(hex.utf8))
        var out = "0x"

        for (index, digit) in hex.enumerated() {
            let nibble = index % 2 == 0 ? hash[index / 2] >> 4 : hash[index / 2] & 0x0f

            out.append(digit.isLetter && nibble >= 8 ? Character(digit.uppercased()) : digit)
        }

        return out
    }

    var summary: String {
        switch what {
        case .address: "EVM address"
        case .hash: "EVM hash · 32 bytes"
        }
    }

    var details: [Detail] {
        switch what {
        case .address:
            [
                Detail("Checksum", checksummed),
                Detail("Lowercase", "0x" + hex),
                Detail("Routescan", "https://routescan.io/address/" + checksummed),
            ]
        case .hash:
            [
                Detail("Hash", "0x" + hex),
                Detail("Decimal", Hex("0x" + hex)?.details.first { $0.label == "Decimal" }?.value ?? ""),
                Detail("Routescan", "https://routescan.io/tx/0x" + hex),
            ]
        }
    }
}

/// Keccak-256 as Ethereum uses it, which is SHA-3 before the padding byte
/// changed. Written out here because the one in CryptoKit is the other one.
enum Keccak {
    private static let rounds: [UInt64] = [
        0x0000000000000001, 0x0000000000008082, 0x800000000000808a, 0x8000000080008000,
        0x000000000000808b, 0x0000000080000001, 0x8000000080008081, 0x8000000000008009,
        0x000000000000008a, 0x0000000000000088, 0x0000000080008009, 0x000000008000000a,
        0x000000008000808b, 0x800000000000008b, 0x8000000000008089, 0x8000000000008003,
        0x8000000000008002, 0x8000000000000080, 0x000000000000800a, 0x800000008000000a,
        0x8000000080008081, 0x8000000000008080, 0x0000000080000001, 0x8000000080008008,
    ]
    private static let rotations: [Int] = [
        0, 1, 62, 28, 27, 36, 44, 6, 55, 20, 3, 10, 43, 25, 39, 41, 45, 15, 21, 8, 18, 2, 61, 56, 14,
    ]

    static func hash(_ message: [UInt8]) -> [UInt8] {
        let rate = 136
        var padded = message

        padded.append(0x01)

        while padded.count % rate != 0 { padded.append(0) }

        padded[padded.count - 1] |= 0x80

        var state = [UInt64](repeating: 0, count: 25)

        for block in stride(from: 0, to: padded.count, by: rate) {
            for lane in 0..<(rate / 8) {
                var word: UInt64 = 0

                for byte in 0..<8 {
                    word |= UInt64(padded[block + lane * 8 + byte]) << (8 * UInt64(byte))
                }

                state[lane] ^= word
            }

            permute(&state)
        }

        var out: [UInt8] = []

        for lane in 0..<4 {
            for byte in 0..<8 {
                out.append(UInt8((state[lane] >> (8 * UInt64(byte))) & 0xff))
            }
        }

        return out
    }

    private static func permute(_ a: inout [UInt64]) {
        for round in 0..<24 {
            var c = [UInt64](repeating: 0, count: 5)

            for x in 0..<5 { c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20] }

            for x in 0..<5 {
                let d = c[(x + 4) % 5] ^ rotl(c[(x + 1) % 5], 1)

                for y in stride(from: 0, to: 25, by: 5) { a[x + y] ^= d }
            }

            var b = [UInt64](repeating: 0, count: 25)

            for x in 0..<5 {
                for y in 0..<5 {
                    b[y + 5 * ((2 * x + 3 * y) % 5)] = rotl(a[x + 5 * y], rotations[x + 5 * y])
                }
            }

            for x in 0..<5 {
                for y in stride(from: 0, to: 25, by: 5) {
                    a[x + y] = b[x + y] ^ (~b[(x + 1) % 5 + y] & b[(x + 2) % 5 + y])
                }
            }

            a[0] ^= rounds[round]
        }
    }

    private static func rotl(_ x: UInt64, _ n: Int) -> UInt64 {
        n == 0 ? x : x << UInt64(n) | x >> UInt64(64 - n)
    }
}

/// A five-field cron expression, read for when it fires: the next few times
/// are worth more than a paraphrase of the fields.
struct Cron {
    private let fields: [Set<Int>]
    let text: String

    init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)

        guard parts.count == 5 else { return nil }

        let ranges = [0...59, 0...23, 1...31, 1...12, 0...6]
        var fields: [Set<Int>] = []

        for (part, range) in zip(parts, ranges) {
            guard let field = Cron.field(String(part), range) else { return nil }

            fields.append(field)
        }

        // a row of five words is a row of five words: at least one field has
        // to say something
        guard fields.contains(where: { !$0.isEmpty }) else { return nil }
        guard trimmed.contains(where: { $0.isNumber || $0 == "*" }) else { return nil }

        self.fields = fields
        self.text = trimmed
    }

    /// `*`, `*/15`, `1-5`, `1,15`, and the day and month names, into the set
    /// of values the field allows.
    private static func field(_ text: String, _ range: ClosedRange<Int>) -> Set<Int>? {
        let names = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
        let months = ["jan", "feb", "mar", "apr", "may", "jun", "jul", "aug", "sep", "oct", "nov", "dec"]

        func value(_ raw: Substring) -> Int? {
            if let number = Int(raw) { return range.contains(number) ? number : nil }

            let word = raw.lowercased()

            if range == 0...6, let index = names.firstIndex(of: word) { return index }
            if range == 1...12, let index = months.firstIndex(of: word) { return index + 1 }

            return nil
        }

        var out: Set<Int> = []

        for item in text.split(separator: ",") {
            let stepped = item.split(separator: "/", omittingEmptySubsequences: false)

            guard stepped.count <= 2 else { return nil }

            let step = stepped.count == 2 ? Int(stepped[1]) : 1

            guard let step, step >= 1 else { return nil }

            let span: ClosedRange<Int>

            if stepped[0] == "*" {
                span = range
            } else {
                let ends = stepped[0].split(separator: "-", omittingEmptySubsequences: false)

                guard ends.count <= 2, let low = value(ends[0]) else { return nil }

                if ends.count == 2 {
                    guard let high = value(ends[1]), high >= low else { return nil }

                    span = low...high
                } else {
                    span = stepped.count == 2 ? low...range.upperBound : low...low
                }
            }

            for number in stride(from: span.lowerBound, through: span.upperBound, by: step) {
                out.insert(number == 7 && range == 0...6 ? 0 : number)
            }
        }

        return out
    }

    private static let calendar: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!

        return calendar
    }()

    /// The next times it fires, walking the minutes from now. A year is the
    /// most that is walked: an expression that never fires in one is wrong.
    func next(_ count: Int, from start: Date = Date()) -> [Date] {
        var out: [Date] = []
        var at = Cron.calendar.date(bySetting: .second, value: 0, of: start).map { $0.addingTimeInterval(60) } ?? start
        let end = start.addingTimeInterval(366 * 86_400)

        while out.count < count, at < end {
            let parts = Cron.calendar.dateComponents([.minute, .hour, .day, .month, .weekday], from: at)

            if fields[0].contains(parts.minute!), fields[1].contains(parts.hour!),
               fields[3].contains(parts.month!),
               // as cron has it: with both day of month and day of week set,
               // either one is enough
               dayMatches(day: parts.day!, weekday: parts.weekday! - 1) {
                out.append(at)
            }

            at = at.addingTimeInterval(60)
        }

        return out
    }

    private func dayMatches(day: Int, weekday: Int) -> Bool {
        let anyDay = fields[2].count == 31
        let anyWeekday = fields[4].count == 7

        if anyDay || anyWeekday { return fields[2].contains(day) && fields[4].contains(weekday) }

        return fields[2].contains(day) || fields[4].contains(weekday)
    }

    var summary: String {
        guard let first = next(1).first else { return "cron · never" }

        return "cron · next " + Readers.relative(first)
    }

    var details: [Detail] {
        let runs = next(5)

        guard !runs.isEmpty else { return [Detail("Next", "never in the coming year")] }

        var out = runs.enumerated().map { index, run in
            Detail(index == 0 ? "Next (UTC)" : "", Readers.utc(run))
        }

        out.append(Detail("Local", Readers.local(runs[0])))

        return out
    }
}

/// The formatters the readers share.
enum Readers {
    private static func formatter(_ format: String, _ zone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = zone
        formatter.dateFormat = format

        return formatter
    }

    static func utc(_ date: Date) -> String {
        formatter("yyyy-MM-dd HH:mm:ss 'UTC'", TimeZone(identifier: "UTC")!).string(from: date)
    }

    static func local(_ date: Date) -> String {
        formatter("yyyy-MM-dd HH:mm:ss", .current).string(from: date) + " " + (TimeZone.current.abbreviation(for: date) ?? "")
    }

    static func relative(_ date: Date) -> String {
        let relative = RelativeDateTimeFormatter()
        relative.locale = Locale(identifier: "en_US")

        return relative.localizedString(for: date, relativeTo: Date())
    }
}
