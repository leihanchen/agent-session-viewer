import SwiftUI

/// Renders text with case-insensitive highlights for every occurrence of `query`.
struct HighlightedText: View {
    let text: String
    let query: String
    var font: Font = .body

    var body: some View {
        Text(attributed)
            .font(font)
            .textSelection(.enabled)
    }

    private var attributed: AttributedString {
        Self.highlight(text: text, query: query)
    }

    static func highlight(text: String, query: String) -> AttributedString {
        var result = AttributedString(text)
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return result }

        var start = text.startIndex
        while start < text.endIndex,
              let range = text.range(of: q, options: [.caseInsensitive], range: start..<text.endIndex)
        {
            if let lower = AttributedString.Index(range.lowerBound, within: result),
               let upper = AttributedString.Index(range.upperBound, within: result)
            {
                result[lower..<upper].backgroundColor = Color.yellow.opacity(0.45)
                result[lower..<upper].foregroundColor = .primary
            }
            start = range.upperBound
        }
        return result
    }
}
