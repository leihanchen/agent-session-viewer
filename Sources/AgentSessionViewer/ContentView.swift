import SwiftUI
import AgentSessionCore

/// Three-column browser: Projects → Sessions → Conversation.
/// Single toolbar search: full-text across **all** sessions / conversations.
struct ContentView: View {
    @StateObject private var model = AppModel()

    var body: some View {
        NavigationSplitView {
            projectsColumn
        } content: {
            sessionsColumn
        } detail: {
            detailColumn
        }
        .navigationTitle("Agent Session Viewer")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text(model.dataRootPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360)
            }
            ToolbarItem(placement: .automatic) {
                Picker("View mode", selection: $model.detailMode) {
                    Text("Readable").tag(DetailViewMode.readable)
                    Text("Full trace").tag(DetailViewMode.fullTrace)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 220)
                .onChange(of: model.detailMode) { _, _ in
                    model.reloadEvents()
                }
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    model.refresh()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .help("Reload projects and sessions from disk")
            }
        }
        // One search field only — conversation full-text over every session.
        .searchable(text: $model.conversationQuery, prompt: "Search all conversations…")
        .onChange(of: model.conversationQuery) { _, _ in
            model.scheduleConversationSearch()
        }
        .onAppear { model.refresh() }
        .onChange(of: model.selectedSessionId) { _, _ in
            model.reloadEvents()
        }
        .onChange(of: model.selectedProjectId) { _, projectId in
            // Browse only: jump to that project's sessions (search is always global).
            guard !model.isSearchActive, let projectId else { return }
            if let first = model.sessions.first(where: { $0.projectId == projectId }) {
                model.selectedSessionId = first.id
            }
        }
        .alert("Error", isPresented: Binding(
            get: { model.errorMessage != nil },
            set: { if !$0 { model.errorMessage = nil } }
        )) {
            Button("OK", role: .cancel) { model.errorMessage = nil }
        } message: {
            Text(model.errorMessage ?? "")
        }
    }

    // MARK: - Projects

    private var projectsColumn: some View {
        List(model.projects, selection: $model.selectedProjectId) { project in
            VStack(alignment: .leading, spacing: 4) {
                Text(project.displayName)
                    .font(.headline)
                Text(project.path)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text("\(project.sessionCount) sessions")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .tag(project.id)
            .padding(.vertical, 2)
        }
        .navigationTitle("Projects")
        .safeAreaInset(edge: .bottom) {
            Text("\(model.projects.count) projects")
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .padding(8)
        }
    }

    // MARK: - Sessions

    private var sessionsColumn: some View {
        Group {
            if model.isSearchActive {
                searchResultsList
            } else {
                browseSessionsList
            }
        }
        .navigationTitle(model.isSearchActive ? "Search results" : "All sessions")
        .safeAreaInset(edge: .bottom) {
            sessionsFooter
        }
    }

    private var browseSessionsList: some View {
        // Always list every session (not gated on project selection).
        List(model.allSessionsSorted, selection: $model.selectedSessionId) { session in
            sessionRow(session)
                .tag(session.id)
        }
        .overlay {
            if model.allSessionsSorted.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }

    private var searchResultsList: some View {
        List(selection: $model.selectedSessionId) {
            if model.isSearching {
                HStack {
                    ProgressView()
                        .controlSize(.small)
                    Text("Searching conversations…")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .listRowSeparator(.hidden)
            }
            ForEach(model.searchResults) { hit in
                searchHitRow(hit)
                    .tag(hit.session.id)
            }
        }
        .overlay {
            if !model.isSearching && model.searchResults.isEmpty {
                ContentUnavailableView(
                    "No matching sessions",
                    systemImage: "magnifyingglass",
                    description: Text("No conversation contains “\(model.trimmedQuery)”.")
                )
            }
        }
    }

    private var sessionsFooter: some View {
        Group {
            if model.isSearchActive {
                if model.isSearching {
                    Text("Searching all conversations…")
                } else {
                    Text("\(model.searchResults.count) of \(model.sessions.count) sessions matched")
                }
            } else {
                Text("\(model.sessions.count) sessions (all projects)")
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(8)
    }

    private func sessionRow(_ session: SessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(session.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
            Text(session.projectPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Text(session.id)
                    .font(.caption2.monospaced())
                Spacer()
                if let updated = session.updatedAt {
                    Text(updated, style: .date)
                        .font(.caption2)
                }
            }
            .foregroundStyle(.secondary)
            Text("\(session.messageCount) messages · \(session.model ?? "—")")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }

    private func searchHitRow(_ hit: ConversationSearchHit) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(hit.session.title)
                .font(.body.weight(.medium))
                .lineLimit(2)
            Text(hit.session.projectPath)
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Text("\(hit.matchCount) match\(hit.matchCount == 1 ? "" : "es")")
                    .font(.caption2.weight(.semibold))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.15), in: Capsule())
                Spacer()
                if let updated = hit.session.updatedAt {
                    Text(updated, style: .date)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            HighlightedText(text: hit.firstSnippet, query: model.trimmedQuery, font: .caption)
                .lineLimit(3)
                .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    // MARK: - Details

    private var detailColumn: some View {
        Group {
            if let session = model.selectedSession {
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 16) {
                            sessionInfoCard(session)
                            conversationSection
                        }
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .onChange(of: model.events) { _, _ in
                        scrollToFirstMatch(proxy: proxy)
                    }
                    .onChange(of: model.conversationQuery) { _, _ in
                        scrollToFirstMatch(proxy: proxy)
                    }
                }
            } else {
                ContentUnavailableView("Select a session", systemImage: "doc.text")
            }
        }
        .navigationTitle("Details")
    }

    private func scrollToFirstMatch(proxy: ScrollViewProxy) {
        guard model.isSearchActive,
              let id = model.firstMatchingEventId
        else { return }
        DispatchQueue.main.async {
            withAnimation {
                proxy.scrollTo(id, anchor: .center)
            }
        }
    }

    private var conversationSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Conversation")
                    .font(.headline)
                Spacer()
                if model.isLoadingEvents {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("\(model.events.count) events")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let loadError = model.eventsError {
                Text(loadError)
                    .font(.callout)
                    .foregroundStyle(.red)
            } else if model.events.isEmpty, !model.isLoadingEvents {
                Text("No conversation events found for this session.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                LazyVStack(alignment: .leading, spacing: 10) {
                    ForEach(model.events) { event in
                        EventRowView(
                            event: event,
                            mode: model.detailMode,
                            highlightQuery: model.isSearchActive ? model.trimmedQuery : nil
                        )
                        .id(event.id)
                    }
                }
            }
        }
    }

    private func sessionInfoCard(_ session: SessionInfo) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Session Info")
                .font(.headline)
            labeled("Title", session.title)
            labeled("ID", session.id)
            labeled("Project", session.projectPath)
            labeled("Model", session.model ?? "—")
            labeled("Messages", "\(session.messageCount)")
            labeled("Path", session.directoryPath)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    private func labeled(_ key: String, _ value: String) -> some View {
        HStack(alignment: .top) {
            Text(key)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 72, alignment: .leading)
            Text(value)
                .font(.caption.monospaced())
                .textSelection(.enabled)
        }
    }
}

