# Read-only access to agent session stores

**Status: superseded by [ADR 0008](0008-session-delete.md).**

Original decision: Agent Session Viewer only reads (and copies out via export) data under configured Data roots. It never deletes, renames, or rewrites session files for any agent. Mutating a live agent store risks corrupting resume state and racing that agent’s own tools; export already covers taking data elsewhere.

**Supersession:** confirmed single-session delete is now allowed (UI + `asv delete`). All other mutations of agent data roots remain forbidden.
