import BingoKit

/// One piece of text found in a photo.
public struct TextObservation: Hashable, Sendable {
    public var text: String
    /// Vision's confidence in this reading, 0–1.
    public var confidence: Double
    /// Height of the text's bounding box as a fraction of the image height, 0–1.
    /// The called number on the big screen is usually the largest text in view.
    public var height: Double

    public init(text: String, confidence: Double, height: Double) {
        self.text = text
        self.confidence = confidence
        self.height = height
    }
}

/// A number the photo might be showing, with a score for ranking (higher is more likely).
public struct CallCandidate: Hashable, Sendable, Identifiable {
    public var number: Int
    public var score: Double
    /// The text it was read from, for debugging.
    public var source: String

    public var id: Int { number }
    public var label: String { BingoColumn.label(for: number) }
}

/// Turns raw OCR text into ranked bingo-call guesses. Pure logic, no Vision, so it's easy to test.
///
/// Scoring:
/// - A letter + number that agree ("G 54") beats a bare number ("54").
/// - Bigger text beats smaller text (the ball on screen is huge; menus and clocks are small).
/// - OCR look-alikes are fixed only where it's safe: "G5A" no, but "O 6S" → O-65 is still
///   checked against the O column's range before it counts.
public enum CallTextInterpreter {
    static let letterAndNumberWeight = 1.0
    static let bareNumberAloneWeight = 0.6
    static let bareNumberInSentenceWeight = 0.25

    public static func candidates(from observations: [TextObservation]) -> [CallCandidate] {
        let tallest = observations.map(\.height).max() ?? 0
        guard tallest > 0 else { return [] }

        var best: [Int: CallCandidate] = [:]
        for observation in observations {
            let sizeWeight = observation.height / tallest
            for match in matches(in: observation.text) {
                let score = observation.confidence * sizeWeight * match.weight
                if score > best[match.number]?.score ?? 0 {
                    best[match.number] = CallCandidate(number: match.number, score: score, source: observation.text)
                }
            }
        }
        return best.values.sorted { $0.score != $1.score ? $0.score > $1.score : $0.number < $1.number }
    }

    struct Match: Equatable {
        let number: Int
        let weight: Double
    }

    static func matches(in text: String) -> [Match] {
        let tokens = tokenize(text)
        var result: [Match] = []
        var index = 0

        while index < tokens.count {
            let token = tokens[index]

            // Joined together: "G54", or "654" where the G was misread as a 6.
            if token.count >= 2, let first = token.first,
               let column = column(for: first, allowLookalikes: token.count == 3 && first.isNumber),
               let number = digits(token.dropFirst()),
               column.range.contains(number) {
                result.append(Match(number: number, weight: letterAndNumberWeight))
                index += 1
                continue
            }

            // Separate: "G" "54" (the separator was already removed by tokenize).
            if token.count == 1, index + 1 < tokens.count,
               let column = column(for: token.first!, allowLookalikes: true),
               let number = digits(tokens[index + 1][...]),
               column.range.contains(number) {
                result.append(Match(number: number, weight: letterAndNumberWeight))
                index += 2
                continue
            }

            // Just a number: "54".
            if (1...2).contains(token.count), token.allSatisfy(\.isNumber),
               let number = Int(token), BingoColumn.validNumbers.contains(number) {
                let weight = tokens.count == 1 ? bareNumberAloneWeight : bareNumberInSentenceWeight
                result.append(Match(number: number, weight: weight))
            }
            index += 1
        }
        return result
    }

    static func tokenize(_ text: String) -> [String] {
        let separators: Set<Character> = ["-", "–", "—", ":", ".", ",", "•", "·", "/", "(", ")", "#"]
        return text.uppercased()
            .split { $0.isWhitespace || separators.contains($0) }
            .map(String.init)
    }

    /// The bingo letter a character stands for. Digit look-alikes (0→O, 1→I, 6→G, 8→B)
    /// are only allowed when the caller knows a letter must be there.
    static func column(for character: Character, allowLookalikes: Bool) -> BingoColumn? {
        if let column = BingoColumn(letter: character) { return column }
        guard allowLookalikes else { return nil }
        switch character {
        case "8": return .b
        case "1", "|": return .i
        case "6": return .g
        case "0": return .o
        default: return nil
        }
    }

    /// Reads 1–2 digits, fixing letter look-alikes (O→0, I/L→1, S→5, Z→2, B→8),
    /// but only if at least one real digit is present (so the word "BINGO" isn't read as B-1).
    static func digits(_ text: Substring) -> Int? {
        guard (1...2).contains(text.count), text.contains(where: \.isNumber) else { return nil }
        let fixed = text.map { character -> Character in
            switch character {
            case "O", "D", "Q": "0"
            case "I", "L", "|", "!": "1"
            case "S": "5"
            case "Z": "2"
            case "B": "8"
            default: character
            }
        }
        guard fixed.allSatisfy(\.isNumber) else { return nil }
        return Int(String(fixed))
    }
}