// MARK: - Event row

private struct EventRowView: View {
    let event: SessionEvent
    let mode: DetailViewMode
    var highlightQuery: String?

    @State private var expanded = false

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                Text(SessionTranscript.displayLabel(for: event))
                    .font(.caption2.weight(.bold))
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(badgeColor.opacity(0.2), in: Capsule())
                    .foregroundStyle(badgeColor)

                if let tool = event.toolName, event.type == "tool_use" || event.type == "tool_result" {
                    Text(tool)
                        .font(.caption2.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }

                Spacer()

                if let ts = event.timestamp {
                    Text(ts, style: .time)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }

            let body = event.content?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !body.isEmpty {
                let hasQuery = bodyMatchesQuery(body)
                let collapsed = mode == .readable && shouldCollapse(body) && !hasQuery
                let shown = collapsed && !expanded
                    ? String(body.prefix(500)) + (body.count > 500 ? "…" : "")
                    : body

                if let q = highlightQuery, !q.isEmpty {
                    HighlightedText(text: shown, query: q, font: .system(.callout, design: .default))
                        .frame(maxWidth: .infinity, alignment: .leading)
                } else {
                    Text(shown)
                        .font(.system(.callout, design: .default))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }

                if collapsed || (hasQuery && shouldCollapse(body) && !expanded) {
                    // If we forced expand due to match, still allow collapse only when no query match
                }
                if mode == .readable && shouldCollapse(body) {
                    Button(expanded || hasQuery ? (expanded ? "Show less" : "Show full") : "Show more") {
                        expanded.toggle()
                    }
                    .font(.caption)
                    .buttonStyle(.plain)
                    .foregroundStyle(.blue)
                }
            } else if mode == .fullTrace {
                Text("(no text payload)")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(rowBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay(
            RoundedRectangle(cornerRadius: 10)
                .strokeBorder(badgeColor.opacity(0.25), lineWidth: 1)
        )
    }

    private func bodyMatchesQuery(_ body: String) -> Bool {
        guard let q = highlightQuery?.trimmingCharacters(in: .whitespacesAndNewlines), !q.isEmpty else {
            return false
        }
        return body.range(of: q, options: [.caseInsensitive]) != nil
    }

    private func shouldCollapse(_ body: String) -> Bool {
        body.count > 500 || body.split(separator: "\n").count > 12
    }

    private var badgeColor: Color {
        switch event.type {
        case "user": return .blue
        case "assistant": return .green
        case "thinking": return .purple
        case "tool_use": return .orange
        case "tool_result": return event.isError ? .red : .teal
        default: return .secondary
        }
    }

    private var rowBackground: Color {
        Color.primary.opacity(0.04)
    }
}

// MARK: - Model

@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var sessions: [SessionInfo] = []
    @Published var selectedProjectId: Project.ID?
    @Published var selectedSessionId: SessionInfo.ID?
    @Published var dataRootPath: String = ""
    @Published var errorMessage: String?

    @Published var detailMode: DetailViewMode = .readable
    @Published var events: [SessionEvent] = []
    @Published var isLoadingEvents = false
    @Published var eventsError: String?

    /// Single toolbar search: full-text over every session conversation.
    @Published var conversationQuery: String = ""
    @Published var searchResults: [ConversationSearchHit] = []
    @Published var isSearching = false

    private var searchTask: Task<Void, Never>?

    var trimmedQuery: String {
        conversationQuery.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isSearchActive: Bool {
        !trimmedQuery.isEmpty
    }

    /// Browse list: every session under the data root, newest first.
    var allSessionsSorted: [SessionInfo] {
        sessions.sorted { a, b in
            switch (a.updatedAt, b.updatedAt) {
            case let (l?, r?):
                if l != r { return l > r }
            case (_?, nil):
                return true
            case (nil, _?):
                return false
            case (nil, nil):
                break
            }
            return a.id < b.id
        }
    }

    var selectedSession: SessionInfo? {
        guard let selectedSessionId else { return nil }
        if isSearchActive {
            return searchResults.first(where: { $0.session.id == selectedSessionId })?.session
                ?? sessions.first { $0.id == selectedSessionId }
        }
        return sessions.first { $0.id == selectedSessionId }
    }

    var firstMatchingEventId: String? {
        guard isSearchActive else { return nil }
        let q = trimmedQuery
        guard !q.isEmpty else { return nil }
        return events.first { event in
            (event.content ?? "").range(of: q, options: [.caseInsensitive]) != nil
        }?.id
    }

    func refresh() {
        errorMessage = nil
        do {
            let catalog = GrokCatalog()
            dataRootPath = catalog.dataRoot.path
            projects = try catalog.listProjects()
            sessions = try catalog.listSessions()
            if let selectedProjectId, !projects.contains(where: { $0.id == selectedProjectId }) {
                self.selectedProjectId = nil
                self.selectedSessionId = nil
            }
            if let selectedSessionId, !sessions.contains(where: { $0.id == selectedSessionId }) {
                self.selectedSessionId = nil
            }
            reloadEvents()
            if isSearchActive {
                scheduleConversationSearch(immediate: true)
            }
        } catch {
            projects = []
            sessions = []
            events = []
            searchResults = []
            errorMessage = error.localizedDescription
        }
    }

    func reloadEvents() {
        guard let session = selectedSession else {
            events = []
            eventsError = nil
            isLoadingEvents = false
            return
        }
        isLoadingEvents = true
        eventsError = nil
        do {
            events = try SessionTranscript.events(for: session, mode: detailMode)
        } catch {
            events = []
            eventsError = error.localizedDescription
        }
        isLoadingEvents = false
    }

    func scheduleConversationSearch(immediate: Bool = false) {
        searchTask?.cancel()
        let q = trimmedQuery
        if q.isEmpty {
            isSearching = false
            searchResults = []
            return
        }

        isSearching = true
        let snapshot = sessions
        let delayNs: UInt64 = immediate ? 0 : 300_000_000

        searchTask = Task { [weak self] in
            if delayNs > 0 {
                try? await Task.sleep(nanoseconds: delayNs)
            }
            guard !Task.isCancelled else { return }

            let hits = await Task.detached(priority: .userInitiated) {
                ConversationSearch.search(sessions: snapshot, query: q) { session in
                    try SessionTranscript.loadEvents(session: session)
                }
            }.value

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                // Drop stale results if the query changed while we scanned.
                guard self.trimmedQuery == q else { return }
                self.searchResults = hits
                self.isSearching = false
                // Keep selection if still in results; otherwise select first hit.
                if let sel = self.selectedSessionId, hits.contains(where: { $0.session.id == sel }) {
                    self.reloadEvents()
                } else if let first = hits.first {
                    self.selectedSessionId = first.session.id
                    self.reloadEvents()
                } else {
                    self.selectedSessionId = nil
                    self.events = []
                }
            }
        }
    }
}
