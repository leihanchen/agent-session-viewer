# Agent Session Viewer — Product Spec (v1)

**Status:** P0 + P1 complete — Core, `asv` (including conversation `show`), SwiftUI Detail stream (Readable / Full trace), export, DMG packaging.  
**Repo:** `/Users/mac/Documents/github_repo/agent-session-viewer`  
**UI language:** English only  
**Related:** `CONTEXT.md`, `docs/adr/0001`–`0006`

---

## 1. Summary

**Agent Session Viewer** is a local, read-only macOS app that visualizes coding-agent sessions on disk in a three-column UI (Projects → Sessions → Details), with a companion CLI **`asv`** for list/export.

- **v1 Agent:** Grok Build only (`~/.grok` / `$GROK_HOME` / override).
- **Future:** additional Agents behind the same UI and Export bundle schema.
- **Not:** a website, cloud service, WebView shell, or session editor.

---

## 2. Goals

| ID | Goal |
|----|------|
| G1 | Browse all discoverable Sessions for the configured Data root without using the agent TUI. |
| G2 | Inspect Session info and a full Detail stream (readable or full-trace UI). |
| G3 | Export Sessions as portable normalized JSON (one file per Session). |
| G4 | Script discovery and export via `asv` without opening the GUI. |
| G5 | Install `asv` **standalone** or obtain it **with** the app DMG distribution. |
| G6 | Keep names and schemas agent-agnostic so more Agents can be added later. |

## 3. Non-goals (v1)

- Writing, deleting, or renaming anything under an agent Data root.
- Live file watching / auto-tail of sessions.
- Full-text search inside conversation bodies (metadata search only).
- Nested subagent parent/child UI (subagent Sessions appear as flat peers).
- Zip packaging of bulk exports.
- Mac App Store / App Sandbox.
- Multi-Agent UI chrome (no agent picker required until a second Agent ships).
- Supporting Claude Code / Cursor / Codex session stores in v1 (design only reserves room).

---

## 4. Personas & primary loop

**User:** developer who already uses Grok Build (and later other coding agents) and wants to review past work, tool traces, and export history.

**Primary loop:**

1. Launch **Agent Session Viewer** (or use `asv` for export-only workflows).
2. See **Projects** (cwd groups) for the current Data root.
3. Select a Project → see **Sessions** (titles, dates, counts).
4. Select a Session → see **Session info** + **Detail stream**.
5. Toggle Readable / Full trace; export one or all Sessions as needed.

---

## 5. Product naming

| Surface | Name |
|---------|------|
| macOS app (menu bar, About, window) | **Agent Session Viewer** |
| CLI binary | **`asv`** |
| Bundle / project folder | `agent-session-viewer` (recommended) |
| Deprecated | “Grok Session Viewer”, `gsv` |

---

## 6. Functional requirements

### 6.1 Data discovery (Grok Build adapter — v1)

| ID | Requirement |
|----|-------------|
| D1 | Default Data root = `~/.grok` if `$GROK_HOME` unset; else `$GROK_HOME`. |
| D2 | User may override Data root in app Settings and via CLI `--home <path>`. |
| D3 | Discover Projects as child directories of `<data-root>/sessions/` (URL-encoded cwd groups per Grok layout). |
| D4 | Discover Sessions as child directories containing Grok session artifacts (`summary.json`, etc.). |
| D5 | Load is **snapshot-based**: on open, project/session select, or explicit Refresh. No FS watcher in v1. |
| D6 | Never write to the Data root (read-only; ADR 0002). |

**Authoritative Grok sources (implementation reference):**

- Index/metadata: `summary.json`
- Conversation / tool trace: `updates.jsonl` (preferred for Detail stream)
- Optional fallbacks for title: first user-visible message from the stream when summary empty

### 6.2 UI — three columns (CC LOG–inspired, English)

