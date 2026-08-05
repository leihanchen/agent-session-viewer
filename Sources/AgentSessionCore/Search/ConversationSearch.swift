import Foundation

/// One session that matched a conversation search query.
public struct ConversationSearchHit: Sendable, Equatable, Identifiable {
    public var id: String { session.id }
    public var session: SessionInfo
    /// Number of events whose content contains the query (case-insensitive).
    public var matchCount: Int
    /// Single-line snippet around the first match (plain text).
    public var firstSnippet: String
    /// UTF-16 offsets of the query within `firstSnippet` (for highlight in UI).
    public var firstSnippetMatchUTF16: Range<Int>?

    public init(
        session: SessionInfo,
        matchCount: Int,
        firstSnippet: String,
        firstSnippetMatchUTF16: Range<Int>?
    ) {
        self.session = session
        self.matchCount = matchCount
        self.firstSnippet = firstSnippet
        self.firstSnippetMatchUTF16 = firstSnippetMatchUTF16
    }
}

/// Scan session transcripts for a substring and rank hits.
public enum ConversationSearch {
    /// Case-insensitive conversation search over the given sessions.
    ///
    /// - Parameters:
    ///   - sessions: Catalog sessions to scan.
    ///   - query: Non-empty search string (whitespace-trimmed by caller recommended).
    ///   - loadEvents: Loads full-trace events for a session (used for body text).
    /// - Returns: Hits sorted by match count desc, then `updatedAt` desc.
    public static func search(
        sessions: [SessionInfo],
        query: String,
        loadEvents: (SessionInfo) throws -> [SessionEvent]
    ) -> [ConversationSearchHit] {
        let q = query.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return [] }

        var hits: [ConversationSearchHit] = []
        for session in sessions {
            let events: [SessionEvent]
            do {
                events = try loadEvents(session)
            } catch {
                continue
            }
            if let hit = match(session: session, events: events, query: q) {
                hits.append(hit)
            }
        }

        return hits.sorted { a, b in
            if a.matchCount != b.matchCount {
                return a.matchCount > b.matchCount
            }
            switch (a.session.updatedAt, b.session.updatedAt) {
            case let (l?, r?):
                if l != r { return l > r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return a.session.id < b.session.id
        }
    }

    /// Convenience using `SessionTranscript.loadEvents`.
    public static func search(sessions: [SessionInfo], query: String) -> [ConversationSearchHit] {
        search(sessions: sessions, query: query) { try SessionTranscript.loadEvents(session: $0) }
    }

    // MARK: - Internals

    static func match(
        session: SessionInfo,
        events: [SessionEvent],
        query: String
    ) -> ConversationSearchHit? {
        var matchCount = 0
        var firstSnippet: String?
        var firstUTF16: Range<Int>?

        for event in events {
            guard let content = event.content, !content.isEmpty else { continue }
            let ranges = content.asvRanges(of: query, options: [.caseInsensitive])
            guard !ranges.isEmpty else { continue }
            matchCount += 1
            if firstSnippet == nil {
                let built = makeSnippet(in: content, match: ranges[0], queryLength: query.count)
                firstSnippet = built.snippet
                firstUTF16 = built.matchUTF16
            }
        }

        guard matchCount > 0, let snippet = firstSnippet else { return nil }
        return ConversationSearchHit(
            session: session,
            matchCount: matchCount,
            firstSnippet: snippet,
            firstSnippetMatchUTF16: firstUTF16
        )
    }

    /// Build a single-line snippet with ~contextChars around the first match.
    static func makeSnippet(
        in text: String,
        match: Range<String.Index>,
        queryLength: Int,
        contextChars: Int = 80
    ) -> (snippet: String, matchUTF16: Range<Int>?) {
        let collapsed = text
            .replacingOccurrences(of: "\r\n", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
            .replacingOccurrences(of: "\t", with: " ")

        // Re-find match in collapsed string (indices may shift if only whitespace differs).
        // Prefer original match mapped when possible; fall back to first CI match in collapsed.
        let matchStartOffset = text.distance(from: text.startIndex, to: match.lowerBound)
        let matchEndOffset = text.distance(from: text.startIndex, to: match.upperBound)

        // Approximate using character offsets on collapsed (good enough for UI).
        let ns = collapsed as NSString
        let fullRange = NSRange(location: 0, length: ns.length)
        let found = ns.range(of: String(text[match]), options: [.caseInsensitive], range: fullRange)
        let useRange: NSRange
        if found.location != NSNotFound {
            useRange = found
        } else {
            // Fallback: scan for query
            let q = String(text[match])
            let r = ns.range(of: q, options: [.caseInsensitive], range: fullRange)
            useRange = r.location != NSNotFound ? r : NSRange(location: max(0, matchStartOffset), length: max(1, matchEndOffset - matchStartOffset))
        }

        let start = max(0, useRange.location - contextChars)
        let end = min(ns.length, useRange.location + useRange.length + contextChars)
        var snippet = ns.substring(with: NSRange(location: start, length: end - start))
        if start > 0 { snippet = "…" + snippet }
        if end < ns.length { snippet = snippet + "…" }

        // Match range within snippet (UTF-16).
        let prefixLen = start > 0 ? 1 : 0 // leading ellipsis is one UTF-16 char "…"
        let matchLocInSnippet = prefixLen + (useRange.location - start)
        let matchUTF16 = matchLocInSnippet..<(matchLocInSnippet + useRange.length)

        _ = queryLength
        return (snippet, matchUTF16)
    }
}

// MARK: - String helpers

extension String {
    /// All ranges of `searchString` using the given options (non-overlapping, forward).
    /// Named to avoid clashing with other `ranges(of:)` overloads in newer SDKs.
    func asvRanges(of searchString: String, options: String.CompareOptions = []) -> [Range<String.Index>] {
        guard !searchString.isEmpty else { return [] }
        var result: [Range<String.Index>] = []
        var start = startIndex
        while start < endIndex,
              let range = range(of: searchString, options: options, range: start..<endIndex)
        {
            result.append(range)
            start = range.upperBound
        }
        return result
    }
}
