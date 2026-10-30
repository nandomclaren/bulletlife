// Recognizing an open item the user is rewriting elsewhere (CLAUDE.md 4.4, Phase 4b; src/data/similar.ts).
// Local, no AI, no network: normalized words compared by overlap. It only ever suggests; linking is the
// user's tap.
import Foundation

public enum Similar {
    /// English and Portuguese filler words: the user writes in either.
    static let stopwords: Set<String> = Set(
        ("a an the and or but of to in on at for from by with about as is are be was it this that these those my your our "
            + "o os as um uma uns umas e ou mas de do da dos das no na nos nas em para pra por com sem ao aos que se meu minha")
            .split(separator: " ").map(String.init))

    public static func normalize(_ text: String) -> [String] {
        var t = text as NSString
        for token in Due.tokens(text).reversed() { t = t.replacingCharacters(in: token.range, with: " ") as NSString }
        let folded = (t as String).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil).lowercased()
        let cleaned = String(folded.unicodeScalars.map { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) ? Character($0) : " " })
        return cleaned.split(separator: " ").map(String.init).filter { !stopwords.contains($0) }
    }

    /// Dice coefficient over word sets: 1 = same words.
    public static func similarity(_ a: [String], _ b: [String]) -> Double {
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let A = Set(a), B = Set(b)
        return 2 * Double(A.intersection(B).count) / Double(A.count + B.count)
    }

    /// A strong match only: the same words, or most words shared with at least two of them in common. Noise
    /// would make the suggestion annoying, so it errs on the side of saying nothing.
    public static func isStrongMatch(_ a: [String], _ b: [String]) -> Bool {
        guard !a.isEmpty, !b.isEmpty else { return false }
        if a == b { return true }
        return Set(a).intersection(b).count >= 2 && similarity(a, b) >= 0.7
    }

    /// The best strong match for `text` among the candidates, or nil.
    public static func bestMatch<T>(_ text: String, _ candidates: [T], text candidateText: (T) -> String) -> T? {
        let words = normalize(text)
        var best: T?
        var score = 0.0
        for c in candidates {
            let other = normalize(candidateText(c))
            guard isStrongMatch(words, other) else { continue }
            let s = similarity(words, other)
            if s > score { (best, score) = (c, s) }
        }
        return best
    }
}
