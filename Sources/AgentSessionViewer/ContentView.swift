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
                Picker("Agent", selection: $model.selectedAgent) {
                    ForEach(AgentKind.allCases) { agent in
                        Text(agent.displayName).tag(agent)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 360)
                .onChange(of: model.selectedAgent) { _, _ in
                    model.switchAgent()
                }
                .help("Select which coding agent’s sessions to browse (Grok Build, Claude Code, Codex)")
            }
            ToolbarItem(placement: .automatic) {
                Text("\(model.selectedAgent.displayName) · \(model.dataRootPath)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 420)
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
            ToolbarItem(placement: .destructiveAction) {
                Button(role: .destructive) {
                    model.confirmDeleteSession = true
                } label: {
                    Label(model.deleteToolbarTitle, systemImage: "trash")
                }
                .disabled(model.selectedSessionIds.isEmpty)
                .help("Delete selected sessions (click, ⌘-click, or Shift-click to select)")
            }
        }
        // One search field only — conversation full-text over every session.
        .searchable(text: $model.conversationQuery, prompt: "Search all conversations…")
        .onChange(of: model.conversationQuery) { _, _ in
            model.scheduleConversationSearch()
        }
        .onAppear { model.refresh() }
        .onChange(of: model.selectedSessionIds) { _, _ in
            model.reloadEvents()
        }
        .onChange(of: model.selectedProjectId) { _, projectId in
            // Browse only: jump to that project's sessions (search is always global).
            guard !model.isSearchActive, let projectId else { return }
            if let first = model.sessions.first(where: { $0.projectId == projectId }) {
                model.selectedSessionIds = [first.id]
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
        .confirmationDialog(
            model.deleteConfirmTitle,
            isPresented: $model.confirmDeleteSession,
            titleVisibility: .visible
        ) {
            Button(model.deleteConfirmActionTitle, role: .destructive) {
                model.deleteSelectedSessions()
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text(model.deleteConfirmMessage)
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
        // Set selection enables macOS multi-select: ⌘-click toggle, Shift-click range.
        List(model.allSessionsSorted, selection: $model.selectedSessionIds) { session in
            sessionRow(session)
                .tag(session.id)
                .contextMenu {
                    Button(model.contextDeleteTitle(for: session.id), role: .destructive) {
                        model.prepareDelete(fromContextMenuOn: session.id)
                    }
                }
        }
        .overlay {
            if model.allSessionsSorted.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }

    private var searchResultsList: some View {
        List(selection: $model.selectedSessionIds) {
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
                    .contextMenu {
                        Button(model.contextDeleteTitle(for: hit.session.id), role: .destructive) {
                            model.prepareDelete(fromContextMenuOn: hit.session.id)
                        }
                    }
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
                    Text(footerLine(
                        base: "\(model.searchResults.count) of \(model.sessions.count) sessions matched"
                    ))
                }
            } else {
                Text(footerLine(base: "\(model.sessions.count) sessions (all projects)"))
            }
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .frame(maxWidth: .infinity)
        .padding(8)
    }

    private func footerLine(base: String) -> String {
        let n = model.selectedSessionIds.count
        if n == 0 { return base }
        if n == 1 { return "\(base) · 1 selected" }
        return "\(base) · \(n) selected"
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
            if model.selectedSessionIds.count > 1 {
                multiSelectDetail
            } else if let session = model.selectedSession {
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
                ContentUnavailableView(
                    "Select a session",
                    systemImage: "doc.text",
                    description: Text("Click a session, or use ⌘-click / Shift-click to select several.")
                )
            }
        }
        .navigationTitle("Details")
    }

    private var multiSelectDetail: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("\(model.selectedSessionIds.count) sessions selected")
                    .font(.title2.weight(.semibold))
                Text("Conversation is shown when exactly one session is selected. Use Delete to remove all selected sessions at once.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                VStack(alignment: .leading, spacing: 8) {
                    ForEach(model.selectedSessions) { session in
                        VStack(alignment: .leading, spacing: 2) {
                            Text(session.title)
                                .font(.body.weight(.medium))
                                .lineLimit(2)
                            Text(session.id)
                                .font(.caption2.monospaced())
                                .foregroundStyle(.secondary)
                            Text(session.projectPath)
                                .font(.caption)
                                .foregroundStyle(.tertiary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .padding(.vertical, 4)
                        Divider()
                    }
                }
                .padding()
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
        }
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
    private static let agentDefaultsKey = "asv.selectedAgent"

    @Published var selectedAgent: AgentKind {
        didSet {
            UserDefaults.standard.set(selectedAgent.rawValue, forKey: Self.agentDefaultsKey)
        }
    }
    @Published var projects: [Project] = []
    @Published var sessions: [SessionInfo] = []
    @Published var selectedProjectId: Project.ID?
    /// Multi-select (macOS List: click, ⌘-click toggle, Shift-click range).
    @Published var selectedSessionIds: Set<SessionInfo.ID> = []
    @Published var dataRootPath: String = ""
    @Published var errorMessage: String?

    @Published var detailMode: DetailViewMode = .readable
    @Published var events: [SessionEvent] = []
    @Published var isLoadingEvents = false
    @Published var eventsError: String?

    /// Single toolbar search: full-text over every session conversation (current agent only).
    @Published var conversationQuery: String = ""
    @Published var searchResults: [ConversationSearchHit] = []
    @Published var isSearching = false

    /// Drives the destructive delete confirmation dialog.
    @Published var confirmDeleteSession = false

    private var store: any AgentSessionStore
    private var searchTask: Task<Void, Never>?

    init() {
        let raw = UserDefaults.standard.string(forKey: Self.agentDefaultsKey)
        let agent = raw.flatMap(AgentKind.init(rawValue:)) ?? .grokBuild
        self.selectedAgent = agent
        self.store = AgentStoreFactory.make(agent: agent)
    }

    func switchAgent() {
        store = AgentStoreFactory.make(agent: selectedAgent)
        selectedProjectId = nil
        selectedSessionIds = []
        conversationQuery = ""
        searchResults = []
        events = []
        refresh()
    }

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

    /// Visible list order (browse or search) — used for multi-select summary and confirm copy.
    var visibleSessions: [SessionInfo] {
        if isSearchActive {
            return searchResults.map(\.session)
        }
        return allSessionsSorted
    }

    /// Selected sessions in **visible list order**.
    var selectedSessions: [SessionInfo] {
        let ids = selectedSessionIds
        return visibleSessions.filter { ids.contains($0.id) }
    }

    /// Conversation detail only when exactly one session is selected.
    var selectedSession: SessionInfo? {
        guard selectedSessionIds.count == 1, let id = selectedSessionIds.first else { return nil }
        if isSearchActive {
            return searchResults.first(where: { $0.session.id == id })?.session
                ?? sessions.first { $0.id == id }
        }
        return sessions.first { $0.id == id }
    }

    var deleteToolbarTitle: String {
        let n = selectedSessionIds.count
        if n <= 1 { return "Delete Session" }
        return "Delete \(n) Sessions"
    }

    var deleteConfirmTitle: String {
        let n = selectedSessionIds.count
        if n <= 1 { return "Delete session?" }
        return "Delete \(n) sessions?"
    }

    var deleteConfirmActionTitle: String {
        let n = selectedSessionIds.count
        if n <= 1 { return "Delete" }
        return "Delete \(n) Sessions"
    }

    var deleteConfirmMessage: String {
        let selected = selectedSessions
        guard !selected.isEmpty else {
            return "Permanently remove the selected session(s) from disk. This cannot be undone."
        }
        if selected.count == 1, let session = selected.first {
            return """
            Permanently remove “\(session.title)” from this Mac?

            ID: \(session.id)
            Path: \(session.directoryPath)

            This cannot be undone. Stop the agent if it is still using this session.
            """
        }
        let previewLimit = 5
        var lines = selected.prefix(previewLimit).map { "• \($0.title)" }
        if selected.count > previewLimit {
            lines.append("• …and \(selected.count - previewLimit) more")
        }
        return """
        Permanently remove \(selected.count) sessions from this Mac?

        \(lines.joined(separator: "\n"))

        This cannot be undone. Stop agents that are still using these sessions.
        """
    }

    func contextDeleteTitle(for sessionId: SessionInfo.ID) -> String {
        if selectedSessionIds.contains(sessionId), selectedSessionIds.count > 1 {
            return "Delete \(selectedSessionIds.count) Sessions…"
        }
        return "Delete Session…"
    }

    /// Finder-like: if the row is already part of a multi-selection, keep it; otherwise select only that row.
    func prepareDelete(fromContextMenuOn sessionId: SessionInfo.ID) {
        if !selectedSessionIds.contains(sessionId) || selectedSessionIds.count <= 1 {
            selectedSessionIds = [sessionId]
        }
        confirmDeleteSession = true
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
        // Rebuild store in case defaults/home changed for the same agent.
        store = AgentStoreFactory.make(agent: selectedAgent)
        do {
            dataRootPath = store.dataRoot.path
            projects = try store.listProjects()
            sessions = try store.listSessions(projectId: nil)
            if let selectedProjectId, !projects.contains(where: { $0.id == selectedProjectId }) {
                self.selectedProjectId = nil
                selectedSessionIds = []
            }
            pruneSelection(toKnown: Set(sessions.map(\.id)))
            reloadEvents()
            if isSearchActive {
                scheduleConversationSearch(immediate: true)
            }
        } catch {
            projects = []
            sessions = []
            events = []
            searchResults = []
            selectedSessionIds = []
            errorMessage = error.localizedDescription
        }
    }

    private func pruneSelection(toKnown known: Set<SessionInfo.ID>) {
        selectedSessionIds = selectedSessionIds.intersection(known)
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
            let raw = try store.loadEvents(session: session)
            events = detailMode == .fullTrace ? raw : SessionTranscript.coalesceForReadable(raw)
        } catch {
            events = []
            eventsError = error.localizedDescription
        }
        isLoadingEvents = false
    }

    /// Permanently delete all selected sessions from the data root, then refresh lists.
    func deleteSelectedSessions() {
        let ids = Array(selectedSessionIds)
        guard !ids.isEmpty else { return }

        var deleted = 0
        var failures: [(String, String)] = []
        for id in ids {
            do {
                _ = try store.deleteSession(id: id)
                deleted += 1
            } catch {
                failures.append((id, error.localizedDescription))
            }
        }

        selectedSessionIds = []
        events = []
        eventsError = nil
        refresh()

        if !failures.isEmpty {
            let failedIds = failures.map(\.0).joined(separator: ", ")
            if deleted == 0 {
                errorMessage = "Could not delete any sessions. \(failures.first?.1 ?? "")"
            } else {
                errorMessage = "Deleted \(deleted) of \(ids.count). Failed: \(failedIds)"
            }
        }
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
        let agent = selectedAgent
        let delayNs: UInt64 = immediate ? 0 : 300_000_000

        searchTask = Task { [weak self] in
            if delayNs > 0 {
                try? await Task.sleep(nanoseconds: delayNs)
            }
            guard !Task.isCancelled else { return }

            let hits = await Task.detached(priority: .userInitiated) {
                ConversationSearch.search(sessions: snapshot, query: q) { session in
                    // Load via SessionTranscript so Grok/Claude dispatch works off-main.
                    try SessionTranscript.loadEvents(session: session)
                }
            }.value
            _ = agent

            guard !Task.isCancelled else { return }
            await MainActor.run {
                guard let self else { return }
                // Drop stale results if the query or agent changed while we scanned.
                guard self.trimmedQuery == q, self.selectedAgent == agent else { return }
                self.searchResults = hits
                self.isSearching = false
                let hitIds = Set(hits.map(\.session.id))
                let kept = self.selectedSessionIds.intersection(hitIds)
                if !kept.isEmpty {
                    self.selectedSessionIds = kept
                    self.reloadEvents()
                } else if let first = hits.first {
                    self.selectedSessionIds = [first.session.id]
                    self.reloadEvents()
                } else {
                    self.selectedSessionIds = []
                    self.events = []
                }
            }
        }
    }
}
