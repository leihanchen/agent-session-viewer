# AGENTS.md — coding agent memory

Instructions for AI coding agents working in **this repository**. Keep changes aligned with the product decisions below; prefer reading `docs/SPEC.md` for full requirements and `CONTEXT.md` for domain vocabulary.

---

## What this project is

**Agent Session Viewer** — local, **read-only** macOS app + companion CLI **`asv`** for browsing and exporting coding-agent sessions on disk.

| Surface | Name |
|---------|------|
| macOS app | Agent Session Viewer |
| CLI binary | `asv` |
| Shared library | `AgentSessionCore` |

- **English UI only**
- **v1 agent store:** Grok Build only (`~/.grok` / `$GROK_HOME` / `--home`)
- **Future:** more agents behind the same models; do **not** bake “Grok” into product/CLI names
- **Not:** a website, WebView app, cloud service, or session editor

---

## Hard rules (do not violate)

1. **Read-only toward agent data roots** — never delete, rename, rewrite, or “fix” files under `~/.grok` (or any Data root). Export only **writes** under a user-chosen output path.
2. **No network required** for browse/export.
3. **SwiftUI + Swift** for app and CLI — not Tauri, Electron, or a web UI stack (ADR 0001).
4. **Non-sandboxed** local app for v1 (must read outside the app container).
5. Prefer **agent-agnostic** types in Core (`Project`, `Session`, `Event`, `ExportBundle`); put Grok layout parsing under `Sources/AgentSessionCore/Grok/`.
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
ASV_VERSION=0.1.0 ./scripts/package-dmg.sh   # PKG only; Info.plist matches asv --version
```

**Version source of truth:** `scripts/embed-version.sh` → `VERSION` + `Sources/AgentSessionCore/Version.swift` (`ASVVersion.current`). Used by CLI and CFBundleShortVersionString.

### CI (GitHub Actions)

- Workflow: `.github/workflows/build-installer.yml` on **macos-14**
- Rebuilds installer remotely via:
  - `workflow_dispatch` (`gh workflow run build-installer.yml -f version=0.1.0`)
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

Common flags: `--home <path>`, `--json` (list/projects/sessions/show), `--full` (`show`), `--out <dir>` (export).

Export = **one JSON file per session**, full event trace, fields at least: `schema_version`, `agent` (e.g. `"grok-build"`), session info, `events[]`. Bulk export = directory of files (not zip in v1).

---

## UI contract (app)

Three columns (CC LOG–style, English):

1. **Projects** — cwd groups  
2. **Sessions** — title, dates, counts  
3. **Details** — Session info + **Conversation** (every message/event)  

- **Session title:** summary → first user message → short id  
- **Readable mode** (default): coalesced turns; **Full trace** toolbar toggle: every event  
- Load via `SessionTranscript.events(for:mode:)` from `updates.jsonl`  
- **One search field only:** “Search all conversations…” — full-text across every session (debounced); not project metadata. Results sorted by match count then `updatedAt`; highlight in snippets + detail (`ConversationSearch` + `HighlightedText`). Empty query lists all sessions. 
- Subagent sessions: **flat peers** (no nesting in v1)  
- Snapshot load / Refresh only — no live file watching in v1  

---

## Grok on-disk layout (v1 adapter)

```
<data-root>/sessions/<percent-encoded-cwd>/<session-id>/
  summary.json      # metadata / title
  updates.jsonl     # authoritative conversation + tool stream
  ...
```

- Default data root: `$GROK_HOME` or `~/.grok`  
- Skip non-directory entries under `sessions/` (e.g. sqlite indexes)  
- Parse via `GrokCatalog` / `GrokUpdates`; keep export normalized, not a raw dir copy  

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

Writing/deleting agent session files · live tail · full-text body search · zip bulk export · App Sandbox / Mac App Store · nested subagent UI · second agent adapter (design only) · web frontend

---

## Related docs

| File | Role |
|------|------|
| [docs/SPEC.md](docs/SPEC.md) | Full product spec |
| [CONTEXT.md](CONTEXT.md) | Ubiquitous language / glossary |
| [docs/adr/](docs/adr/) | Why we chose SwiftUI, read-only, export shape, naming, CLI install |
| [README.md](README.md) | Human install & command cheat sheet |
