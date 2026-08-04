# Agent Session View

A local, read-only macOS application (with companion CLI) for browsing and exporting coding-agent sessions stored on disk. English UI only. v1 focuses on Grok Build sessions; the product is named and structured so additional agents can be added later.

## Language

**Agent Session View**:
The product: a native macOS application that visualizes coding-agent sessions and exports them. English UI only.
_Avoid_: Grok Session Viewer, Grok Log, CC LOG, web viewer, online viewer, Agent Session Viewer (prefer “View” as the product name)

**asv**:
The companion command-line binary for listing and exporting sessions without opening the GUI. Installable on its own or bundled with the app distribution.
_Avoid_: gsv

**Agent**:
A coding-agent product whose on-disk sessions Agent Session View can read. v1 supports Grok Build only; the domain model stays agent-agnostic where practical.
_Avoid_: model (use for LLM id), provider (too vague)

**Grok home**:
The root directory of Grok Build’s on-disk state. Defaults to `~/.grok`, or `$GROK_HOME` when set; the user may override the path in the app or CLI. Not a network service.
_Avoid_: server, cloud, remote data root

**Data root**:
The configured on-disk root from which sessions are discovered for a given Agent. For Grok Build this is Grok home. Future agents will each have their own default root and override.

**Project**:
A working-directory group under a Data root that owns zero or more Sessions. For Grok Build this is an encoded cwd folder under `sessions/`. Displayed by path/name in the Projects column.
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
The ordered sequence of Events for one Session shown in the Details column.

**Event**:
A single item in the Detail stream: user message, assistant message, tool use, tool result, error, or similar agent-trace record. Normalized across agents at the Export bundle boundary.

**Full trace**:
Detail stream mode (and CLI export content) that includes every Event, including tool payloads, not only human-readable chat text.
_Avoid_: debug dump, raw agent files (on-disk layout, not the normalized model)

**Readable mode**:
UI Detail stream mode that emphasizes user/assistant text and collapses tool I/O behind chips/summaries. Toggleable to Full trace.

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
