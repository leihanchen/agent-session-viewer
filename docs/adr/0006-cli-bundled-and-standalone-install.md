# CLI installable standalone or via installer with the app

`asv` is a first-class deliverable. Users may install the CLI alone (copy the binary or a future formula). App distribution ships a **macOS Installer package** (`.pkg`, also wrapped in a DMG) that places **Agent Session Viewer.app** in `/Applications` and **`asv`** in `/usr/local/bin` so the user does not need to drag-copy files. The shared library powers both so behavior stays identical. A fallback copy of `asv` remains inside the app bundle under `Contents/Resources/bin/`.
