# Warp sessions live in warp.sqlite (SQL delete)

Warp agent conversations are stored as rows in `warp.sqlite` (macOS: Warp-Stable group container), not per-session files. ASV lists `agent_conversations`, reconstructs user turns from `ai_queries`, and deletes a session with a SQL transaction on that conversation id only — never by removing the sqlite file. Assistant/tool proto blobs in `agent_tasks` are not decoded in v1.
