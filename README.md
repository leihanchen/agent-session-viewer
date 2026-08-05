# Agent Session Viewer

Local, read-only **macOS** browser for coding-agent sessions, with companion CLI **`asv`**.

| | |
|--|--|
| **Agents** | **Grok Build**, **Claude Code**, and **Codex** (toolbar picker / CLI `--agent`) |
| **UI** | SwiftUI three-column browser (Projects → Sessions → Conversation) |
| **CLI** | `list` / `projects` / `sessions` / `show` / `export` |

See [docs/SPEC.md](docs/SPEC.md) (requirements), [AGENTS.md](AGENTS.md) (coding-agent runbook), [CONTEXT.md](CONTEXT.md) (domain glossary), and [docs/adr/](docs/adr/) (decisions).

**App icon:** packaging builds `AppIcon.icns` from [`Assets/asv-icon-1024.png`](Assets/asv-icon-1024.png) and sets `CFBundleIconFile` so Finder/Dock use it after install.

**Version:** `ASV_VERSION` env, git tag `v*`, or [`VERSION`](VERSION) → `scripts/embed-version.sh` writes `ASVVersion.current`. That value is used by `asv --version` and the app’s `CFBundleShortVersionString` / `CFBundleVersion`.

## Supported agents

| Agent | CLI / export id | Default data root | Env override |
|--------|-----------------|-------------------|--------------|
| **Grok Build** | `grok-build` | `~/.grok` | `$GROK_HOME` |
| **Claude Code** | `claude-code` | `~/.claude` | `$CLAUDE_CONFIG_DIR` or `$CLAUDE_HOME` |
| **Codex** | `codex` | `~/.codex` | `$CODEX_HOME` |

- **App:** segmented control in the toolbar selects the active agent; projects, sessions, conversation, and search apply to **that agent only**.
- **CLI:** pass `--agent grok-build` (default), `claude-code`, or `codex`. Optional `--home <path>` overrides that agent’s data root.
- On-disk layouts differ (Grok: `sessions/<cwd>/<id>/`; Claude: `projects/<cwd>/<id>.jsonl`; Codex: `sessions/YYYY/MM/DD/rollout-*-<id>.jsonl`). All normalize into the same UI/export model. See [ADR 0007](docs/adr/0007-multi-agent-session-stores.md).

## Requirements

- macOS 14+
- Swift 5.9+ / Xcode 15+
- Apple Silicon for the published installer build

## Build

```bash
cd agent-session-viewer
swift build
swift run asv-check          # fixture smoke tests (Grok + Claude; works with CLT-only)
# swift test                 # requires full Xcode (XCTest)
```

Install the CLI locally:

```bash
swift build -c release --product asv
cp .build/release/asv /usr/local/bin/asv   # or any directory on your PATH
asv --help
```

## CLI

One agent per invocation (same idea as the app picker):

```bash
# Grok Build (default)
asv list
asv projects
asv sessions
asv show <session-id>
asv show <session-id> --full
asv export <session-id> --out ./out
asv export --all --out ./out

# Claude Code
asv list --agent claude-code
asv show <session-id> --agent claude-code
asv export --all --agent claude-code --out ./out

# Codex
asv list --agent codex
asv sessions --agent codex
asv show <session-id> --agent codex
asv export --all --agent codex --out ./out

# Overrides
asv list --home /path/to/grok-home
asv list --agent codex --home /path/to/codex-home
asv projects --json
asv show <session-id> --json
```

| Flag | Meaning |
|------|---------|
| `--agent` | `grok-build` (default), `claude-code`, or `codex` |
| `--home` | Override data root for that agent |
| `--json` | Machine-readable output (`list` / `projects` / `sessions` / `show`) |
| `--full` | Full event trace on `show` (default is readable/coalesced) |

Export JSON includes `"agent": "grok-build"`, `"claude-code"`, or `"codex"`.

## macOS app (dev)

```bash
swift run AgentSessionViewer
```

Or open `Package.swift` in Xcode, select the **AgentSessionViewer** scheme, and Run.

### UI notes

- Toolbar: **Grok Build | Claude Code | Codex**, data root path, Readable / Full trace, Refresh.
- Search field: **Search all conversations…** — full-text over **every session of the selected agent** (not across agents). Empty query lists all sessions for that agent.
- Details: Session info + conversation stream; matches highlight when searching.

## Layout

```
Sources/AgentSessionCore/
  Agent/                 # AgentSessionStore protocol + factory
  Grok/                  # Grok Build adapter
  Claude/                # Claude Code adapter
  Codex/                 # OpenAI Codex adapter
  Search/                # Conversation search
  Export/
Sources/asv/             # CLI
Sources/AgentSessionViewer/
Tests/AgentSessionCoreTests/Fixtures/
  grok-home/
  claude-home/
  codex-home/
docs/SPEC.md
docs/adr/
CONTEXT.md
AGENTS.md
```

## Install notes (product)

- **Installer (only distribution format):** double-click the `.pkg`. It installs:
  - **Agent Session Viewer.app** → `/Applications`
  - **`asv`** → `/usr/local/bin/asv`  
  Admin password once; no drag-and-drop, no separate CLI copy, **no DMG**.
- **CLI-only:** you can still place `asv` on PATH without the GUI if you extract it from a build.
- Fallback: `asv` is also inside the app at `Contents/Resources/bin/asv` (ADR 0006).

### Build installer (local)

```bash
./scripts/package-dmg.sh
# optional: ASV_VERSION=0.1.0 ./scripts/package-dmg.sh
```

Outputs:

| Artifact | Path |
|----------|------|
| Installer package | `dist/AgentSessionViewer-<version>.pkg` |
| Stable pkg name | `dist/AgentSessionViewer.pkg` |
| Staged app | `dist/stage-build/Agent Session Viewer.app` |

**User flow:** download **AgentSessionViewer-x.y.z.pkg** from Releases → double-click → authenticate → open the app from Applications and run `asv --help` in Terminal.

If the CLI installs but the app does not appear under `/Applications`, you may have an older relocatable package that updated a build copy instead. Clean and reinstall:

```bash
sudo pkgutil --forget app.agentsessionviewer.pkg
sudo rm -rf "/Applications/Agent Session Viewer.app"
sudo rm -rf /path/to/repo/dist/stage   # only if a root-owned leftover exists there
# then double-click the new AgentSessionViewer-*.pkg
```

### GitHub Actions (remote rebuild)

Workflow: [`.github/workflows/build-installer.yml`](.github/workflows/build-installer.yml) (macOS runner).

| Trigger | How |
|---------|-----|
| **Manual / remote CLI** | `gh workflow run build-installer.yml -f version=0.1.0` |
| **Actions UI** | Actions → **Build installer** → Run workflow |
| **API (`repository_dispatch`)** | See below |
| **Tag** | `git tag v0.1.0 && git push origin v0.1.0` (uploads release assets) |
| **Push to `main`** | When `Sources/`, `scripts/`, or packaging paths change |

Artifacts (`.pkg` only) appear under the workflow run → **Artifacts**, and on tag Releases.

```bash
# Trigger from anywhere with gh authenticated
gh workflow run build-installer.yml --repo leihanchen/agent-session-viewer -f version=0.1.0

# Or via repository_dispatch
gh api repos/leihanchen/agent-session-viewer/dispatches \
  -f event_type=build-installer \
  -f 'client_payload[version]=0.1.0'
```
