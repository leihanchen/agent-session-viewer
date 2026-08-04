import SwiftUI
import AgentSessionCore

/// P0 three-column shell: Projects → Sessions → placeholder Details.
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
        .navigationTitle("Agent Session View")
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Text(model.dataRootPath)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .frame(maxWidth: 360)
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
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Conversation")
                                .font(.headline)
                            Text("Detail stream (Readable / Full trace) lands in P1. Use `asv show` / `asv export` for now.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
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

@MainActor
final class AppModel: ObservableObject {
    @Published var projects: [Project] = []
    @Published var sessions: [SessionInfo] = []
    @Published var selectedProjectId: Project.ID?
    @Published var selectedSessionId: SessionInfo.ID?
    @Published var projectFilter: String = ""
    @Published var dataRootPath: String = ""
    @Published var errorMessage: String?

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
        } catch {
            projects = []
            sessions = []
            errorMessage = error.localizedDescription
        }
    }
}
