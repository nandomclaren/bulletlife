// Order keys and ids, compatible with the PWA: the `fractional-indexing` package (base 62, integer heads
// a–z / A–Z, "a0" first) and ULIDs. Ported line by line so both apps place entries the same way.
import Foundation

public enum OrderKey {
    static let digits: [Character] = Array("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz")
    static let zero: Character = "0"

    public enum Problem: Error { case invalid(String) }

    static func value(_ c: Character) -> Int { digits.firstIndex(of: c) ?? 0 }

    /// A key strictly between `a` and `b` (either may be nil: open end).
    public static func between(_ a: String?, _ b: String?) throws -> String {
        if let a { try validate(a) }
        if let b { try validate(b) }
        var a = a
        var b = b
        if let x = a, let y = b, x > y { (a, b) = (y, x) }
        guard let a else {
            guard let b else { return "a0" }
            let ib = try integerPart(b)
            let fb = String(b.dropFirst(ib.count))
            if ib == "A" + String(repeating: "0", count: 26) { return ib + (try midpoint("", fb)) }
            if ib < b { return ib }
            guard let res = try decrement(ib) else { throw Problem.invalid("cannot decrement any more") }
            return res
        }
        guard let b else {
            let ia = try integerPart(a)
            let fa = String(a.dropFirst(ia.count))
            guard let i = try increment(ia) else { return ia + (try midpoint(fa, nil)) }
            return i
        }
        let ia = try integerPart(a)
        let fa = String(a.dropFirst(ia.count))
        let ib = try integerPart(b)
        let fb = String(b.dropFirst(ib.count))
        if ia == ib { return ia + (try midpoint(fa, fb)) }
        guard let i = try increment(ia) else { throw Problem.invalid("cannot increment any more") }
        if i < b { return i }
        return ia + (try midpoint(fa, nil))
    }

    /// Keys for items in their new sequence, keeping existing keys while they are still in order, so only
    /// moved or new items get written (src/data/order.ts).
    public static func assign(ids: [String], existing: [String: String]) -> [String] {
        var out: [String] = []
        var prev: String?
        for i in ids.indices {
            if let own = existing[ids[i]], prev.map({ own > $0 }) ?? true {
                out.append(own)
                prev = own
                continue
            }
            var upper: String?
            for j in (i + 1)..<max(i + 1, ids.count) {
                if let k = existing[ids[j]] {
                    if prev.map({ k > $0 }) ?? true { upper = k }
                    break
                }
            }
            let key = (try? between(prev, upper)) ?? ((try? between(prev, nil)) ?? "a0")
            out.append(key)
            prev = key
        }
        return out
    }

    // MARK: Internals (fractional-indexing)

    static func midpoint(_ a: String, _ b: String?) throws -> String {
        if let b, a >= b { throw Problem.invalid("\(a) >= \(b)") }
        if a.last == zero || b?.last == zero { throw Problem.invalid("trailing zero") }
        let ac = Array(a)
        if let b, !b.isEmpty {
            let bc = Array(b)
            var n = 0
            while n < bc.count && (n < ac.count ? ac[n] : zero) == bc[n] { n += 1 }
            if n > 0 {
                return String(bc[0..<n]) + (try midpoint(String(ac.dropFirst(n)), String(bc.dropFirst(n))))
            }
        }
        let digitA = ac.first.map(value) ?? 0
        if let b, b.isEmpty {
            // The library compares against an undefined digit here, which takes the branch below.
            return String(digits[digitA]) + (try midpoint(String(ac.dropFirst()), nil))
        }
        let digitB = b.flatMap(\.first).map(value) ?? digits.count
        if digitB - digitA > 1 {
            let mid = Int((0.5 * Double(digitA + digitB)).rounded(.toNearestOrAwayFromZero))
            return String(digits[mid])
        }
        if let b, b.count > 1 { return String(b.prefix(1)) }
        return String(digits[digitA]) + (try midpoint(String(ac.dropFirst()), nil))
    }

    static func integerLength(_ head: Character) throws -> Int {
        guard let v = head.asciiValue else { throw Problem.invalid("head \(head)") }
        if (97...122).contains(v) { return Int(v) - 97 + 2 }  // a…z
        if (65...90).contains(v) { return 90 - Int(v) + 2 }  // A…Z
        throw Problem.invalid("head \(head)")
    }

    static func integerPart(_ key: String) throws -> String {
        guard let head = key.first else { throw Problem.invalid("empty key") }
        let n = try integerLength(head)
        if n > key.count { throw Problem.invalid("key \(key)") }
        return String(key.prefix(n))
    }

    static func validate(_ key: String) throws {
        if key == "A" + String(repeating: "0", count: 26) { throw Problem.invalid("key \(key)") }
        let i = try integerPart(key)
        if key.count > i.count && key.last == zero { throw Problem.invalid("key \(key)") }
    }

    static func increment(_ x: String) throws -> String? {
        let xc = Array(x)
        guard xc.count == (try integerLength(xc[0])) else { throw Problem.invalid("integer \(x)") }
        let head = xc[0]
        var trailing = ""
        var i = xc.count - 1
        while i >= 1 {
            let d = value(xc[i]) + 1
            if d == digits.count {
                trailing = String(zero) + trailing
            } else {
                return String(head) + String(xc[1..<i]) + String(digits[d]) + trailing
            }
            i -= 1
        }
        if head == "z" { return nil }
        let h: Character = head == "Z" ? "a" : Character(UnicodeScalar(head.asciiValue! + 1))
        let delta = try integerLength(h) - integerLength(head)
        if delta > 0 { return String(h) + trailing + String(zero) }
        if delta < 0 { return String(h) + String(trailing.dropFirst()) }
        return String(h) + trailing
    }

    static func decrement(_ x: String) throws -> String? {
        let xc = Array(x)
        guard xc.count == (try integerLength(xc[0])) else { throw Problem.invalid("integer \(x)") }
        let head = xc[0]
        let last = digits[digits.count - 1]
        var trailing = ""
        var i = xc.count - 1
        while i >= 1 {
            let d = value(xc[i]) - 1
            if d == -1 {
                trailing = String(last) + trailing
            } else {
                return String(head) + String(xc[1..<i]) + String(digits[d]) + trailing
            }
            i -= 1
        }
        if head == "A" { return nil }
        let h: Character = head == "a" ? "Z" : Character(UnicodeScalar(head.asciiValue! - 1))
        let delta = try integerLength(h) - integerLength(head)
        if delta > 0 { return String(h) + trailing + String(last) }
        if delta < 0 { return String(h) + String(trailing.dropFirst()) }
        return String(h) + trailing
    }
}

/// ULIDs (sortable unique ids), the id format of the PWA's entries.
public enum ULID {
    static let alphabet = Array("0123456789ABCDEFGHJKMNPQRSTVWXYZ")

    public static func make(now: Date = Date()) -> String {
        var ms = UInt64(max(0, now.timeIntervalSince1970 * 1000))
        var time = [Character](repeating: "0", count: 10)
        for i in (0..<10).reversed() {
            time[i] = alphabet[Int(ms % 32)]
            ms /= 32
        }
        let random = (0..<16).map { _ in alphabet[Int.random(in: 0..<32)] }
        return String(time + random)
    }
}
