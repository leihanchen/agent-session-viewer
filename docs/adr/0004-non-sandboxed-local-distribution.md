# Non-sandboxed local distribution for v1

Agent Session Viewer must freely read Data roots (e.g. Grok home under `~/.grok` or an override). v1 is a non-sandboxed local macOS app plus `asv` CLI — not Mac App Store / App Sandbox. Sandbox plus security-scoped folder picks would slow the core “see my sessions” loop for a personal developer tool.
