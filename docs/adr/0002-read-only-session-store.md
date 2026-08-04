# Read-only access to agent session stores

Agent Session Viewer only reads (and copies out via export) data under configured Data roots. It never deletes, renames, or rewrites session files for any agent. Mutating a live agent store risks corrupting resume state and racing that agent’s own tools; export already covers taking data elsewhere.