| ID | Requirement |
|----|-------------|
| U1 | Layout: **Projects** \| **Sessions** \| **Details** (and Session info within Details or a header card). |
| U2 | **Projects:** show project label (folder basename and/or path), session count, last updated when known. |
| U3 | **Sessions:** show Session title, timestamps, message/tool counts when available. |
| U4 | **Session title** resolution: non-empty summary → truncated first user message → short session id. |
| U5 | **Details:** Session info card **plus** chronological Conversation Event list (user, assistant, thinking, tool_use, tool_result) with timestamps and role labels. |
| U6 | **Readable mode (default):** consecutive text chunks coalesced into turns; long bodies collapsible (“Show more”); hook/noise types hidden. |
| U7 | **Full trace mode:** toolbar toggle shows every normalized Event including thinking and tool args/results. |
| U8 | Header chrome: product name, Data root path, Refresh control; optional index/session counts. |
| U9 | **One toolbar search (UI):** searches **all** sessions’ full conversation bodies (case-insensitive). Matching sessions appear in the Sessions column, sorted by match count then recency; snippets and detail stream **highlight** the query. Empty query lists every session (all projects). Not a project-name filter. |
| U10 | Subagent Sessions listed as **flat peers** under the Project. |
| U11 | Export actions: export current Session; export all Sessions in current Project or all Projects (bulk → directory). |
| U12 | English UI strings only. |

### 6.3 Export

| ID | Requirement |
|----|-------------|
| E1 | One **Export bundle** JSON file per Session. |
| E2 | Export content is **full trace** (all Events + Session info), regardless of UI Readable mode. |
| E3 | Bulk export writes many JSON files into a user-chosen **directory** (not zip in v1). |
| E4 | Schema is **normalized** and includes at least: `schema_version`, `agent` (e.g. `"grok-build"`), session id, Session info fields, ordered `events[]`. |
| E5 | Export never mutates the source Data root; it only creates files under the user-chosen output path. |

**Export bundle (v1 sketch — finalize during implementation):**

```json
{
  "schema_version": 1,
  "agent": "grok-build",
  "exported_at": "ISO-8601",
  "session": {
    "id": "...",
    "title": "...",
    "cwd": "...",
    "created_at": "...",
    "updated_at": "...",
    "model": "...",
    "message_count": 0,
    "extra": {}
  },
  "events": [
    {
      "type": "user|assistant|tool_use|tool_result|error|other",
      "timestamp": "...",
      "role": "...",
      "content": "...",
      "tool": { "name": "...", "id": "...", "input": {}, "output": {}, "is_error": false },
      "raw": {}
    }
  ]
}
```

`raw` may hold agent-specific fields for lossless-enough export without forcing every agent into identical internal shapes.

### 6.4 CLI (`asv`)

| ID | Requirement |
|----|-------------|
| C1 | Binary name: **`asv`**. |
| C2 | Commands (v1): |
| | `asv list` — overview (projects + session counts) |
| | `asv projects` — list Projects |
| | `asv sessions [project]` — list Sessions (optional project filter) |
| | `asv show <session-id> [--full] [--json]` — metadata + full conversation (readable default; `--full` = full trace) |
| | `asv export <session-id\|--all> [--out <dir>] [--home <path>]` — full-trace Export bundles |
| C3 | Global/common flags: `--home <path>` (Data root override), stable machine-readable output where useful (`--json` on list/show optional but recommended). |
| C4 | Exit non-zero on missing paths, unknown session ids, and write failures; print clear errors to stderr. |
| C5 | Shared core library with the app: same discovery, title rules, and export schema. |

### 6.5 Installation & distribution

| ID | Requirement |
|----|-------------|
| I1 | **Non-sandboxed** local macOS app (ADR 0004). Not App Store for v1. |
| I2 | **CLI-only install:** users can install `asv` **without** the GUI (documented release artifact and/or package manager formula later). |
| I3 | **Installer package only:** a macOS `.pkg` installs **Agent Session Viewer.app** to `/Applications` and **`asv`** to `/usr/local/bin` with a single Installer run (admin password). Users must **not** need to drag-copy. **No DMG** is required or published. |
| I3b | **Fallback:** `asv` may also live at `Agent Session Viewer.app/Contents/Resources/bin/asv` for recovery if PATH install is removed. |
| I4 | GUI and CLI from the same version must produce compatible Export bundles (`schema_version` + `agent`). |
| I5 | README documents: run installer PKG, open app, override Data root, CLI-only options, uninstall paths. |

