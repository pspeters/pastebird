import Foundation

/// Small realtime fuzzy search. Every space-separated term must match, either as a substring
/// (ranked highest) or as an in-order subsequence ("proj" → "/Users/me/Projects/..."). Ties keep recency order.
enum FuzzySearch {
    static func filter(_ items: [ClipItem], query: String) -> [ClipItem] {
        let terms = query.trimmingCharacters(in: .whitespaces).lowercased().split(separator: " ").map { Array(String($0).unicodeScalars) }
        if terms.isEmpty { return items }

        var matches: [(item: ClipItem, score: Int, index: Int)] = []
        for (i, item) in items.enumerated() {
            let text = item.searchText
            var total = 0
            for term in terms {
                let s = score(text, term)
                if s < 0 { total = -1; break }
                total += s
            }
            if total >= 0 { matches.append((item, total, i)) }
        }

        matches.sort { $0.score != $1.score ? $0.score > $1.score : $0.index < $1.index }
        return matches.map(\.item)
    }

    /// At most this many characters may sit between two letters of a subsequence match, so the letters of a
    /// term scattered over a long text ("nissewaard" across a whole e-mail) don't count as a match.
    private static let maxGap = 5

    /// Returns -1 for no match; substring matches always outrank subsequence matches.
    static func score(_ text: [Unicode.Scalar], _ term: [Unicode.Scalar]) -> Int {
        if let index = indexOf(term, in: text) {
            return 1000 + (isWordStart(text, index) ? 200 : 0) - min(index, 300)
        }
        guard let first = term.first else { return -1 }

        // Try every place the term's first letter occurs and keep the best compact match.
        var best = -1
        for start in text.indices where text[start] == first {
            var score = isWordStart(text, start) ? 10 : 0, matched = 1, last = start, streak = 0
            var i = start + 1
            while i < text.count && matched < term.count && i - last - 1 <= maxGap {
                defer { i += 1 }
                if text[i] != term[matched] { continue }

                if last == i - 1 {
                    streak += 1
                    score += 5 * streak
                } else {
                    streak = 0
                    score -= i - last - 1
                }
                if isWordStart(text, i) { score += 10 }
                last = i
                matched += 1
            }
            if matched == term.count { best = max(best, min(max(100 + score, 1), 600)) }
        }
        return best
    }

    private static func indexOf(_ term: [Unicode.Scalar], in text: [Unicode.Scalar]) -> Int? {
        guard !term.isEmpty, term.count <= text.count else { return term.isEmpty ? 0 : nil }
        let first = term[0]
        outer: for start in 0...(text.count - term.count) where text[start] == first {
            for j in 1..<term.count where text[start + j] != term[j] { continue outer }
            return start
        }
        return nil
    }

    private static func isWordStart(_ text: [Unicode.Scalar], _ i: Int) -> Bool {
        i == 0 || !(CharacterSet.alphanumerics.contains(text[i - 1]))
    }
}
