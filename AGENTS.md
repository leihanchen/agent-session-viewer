# AGENTS.md — coding agent memory

Instructions for AI coding agents working in **this repository**. Keep changes aligned with the product decisions below; prefer reading `docs/SPEC.md` for full requirements and `CONTEXT.md` for domain vocabulary.

---

## What this project is

**Agent Session Viewer** — local macOS app + companion CLI **`asv`** for browsing, exporting, and (when confirmed) deleting coding-agent sessions on disk.

| Surface | Name |
|---------|------|
| macOS app | Agent Session Viewer |
| CLI binary | `asv` |
| Shared library | `AgentSessionCore` |

- **English UI only**
- **Agent stores:** Grok Build (`~/.grok`), Claude Code (`~/.claude`), Codex (`~/.codex`), Warp (`warp.sqlite`: macOS group container or Linux `~/.local/state/warp-terminal`); toolbar picker + CLI `--agent`
- **CLI (`asv`)** builds on **macOS and Linux**. **Viewer** is **macOS-only** (not in the Linux product list).
- **Future agents:** add `AgentSessionStore` under `Sources/AgentSessionCore/<Agent>/`
- **Not:** a website, WebView app, cloud service, or session editor

---

## Hard rules (do not violate)

1. **Non-mutating by default toward agent data roots** — do not rename, rewrite, or “fix” files under any Data root. **Exception (ADR 0008 / 0009):** confirmed session delete via `AgentSessionStore.deleteSession` / UI Delete / `asv delete` only. Warp delete is SQL row delete inside `warp.sqlite` — never remove the database file. Export **writes** only under a user-chosen output path.
2. **No network required** for browse/export.
3. **SwiftUI + Swift** for app and CLI — not Tauri, Electron, or a web UI stack (ADR 0001).
4. **Non-sandboxed** local app for v1 (must read outside the app container).
5. Prefer **agent-agnostic** types in Core (`Project`, `Session`, `Event`, `ExportBundle`); put layout parsing under `Sources/AgentSessionCore/Grok/` or `Claude/` via `AgentSessionStore`.
6. Use glossary terms from `CONTEXT.md` in code comments, UI strings, and docs (e.g. **Project**, **Session**, **Detail stream**, not “workspace/chat/thread” for those concepts).

---

## Repo map

```
Package.swift                 # SPM: AgentSessionCore, asv, AgentSessionViewer, asv-check
Sources/AgentSessionCore/     # discovery, models, Grok adapter, export
Sources/asv/                  # CLI (ArgumentParser) — keep --help complete
Sources/AgentSessionViewer/     # SwiftUI three-column app
Sources/asv-check/            # fixture smoke tests (no XCTest / CLT-friendly)
Tests/AgentSessionCoreTests/  # XCTest + Fixtures (needs full Xcode)
docs/SPEC.md                  # product requirements & phases
docs/adr/                     # architecture decisions
CONTEXT.md                    # domain glossary only (not agent runbook)
README.md                     # human quickstart
```

---

## Build & verify (mandatory before claiming done)

```bash
swift build
swift run asv-check                    # always — works with Command Line Tools only
swift build --product asv
.build/debug/asv --help                # help must list all commands + usage
.build/debug/asv list                  # optional live check against ~/.grok
# swift test                           # only if full Xcode is installed (XCTest)
```

App (dev):

```bash
swift run AgentSessionViewer
```

Release CLI / installer:

```bash
# Embed marketing version (from ASV_VERSION, git tag, or VERSION file)
./scripts/embed-version.sh
swift build -c release --product asv
./.build/release/asv --version            # must match VERSION / tag
ASV_VERSION=0.2.0 ./scripts/package-dmg.sh   # PKG only; Info.plist matches asv --version
```

**Version source of truth:** `scripts/embed-version.sh` → `VERSION` + `Sources/AgentSessionCore/Version.swift` (`ASVVersion.current`). Used by CLI and CFBundleShortVersionString. See `CHANGELOG.md` for release history.

### CI (GitHub Actions)

- Workflow: `.github/workflows/build-installer.yml` on **macos-14**
- Rebuilds installer remotely via:
  - `workflow_dispatch` (`gh workflow run build-installer.yml -f version=0.2.0`)
  - `repository_dispatch` event type `build-installer`
  - tag `v*`
  - push to `main` when packaging/source paths change
- Uploads `.pkg` as workflow artifact; tags attach the `.pkg` to a GitHub Release

---

## CLI contract (`asv`)

Commands must remain discoverable via `asv --help` (overview + examples) and `asv <cmd> --help`.

| Command | Purpose |
|---------|---------|
| `list` | Overview (default subcommand) |
| `projects` | List projects |
| `sessions [project-id]` | List sessions |
| `show <session-id>` | Metadata **+ full conversation** (Readable by default; `--full` for full trace) |
| `export <id>\|--all` | Full-trace JSON into a directory |
| `delete <session-id>` | Permanently remove one session (`--yes` skips confirm) |

Common flags: `--agent grok-build|claude-code|codex|warp` (default `grok-build`), `--home <path>`, `--json` (list/projects/sessions/show), `--full` (`show`), `--out <dir>` (export), `--yes` (`delete`).

