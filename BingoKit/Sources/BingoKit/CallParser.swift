/// Turns typed (and later, OCR'd) text such as "G-54", "g 54" or "54" into a called number.
public enum CallParser {
    /// Returns the number 1–75, or nil if the text isn't a valid call.
    /// If a letter is given it must match the number's column ("B-54" is rejected).
    public static func parse(_ text: String) -> Int? {
        let separators: Set<Character> = ["-", "–", "—", ":", ".", " "]
        var characters = Array(text.uppercased().filter { !separators.contains($0) && !$0.isWhitespace })
        guard !characters.isEmpty else { return nil }

        var letterColumn: BingoColumn?
        if let first = characters.first, first.isLetter {
            guard let column = BingoColumn(letter: first) else { return nil }
            letterColumn = column
            characters.removeFirst()
        }

        guard (1...2).contains(characters.count),
              characters.allSatisfy(\.isNumber),
              let number = Int(String(characters)),
              let column = BingoColumn(number: number)
        else { return nil }

        if let letterColumn, letterColumn != column { return nil }
        return number
    }
}
