# CLI installable standalone or bundled with the app

`asv` is a first-class deliverable, not only an internal helper. Users may install the CLI alone (CLI-only install) for scripting without the GUI. App distribution (DMG) must also support obtaining the CLI: either bundle `asv` in the DMG and offer install-to-PATH / copy into the app package, or document a same-release CLI artifact. The shared library powers both so behavior stays identical.