Export = **one JSON file per session**, full event trace, fields at least: `schema_version`, `agent` (`grok-build` / `claude-code` / `codex` / `warp`), session info, `events[]`. Bulk export = directory of files (not zip in v1). One agent per command (no cross-agent list).

Delete = remove that session’s primary artifact under the data root only (Grok directory; Claude/Codex jsonl; Warp conversation rows). Paths outside the data root are refused (file-backed agents).

---

## UI contract (app)

Three columns (CC LOG–style, English):

1. **Projects** — cwd groups  
2. **Sessions** — title, dates, counts  
3. **Details** — Session info + **Conversation** (every message/event)  

- **Session title:** summary → first user message → short id  
- **Delete:** toolbar trash (and session context menu) with confirmation; multi-select with ⌘-click / Shift-click range, then delete all selected  
 
 
- **Readable mode** (default): coalesced turns; **Full trace** toolbar toggle: every event  
- Load via `SessionTranscript.events(for:mode:)` from `updates.jsonl`  
- **Agent picker** (toolbar): Grok Build | Claude Code | Codex — reloads that agent’s data root only  
- **One search field only:** “Search all conversations…” — full-text across every session **of the selected agent** (debounced). Results sorted by match count then `updatedAt`; highlight in snippets + detail. Empty query lists all sessions for that agent.
- Subagent sessions: **flat peers** (no nesting in v1)  
- Snapshot load / Refresh only — no live file watching in v1  

---

## On-disk layouts

### Grok Build

```
<data-root>/sessions/<percent-encoded-cwd>/<session-id>/
  summary.json      # metadata / title
  updates.jsonl     # authoritative conversation + tool stream
```

- Default: `$GROK_HOME` or `~/.grok`
- Adapter: `GrokCatalog` / `GrokUpdates`

### Claude Code

```
<data-root>/projects/<encoded-cwd>/<session-uuid>.jsonl
```

- Default: `$CLAUDE_CONFIG_DIR` / `$CLAUDE_HOME` or `~/.claude`
- Prefer JSONL `cwd` over reverse-encoding the folder name
- Adapter: `ClaudeCatalog` / `ClaudeTranscript`
- Do not depend on third-party indexes (e.g. `cc-log.sqlite`)

### Codex

```
<data-root>/sessions/YYYY/MM/DD/rollout-<timestamp>-<session-uuid>.jsonl
<data-root>/session_index.jsonl   # optional titles
```

- Default: `$CODEX_HOME` or `~/.codex`
- Discover by scanning rollouts; use `session_index` for `thread_name` titles when present
- Group projects by `session_meta.cwd`
- Adapter: `CodexCatalog` / `CodexTranscript`
- Do not require SQLite logs for MVP

### Warp

```
<data-root>/warp.sqlite
```

- Default: `$WARP_HOME` / `$WARP_DIR`, else macOS group container or Linux `~/.local/state/warp-terminal`
- Discover `agent_conversations`; user turns from `ai_queries` (`Query.text`)
- Group projects by `summary.initial_working_directory`
- Adapter: `WarpCatalog` / `WarpTranscript`
- Delete = SQL `DELETE` for that `conversation_id` (ADR 0009). Never `rm` `warp.sqlite`.
- Do not decode `agent_tasks` protobuf in v1

All implement `AgentSessionStore` via `AgentStoreFactory`. 

---

## Delivery phases (don’t skip ahead carelessly)

| Phase | Focus |
|-------|--------|
| **P0** | Core + `asv` + app shell + fixtures — **done** |
| **P1** | Detail stream UI + `asv show` conversation — **done** |
| **P2** | In-app export UI polish |
| **P3** | Installer **PKG only** — `./scripts/package-dmg.sh` — app → `/Applications`, `asv` → `/usr/local/bin` (no DMG) |

Install product rules (ADR 0006):

- **PKG only** on Releases: installs app + CLI with admin auth — no manual copy, no DMG.
- CLI remains installable **standalone** if needed.
- Fallback: `asv` inside the app bundle under `Contents/Resources/bin/`.
- **App icon:** `Assets/asv-icon-1024.png` → `AppIcon.icns` + `CFBundleIconFile=AppIcon` in the packaged `.app` (required; packaging fails if the asset is missing).

---

## When changing behavior

1. Check `docs/adr/` — don’t reverse locked decisions silently.  
2. Update `docs/SPEC.md` if requirements change.  
3. Update `CONTEXT.md` only for **domain terms** (glossary), not implementation notes.  
4. Update this `AGENTS.md` if agent workflow / hard rules change.  
5. Keep `asv --help` and subcommand help accurate when adding CLI flags/commands.  
6. Add/adjust fixtures under `Tests/AgentSessionCoreTests/Fixtures/` and cover with `asv-check` when possible.

---

## Out of scope (v1)

Rewriting/renaming session files · bulk delete · live tail · zip bulk export · App Sandbox / Mac App Store · nested subagent UI · Cursor adapter · cross-agent search · web frontend

---

## Related docs

| File | Role |
|------|------|
| [docs/SPEC.md](docs/SPEC.md) | Full product spec |
| [CONTEXT.md](CONTEXT.md) | Ubiquitous language / glossary |
| [docs/adr/](docs/adr/) | Why we chose SwiftUI, session-delete exception, export shape, naming, CLI install |
| [README.md](README.md) | Human install & command cheat sheet |
