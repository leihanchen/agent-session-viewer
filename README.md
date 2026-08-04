# Agent Session View

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
cd agent-session-view
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
asv show <session-id>
asv export <session-id> --out ./out
asv export --all --out ./out
asv list --home /path/to/grok-home
asv projects --json
```

## macOS app (dev)

```bash
swift run AgentSessionView
```

Or open `Package.swift` in Xcode, select the **AgentSessionView** scheme, and Run.

P0 ships discovery + session info; full conversation stream UI is P1.

## Layout

```
Sources/AgentSessionCore/   # shared discovery, Grok adapter, export
Sources/asv/                # CLI
Sources/AgentSessionView/   # SwiftUI app
Tests/AgentSessionCoreTests/
docs/SPEC.md
docs/adr/
CONTEXT.md
```

## Install notes (product)

- **CLI-only:** ship/install `asv` without the GUI.
- **DMG:** app + top-level `asv` + CLI also inside the app bundle (ADR 0006).

### Build a DMG

```bash
./scripts/package-dmg.sh
# optional: ASV_VERSION=0.1.0 ./scripts/package-dmg.sh
```

Outputs:

- `dist/AgentSessionView-<version>.dmg`
- `dist/AgentSessionView.dmg` (same file, stable name)
- Staged app: `dist/stage/Agent Session View.app`

DMG contents: drag **Agent Session View.app** → Applications, copy **asv** to PATH (or run the install script inside the app).
