# Agent Session Viewer

Local, read-only **macOS** browser for coding-agent sessions, with companion CLI **`asv`**.

- **v1 agent:** Grok Build (`~/.grok` / `$GROK_HOME`)
- **UI:** SwiftUI three-column shell (Projects → Sessions → Details)
- **CLI:** list / projects / sessions / show / export

See [docs/SPEC.md](docs/SPEC.md) (requirements), [AGENTS.md](AGENTS.md) (coding-agent runbook), and [CONTEXT.md](CONTEXT.md) (domain glossary).

## Requirements

- macOS 14+
- Swift 5.9+ / Xcode 15+

## Build

```bash
cd agent-session-viewer
swift build
swift run asv-check          # fixture smoke tests (works with CLT-only)
# swift test                 # requires full Xcode (XCTest)
```

Install the CLI locally:

```bash
swift build -c release --product asv
cp .build/release/asv /usr/local/bin/asv   # or any directory on your PATH
asv --help
```

## CLI

```bash
asv list
asv projects
asv sessions
asv sessions '%2FUsers%2Fyou%2Fmy-project'   # optional project id (encoded cwd folder)
asv show <session-id>              # metadata + conversation (readable)
asv show <session-id> --full       # full event trace
asv show <session-id> --json       # session + events as JSON
asv export <session-id> --out ./out
asv export --all --out ./out
asv list --home /path/to/grok-home
asv projects --json
```

## macOS app (dev)

```bash
swift run AgentSessionViewer
```

Or open `Package.swift` in Xcode, select the **AgentSessionViewer** scheme, and Run.

The Details column shows Session info and the full Conversation stream (Readable / Full trace). `asv show` prints the same.

## Layout

```
Sources/AgentSessionCore/   # shared discovery, Grok adapter, export
Sources/asv/                # CLI
Sources/AgentSessionViewer/   # SwiftUI app
Tests/AgentSessionCoreTests/
docs/SPEC.md
docs/adr/
CONTEXT.md
```

## Install notes (product)

- **Installer (recommended):** double-click the `.pkg` (from the DMG or standalone). It installs:
  - **Agent Session Viewer.app** → `/Applications`
  - **`asv`** → `/usr/local/bin/asv`  
  No manual drag-and-drop or copy is required (admin password once).
- **CLI-only:** you can still place `asv` on PATH without the GUI if you extract it from a build.
- Fallback: `asv` is also inside the app at `Contents/Resources/bin/asv` (ADR 0006).

### Build installer + DMG (local)

```bash
./scripts/package-dmg.sh
# optional: ASV_VERSION=0.1.0 ./scripts/package-dmg.sh
```

Outputs:

| Artifact | Path |
|----------|------|
| Installer package | `dist/AgentSessionViewer-<version>.pkg` |
| Stable pkg name | `dist/AgentSessionViewer.pkg` |
| DMG (contains the installer) | `dist/AgentSessionViewer-<version>.dmg` |
| Staged app | `dist/stage/Agent Session Viewer.app` |

**User flow:** open the DMG → double-click **Install Agent Session Viewer.pkg** → authenticate → open the app from Applications and run `asv --help` in Terminal.

### GitHub Actions (remote rebuild)

Workflow: [`.github/workflows/build-installer.yml`](.github/workflows/build-installer.yml) (macOS runner).

| Trigger | How |
|---------|-----|
| **Manual / remote CLI** | `gh workflow run build-installer.yml -f version=0.1.0` |
| **Actions UI** | Actions → **Build installer** → Run workflow |
| **API (`repository_dispatch`)** | See below |
| **Tag** | `git tag v0.1.0 && git push origin v0.1.0` (uploads release assets) |
| **Push to `main`** | When `Sources/`, `scripts/`, or packaging paths change |

Artifacts (`.pkg` + `.dmg`) appear under the workflow run → **Artifacts**.

```bash
# Trigger from anywhere with gh authenticated
gh workflow run build-installer.yml --repo leihanchen/agent-session-viewer -f version=0.1.0

# Or via repository_dispatch
gh api repos/leihanchen/agent-session-viewer/dispatches \
  -f event_type=build-installer \
  -f 'client_payload[version]=0.1.0'
```
