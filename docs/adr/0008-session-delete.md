# Explicit session delete (exception to read-only store)

Users may permanently remove **one** session at a time from the local data root via the viewer (confirmed UI action) or `asv delete` (interactive confirm or `--yes`). Delete is scoped to that session’s primary artifact (`SessionInfo.directoryPath`: Grok directory, Claude/Codex jsonl). ASV still does not rewrite or rename live session files for any other purpose. Supersedes the absolute “never mutate data root” rule in ADR 0002.