---

## 7. UX reference

Inspired by local log viewers such as “CC LOG” (three columns: project list, session list, event detail with tool badges). Visual styling may be dark, dense, card-based; implementation is **SwiftUI**, not HTML.

Mock expectations:

- Left: Projects with path + counts  
- Middle: Sessions with title + stats  
- Right: Event stream with tool_use / tool_result / errors  

---

## 8. Architecture (implementation guide)

```
agent-session-viewer/
  Package.swift or Xcode project
  Sources/
    AgentSessionCore/     # discovery, parsers, export, title rules
      Grok/               # v1 adapter: Grok home layout
    asv/                  # CLI executable target
    AgentSessionViewer/     # SwiftUI macOS app target
  Tests/
    AgentSessionCoreTests/
  docs/
    SPEC.md
    adr/
  CONTEXT.md
```

| Layer | Responsibility |
|-------|----------------|
| **Core** | Data root resolution, Project/Session models, Grok parser, Event normalization, export writers |
| **App** | SwiftUI three-column UI, settings (Data root), export panels, refresh |
| **CLI** | Argument parsing, stdout/stderr, calls Core only |

**Future Agents:** add `Sources/AgentSessionCore/<Agent>/` adapters implementing a shared protocol; UI gains an agent filter only when needed.

---

## 9. Quality bar

| ID | Requirement |
|----|-------------|
| Q1 | Unit tests for Grok discovery against fixture trees (encoded cwd, sample `summary.json` + `updates.jsonl`). |
| Q2 | Unit tests for Session title fallbacks and export JSON shape (`schema_version`, `agent`, non-empty events when fixtures have them). |
| Q3 | CLI smoke: `asv projects` / `asv export` against fixtures in CI or local script. |
| Q4 | App builds for Apple Silicon (and Intel if trivial); minimum macOS version chosen at scaffold (recommend macOS 14+ unless constrained). |

---

## 10. Security & privacy

| ID | Requirement |
|----|-------------|
| S1 | All data stays on local disk; no telemetry required for v1 core features. |
| S2 | Export may contain secrets from tool output; document that Export bundles should be treated as sensitive. |
| S3 | No network calls required to browse or export (v1). |

---

## 11. Phased delivery

| Phase | Deliverable | Status |
|-------|-------------|--------|
| **P0** | Core + `asv` list/projects/sessions + app shell + fixtures | Done |
| **P1** | Detail stream: UI Conversation + `asv show` prints all messages; Readable / Full trace | Done |
| **P2** | Export CLI + core export API (app export button optional polish) | Mostly done (CLI export) |
| **P3** | PKG installer only → `/Applications` + `/usr/local/bin` (no DMG) | Done (`scripts/package-dmg.sh`) |
| **Later** | Full-text search; live refresh; second Agent adapter; zip export; nested subagents; in-app export UI | |

---

## 12. Acceptance criteria (v1 done)

1. Opening the app on a machine with Grok sessions shows Projects and Sessions without network.
2. Selecting a Session shows Session info and Events; Full trace reveals tool payloads.
3. `asv export --all --out /tmp/asv-out` writes one JSON file per Session with `schema_version` and `agent: "grok-build"`.
4. `asv` runs when installed without the GUI.
5. Installer package places the app in `/Applications` and `asv` in `/usr/local/bin` without manual copy; Releases ship the `.pkg` only.
6. No code path deletes or rewrites files under Grok home.
7. UI strings are English; product name is Agent Session Viewer; CLI is `asv`.

---

## 13. Open points (non-blocking for scaffold)

- Exact DMG layout (in-bundle binary + “Install CLI” vs side-by-side binary).
- Minimum macOS version (default **14** unless you need older).
- Whether `--json` is mandatory on all list commands in v1 or added in P0.5.
- Precise Event `type` enum after sampling real `updates.jsonl` shapes.

These can be decided during P0/P3 without changing the product goals above.
