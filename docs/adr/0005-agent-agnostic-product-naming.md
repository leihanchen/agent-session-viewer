# Product named Agent Session Viewer (`asv`), not Grok-specific

The first supported Agent is Grok Build, but the product will gradually support multiple coding agents. The macOS app is **Agent Session Viewer**; the CLI binary is **`asv`**. Domain types (Project, Session, Event, Export bundle) stay agent-agnostic; agent-specific parsers adapt on-disk formats into that model. Avoid baking “Grok” into the product or CLI name.
