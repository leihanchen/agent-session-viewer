# Normalized JSON export, not raw agent directories

CLI and GUI export produce one portable JSON file per Session (Session info + full Event trace), written into a directory for bulk export. We do not ship a productized “zip of raw agent session files” as the primary export: those layouts already exist on disk and differ per agent, while a stable normalized schema (with an agent identifier) is what viewers and scripts should depend on.
