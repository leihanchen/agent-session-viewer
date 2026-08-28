# AGENTS.md — coding-agent runbook

Instructions for AI agents working in this repository. Read `docs/adr/` before changing locked decisions, `docs/SPEC.md` for requirements, and `CONTEXT.md` for domain terms.

## Product

**Agent Session Viewer** is a local macOS SwiftUI app plus Linux terminal UI with companion Swift CLI, **`asv`**, for browsing, searching, exporting, and confirmed deletion of coding-agent Sessions.

| Target | Purpose | Platforms |
|--------|---------|-----------|
| `AgentSessionCore` | Shared models, stores, parsing, search, export, delete safety | macOS, Linux |
| `asv` | CLI (ArgumentParser) | macOS, Linux |
| `asv-check` | Fixture smoke checks | macOS, Linux |
| `AgentSessionViewer` | SwiftUI app / Linux terminal UI | macOS 14+ / Linux |

Supported Agents: **Grok Build, Claude Code, Codex, Warp**. English UI only. Browse/search/export require no network. This is not a website, cloud service, or Session editor.

## Hard rules

1. Agent Data roots are non-mutating by default: never rename, rewrite, or repair their contents.
2. Confirmed Session delete is the only mutation exception (ADR 0008/0009):
   - Grok: one Session directory.
   - Claude/Codex: one Session JSONL file.
   - Warp: rows for one `conversation_id` in a transaction; never delete `warp.sqlite`.
   - File-backed deletion must use `SessionDeleter` containment/type checks.
3. Export writes only to the chosen output directory. Treat exports as sensitive.
4. Keep the native, non-sandboxed Swift architecture (ADRs 0001/0004); no Electron, Tauri, WebView, or App Sandbox in v1.
5. Keep Core Agent-agnostic (`AgentKind`, `Project`, `SessionInfo`, `SessionEvent`, `ExportBundle`). Agent-specific parsing belongs under `Sources/AgentSessionCore/<Agent>/` behind `AgentSessionStore`.
6. Use `CONTEXT.md` terms: **Agent, Data root, Project, Session, Detail stream, Event, Readable mode, Full trace, Export bundle**. Avoid workspace/chat/thread for these concepts.
7. New Agents require `AgentKind`, `DataRoot`, store/factory, transcript dispatch, fixtures/checks, CLI help, and docs updates.

## Architecture and layout

```text
AgentSessionViewer (SwiftUI macOS / terminal Linux)  asv (ArgumentParser)
              \                    /
               AgentSessionCore
 models · roots · transcripts · search · export · delete safety
                       |
              AgentSessionStore
       Grok | Claude | Codex | Warp adapters
       files   JSONL    JSONL   SQLite rows
```

- Swift tools 5.9; macOS deployment target 14.
- `swift-argument-parser` is CLI-only. Core links `sqlite3` for Warp; Linux builds need `libsqlite3-dev`.
- `Package.swift` selects the SwiftUI viewer on macOS and a dependency-free terminal viewer on Linux. Never import SwiftUI/AppKit in Core or CLI.
- Flow: `DataRoot.resolve` → `AgentStoreFactory` → normalized models/events → `SessionTranscript`, `ConversationSearch`, `SessionExporter`, or `deleteSession`.
- Readable mode coalesces text chunks and removes noise; Full trace preserves all normalized Events. Export always uses Full trace, schema version 1.
- Search is case-insensitive per selected Agent, ranked by matching Event count then recency.

```text
Sources/AgentSessionCore/
  Agent/                 # protocol, factory, delete safety
  Grok/ Claude/ Codex/ Warp/
  Search/ Export/
  DataRoot.swift Models.swift SessionTitle.swift SessionTranscript.swift
Sources/asv/ASV.swift
Sources/AgentSessionViewer/       # SwiftUI macOS target
Sources/AgentSessionViewerLinux/  # terminal Linux target
Sources/asv-check/main.swift
Tests/AgentSessionCoreTests/Fixtures/{grok-home,claude-home,codex-home,warp-home}/
docs/{SPEC.md,adr/}  CONTEXT.md  README.md  CHANGELOG.md
```

## Agent stores

| Agent / CLI id | Root resolution | Discovery |
|----------------|-----------------|-----------|
| Grok Build / `grok-build` | `--home` → `$GROK_HOME` → `~/.grok` | `sessions/<encoded-cwd>/<id>/{summary.json,updates.jsonl}` |
| Claude Code / `claude-code` | `--home` → `$CLAUDE_CONFIG_DIR` → `$CLAUDE_HOME` → `~/.claude` | `projects/<encoded-cwd>/<id>.jsonl`; prefer JSONL `cwd` |
| Codex / `codex` | `--home` → `$CODEX_HOME` → `~/.codex` | scan `sessions/YYYY/MM/DD/rollout-*.jsonl`; optional `session_index.jsonl` titles; group by `session_meta.cwd` |
| Warp / `warp` | `--home` → `$WARP_HOME` → `$WARP_DIR` → platform default | `warp.sqlite`: `agent_conversations` + `ai_queries` |

