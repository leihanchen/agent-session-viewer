# Agent Session Viewer

A local macOS application (with companion CLI) for browsing, exporting, and optionally deleting coding-agent sessions stored on disk. English UI only. Supports Grok Build, Claude Code, Codex, and Warp via an agent picker. Browse/export are non-mutating; delete permanently removes selected session(s) after confirmation.

## Language

**Agent Session Viewer**:
The product: a native macOS application that visualizes coding-agent sessions and exports them. English UI only.
_Avoid_: Agent Session View, Grok Session Viewer (as product name), Grok Log, CC LOG, web viewer, online viewer

**asv**:
The companion command-line binary for listing, exporting, and deleting sessions without opening the GUI. Installable on its own or bundled with the app distribution.
_Avoid_: gsv

**Session delete**:
Permanently remove Session artifacts from the local Agent data root after UI confirmation or `asv delete --yes` / interactive confirm (Grok directory; Claude/Codex jsonl; Warp conversation rows in `warp.sqlite`). Irreversible. Viewer may delete several selected Sessions at once.
_Avoid_: soft delete, trash, wipe project

**Agent**:
A coding-agent product whose on-disk sessions Agent Session Viewer can read. Supported: Grok Build, Claude Code, Codex, Warp. Domain model stays agent-agnostic where practical.
_Avoid_: model (use for LLM id), provider (too vague)

**Agent picker**:
Toolbar control that selects the active Agent; browse, search, and export apply to that Agent only.

**Grok home**:
The root directory of Grok Build’s on-disk state. Defaults to `~/.grok`, or `$GROK_HOME` when set.
_Avoid_: server, cloud, remote data root

**Claude home**:
The root directory of Claude Code’s on-disk state. Defaults to `~/.claude`, or `$CLAUDE_CONFIG_DIR` / `$CLAUDE_HOME` when set.
_Avoid_: Claude.ai web history, Anthropic cloud

**Codex home**:
The root directory of OpenAI Codex’s on-disk state. Defaults to `~/.codex`, or `$CODEX_HOME` when set.
_Avoid_: ChatGPT web history

**Warp home**:
The directory that contains Warp’s `warp.sqlite`. Defaults to the macOS group container `…/dev.warp.Warp-Stable/`, or `~/.local/state/warp-terminal` on Linux, or `$WARP_HOME` / `$WARP_DIR` when set.
_Avoid_: Warp cloud conversations, Warp Drive

**Data root**:
The configured on-disk root for the selected Agent (Grok, Claude, Codex, or Warp home).

**Project**:
A working-directory group under a Data root that owns zero or more Sessions (Grok: encoded cwd under `sessions/`; Claude: folder under `projects/`; Codex/Warp: grouped by session `cwd`).
_Avoid_: repository (unless referring to git metadata on a session), workspace (ambiguous with editor workspaces)

**Session**:
One persistent agent conversation under a Project, identified by a session id, with Session info and a Detail stream.
_Avoid_: chat (too vague), thread (ambiguous with UI threads)

**Session info**:
Metadata about a Session (id, title/summary, timestamps, model, message counts, cwd, agent, git hints when present).

**Session title**:
The display name of a Session in lists. Prefer non-empty summary/title from the agent store; else a truncated first user message; else a short form of the session id.
_Avoid_: always using raw UUID as the only label

**Detail stream**:
The ordered sequence of Events for one Session shown in the Details column (Conversation). Loaded from the agent’s on-disk log (`updates.jsonl` for Grok Build).

**Event**:
A single item in the Detail stream: user message, assistant message, thinking, tool use, tool result, error, or similar agent-trace record. Normalized across agents at the Export bundle boundary.

**Conversation search**:
UI search that finds Sessions whose Detail stream text contains a query, ranks them, and highlights matches. Empty query means normal project browse.
_Avoid_: project-only filter (that is browse metadata filtering, not conversation search)

**Readable mode**:
Detail stream presentation that coalesces consecutive text chunks into turns and de-emphasizes noise; default for UI and `asv show`.
_Avoid_: summary-only view (implies messages are omitted)

**Full trace**:
Detail stream that lists every normalized Event without coalescing (UI toggle / `asv show --full`). Export always uses full trace.
_Avoid_: debug dump, raw agent files (on-disk layout, not the normalized model)

**Export bundle**:
A normalized portable JSON document for one Session: Session info plus the full Event trace. One file per Session. Agent-agnostic schema with an agent identifier field. Not a raw copy of any agent’s session directory.
_Avoid_: backup, archive of ~/.grok, raw session dir

**Bulk export**:
Writing many Export bundles as individual JSON files into a directory (not a zip in v1).

**Subagent session**:
A Session created for a subagent. In v1 it appears as a flat peer Session under the same Project, with no parent/child nesting in the UI.

**App distribution**:
How the macOS application is delivered (e.g. DMG). May bundle the `asv` CLI for optional install onto PATH.

**CLI-only install**:
Installing the `asv` binary without installing the macOS GUI app (e.g. Homebrew, direct binary, or “CLI only” from the same release artifacts).
