import SwiftUI
import AgentSessionCore

/// Three-column browser: Projects → Sessions → Session info + Conversation stream.
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
        .searchable(text: $model.projectFilter, prompt: "Filter projects")
        .onAppear { model.refresh() }
        .onChange(of: model.selectedSessionId) { _, _ in
            model.reloadEvents()
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

    private var projectsColumn: some View {
        List(model.filteredProjects, selection: $model.selectedProjectId) { project in
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

    private var sessionsColumn: some View {
        List(model.sessionsForSelection, selection: $model.selectedSessionId) { session in
            VStack(alignment: .leading, spacing: 4) {
                Text(session.title)
                    .font(.body.weight(.medium))
                    .lineLimit(2)
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
            .tag(session.id)
            .padding(.vertical, 2)
        }
        .navigationTitle("Sessions")
        .overlay {
            if model.selectedProjectId == nil {
                ContentUnavailableView("Select a project", systemImage: "folder")
            } else if model.sessionsForSelection.isEmpty {
                ContentUnavailableView("No sessions", systemImage: "bubble.left.and.bubble.right")
            }
        }
    }

    private var detailColumn: some View {
        Group {
            if let session = model.selectedSession {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        sessionInfoCard(session)
                        conversationSection
                    }
                    .padding()
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                ContentUnavailableView("Select a session", systemImage: "doc.text")
            }
        }
        .navigationTitle("Details")
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
                        EventRowView(event: event, mode: model.detailMode)
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
                let collapsed = mode == .readable && shouldCollapse(body)
                Text(collapsed && !expanded ? String(body.prefix(500)) + (body.count > 500 ? "…" : "") : body)
                    .font(.system(.callout, design: .default))
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if collapsed {
                    Button(expanded ? "Show less" : "Show more") {
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
    @Published var projectFilter: String = ""
    @Published var dataRootPath: String = ""
    @Published var errorMessage: String?

    @Published var detailMode: DetailViewMode = .readable
    @Published var events: [SessionEvent] = []
    @Published var isLoadingEvents = false
    @Published var eventsError: String?

    var filteredProjects: [Project] {
        let q = projectFilter.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !q.isEmpty else { return projects }
        return projects.filter {
            $0.path.localizedCaseInsensitiveContains(q)
                || $0.displayName.localizedCaseInsensitiveContains(q)
                || $0.id.localizedCaseInsensitiveContains(q)
        }
    }

    var sessionsForSelection: [SessionInfo] {
        guard let selectedProjectId else { return [] }
        return sessions.filter { $0.projectId == selectedProjectId }
    }

    var selectedSession: SessionInfo? {
        guard let selectedSessionId else { return nil }
        return sessions.first { $0.id == selectedSessionId }
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
        } catch {
            projects = []
            sessions = []
            events = []
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
}