Warp defaults: macOS group container `…/dev.warp.Warp-Stable`; Linux `~/.local/state/warp-terminal`. An override may be a directory or the SQLite path. Warp `SessionInfo.directoryPath` is a locator, not a removable path. Do not decode `agent_tasks` protobuf in v1. Do not depend on third-party Claude/Codex indexes.

## `asv` CLI contract

One Agent per invocation; `grok-build` and `list` are defaults.

| Command | Contract |
|---------|----------|
| `list` | Root plus Project/Session counts; `--json` object |
| `projects` | Project groups; text TSV or `--json` array |
| `sessions [project-id]` | All or exact-Project Sessions; text TSV or `--json` array |
| `show <session-id>` | Metadata + Readable conversation; `--full` for Full trace; optional `--json` |
| `export <id>\|--all` | One Full-trace JSON file per Session; `--out` defaults to `./asv-export` |
| `delete <session-id>` | Exactly one Session; type `delete` interactively or pass `--yes` (required without TTY) |

Common options: `--agent grok-build|claude-code|codex|warp`, `--home <path>`. `--json` is limited to list/projects/sessions/show; `--full` to show; `--out` to export; `--yes` to delete.

Export is normalized JSON, not raw files or a zip. It contains top-level `schema_version`, `agent`, `exported_at`, `session`, and `events`; top-level custom keys are snake_case while nested synthesized model keys are camelCase. Files are pretty-printed, atomically written, and named from the Session id with `/` replaced by `_`.

Missing roots/Sessions, invalid Agent or export arguments, unsafe deletes, and write failures must exit non-zero with clear errors. Keep top-level and subcommand `--help` accurate.

## App contract

- Three columns: **Projects → Sessions → Details/Conversation**.
- Toolbar: persisted four-Agent picker, resolved root, Readable/Full trace, Refresh, confirmed Delete.
- Sessions list shows all Sessions for the Agent, newest first; Project selection jumps to that Project’s first Session.
- One debounced “Search all conversations…” field searches the selected Agent only, ranks/highlights matches, and returns to browse on an empty query.
- Click/⌘-click/Shift-click multi-selection; app can confirm-delete selected Sessions, while CLI deletion remains one at a time.
- Title fallback: Agent summary/title → first user message → short id.
- Subagent Sessions are flat; loading is snapshot + Refresh; no live watcher.
- CLI export is complete; in-app export controls remain pending.

## Build and verify

Mandatory before claiming done:

```bash
swift build
swift run asv-check
swift build --product asv
.build/debug/asv --help
.build/debug/asv list --help
.build/debug/asv projects --help
.build/debug/asv sessions --help
.build/debug/asv show --help
.build/debug/asv export --help
.build/debug/asv delete --help
```

Run `swift test` when full Xcode/XCTest is available. For GUI work, run `swift run AgentSessionViewer`. Live-root checks are optional; never test delete against user data or immutable fixtures—use temporary fixture copies.

Release checks:

```bash
./scripts/embed-version.sh
swift build -c release --product asv
.build/release/asv --version
ASV_VERSION=0.2.0 ./scripts/package-dmg.sh
```

Version resolution: `ASV_VERSION` → `v*` tag → `VERSION`; `embed-version.sh` updates `Version.swift`. The historically named `package-dmg.sh` must produce **PKG only**: app → `/Applications`, CLI → `/usr/local/bin`, fallback CLI inside the app. Packaging requires `Assets/asv-icon-1024.png`.

CI (`.github/workflows/build-installer.yml`) builds the macOS PKG and Linux tarball (both `asv` and `AgentSessionViewer`) on Ubuntu; tags attach both to Releases.

## Change checklist

1. Check ADRs; update `docs/SPEC.md` for requirement changes and `CONTEXT.md` only for glossary changes.
2. Keep source, CLI help, README, SPEC, changelog, and this runbook aligned.
3. Add/update per-Agent fixtures and `asv-check`; add XCTest where useful.
4. Verify new CLI behavior in help, text/JSON output, errors, and Linux builds.
5. Test deletion only on temporary copies; verify the target is gone and siblings/root/database remain.
6. Verify export schema/Agent/Full trace, one-file naming, atomic writes, and output-only mutation.

Out of scope v1: rewriting Session files; Project/root or CLI bulk delete; live tail; zip/raw export; App Sandbox/App Store; nested subagents; Cursor; cross-Agent search; web UI; Warp protobuf decoding.

Documentation authority: `docs/adr/` (locked decisions) → `docs/SPEC.md` (requirements) → `CONTEXT.md` (terms) → `README.md` (user guide) → `CHANGELOG.md`. If code and docs disagree about current behavior, inspect source/tests and update stale docs; requirement changes still need SPEC/ADR updates.
