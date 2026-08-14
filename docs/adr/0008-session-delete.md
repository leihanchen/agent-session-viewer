# Explicit session delete (exception to read-only store)

Users may permanently remove session(s) from the local data root via the viewer (confirmed UI action, including multi-select bulk delete) or `asv delete` (one id per invocation; interactive confirm or `--yes`). Each delete is scoped to that session’s primary artifact (`SessionInfo.directoryPath`: Grok directory, Claude/Codex jsonl). ASV still does not rewrite or rename live session files for any other purpose, and does not wipe whole data roots. Supersedes the absolute “never mutate data root” rule in ADR 0002.
