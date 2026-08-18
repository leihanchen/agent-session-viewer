# Warp sessions live in warp.sqlite (SQL delete)

Warp agent conversations are stored as rows in `warp.sqlite`, not per-session files. Default root is the macOS Warp-Stable group container, or `~/.local/state/warp-terminal` on Linux (`$WARP_HOME` / `$WARP_DIR` override). ASV lists `agent_conversations`, reconstructs user turns from `ai_queries`, and deletes a session with a SQL transaction on that conversation id only — never by removing the sqlite file. Assistant/tool proto blobs in `agent_tasks` are not decoded in v1.
