# Changelog

All notable changes to **Agent Session Viewer** are documented here.

## [0.2.0] — 2026-08-05

### Highlights

Multi-agent browsing, full conversation search, and a reliable macOS PKG installer.

### Added

- **Claude Code** adapter (`~/.claude` / `$CLAUDE_CONFIG_DIR` / `$CLAUDE_HOME`)
- **Codex** adapter (`~/.codex` / `$CODEX_HOME`) for `sessions/**/rollout-*.jsonl`
- Toolbar **agent picker** (segmented: Grok Build | Claude Code | Codex)
- CLI **`--agent grok-build|claude-code|codex`** (default `grok-build`)
- **Conversation search** across all sessions of the selected agent (rank by match count, highlight query)
- Full **conversation stream** in the UI Details column and `asv show` (`--full` / `--json`)
- **PKG installer** placing the app in `/Applications` and `asv` in `/usr/local/bin` (no DMG)
- App icon from `Assets/` as `AppIcon.icns`
- Version embedding (`ASVVersion.current` ↔ `asv --version` ↔ CFBundle versions)
- GitHub Actions installer workflow

### Fixed

- PKG bundle relocation so the app always installs under `/Applications` (not a relocatable build path)
- Installer packaging: PKG-only releases

### Docs

- Multi-agent layouts and CLI usage in README, AGENTS, CONTEXT, SPEC
- ADR 0007 multi-agent stores; ADR 0006 CLI/app install

### Install (v0.2.0)

1. Download **AgentSessionViewer-0.2.0.pkg** from [Releases](https://github.com/leihanchen/agent-session-viewer/releases/tag/v0.2.0)
2. Double-click → enter admin password
3. Open **Agent Session Viewer** from Applications; run `asv --help` in Terminal

**Requirements:** macOS 14+, Apple Silicon. Ad-hoc signed — first open may need **right-click → Open**.

## [0.1.0] — 2026-08-04

Initial public installer: Grok Build sessions, three-column viewer shell, `asv` list/export, basic PKG packaging.
