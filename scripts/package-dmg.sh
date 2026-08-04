#!/usr/bin/env bash
# Build release binaries, assemble .app + asv, and produce a DMG.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Agent Session View"
BIN_NAME="AgentSessionView"
CLI_NAME="asv"
BUNDLE_ID="app.agentsessionview.viewer"
VERSION="${ASV_VERSION:-0.1.0}"
MIN_MACOS="14.0"

DIST="$ROOT/dist"
STAGE="$DIST/stage"
DMG_ROOT="$DIST/dmg-root"
APP_BUNDLE="$STAGE/${APP_NAME}.app"
DMG_PATH="$DIST/AgentSessionView-${VERSION}.dmg"
VOL_NAME="Agent Session View"

echo "==> Building release products…"
swift build -c release --product AgentSessionView
swift build -c release --product asv

APP_BIN="$ROOT/.build/release/${BIN_NAME}"
CLI_BIN="$ROOT/.build/release/${CLI_NAME}"
test -x "$APP_BIN"
test -x "$CLI_BIN"

echo "==> Assembling app bundle…"
rm -rf "$STAGE" "$DMG_ROOT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$APP_BIN" "$APP_BUNDLE/Contents/MacOS/${BIN_NAME}"
chmod +x "$APP_BUNDLE/Contents/MacOS/${BIN_NAME}"

# Bundle CLI inside the app (ADR 0006) and also ship a top-level copy on the DMG.
cp "$CLI_BIN" "$APP_BUNDLE/Contents/Resources/bin/${CLI_NAME}"
chmod +x "$APP_BUNDLE/Contents/Resources/bin/${CLI_NAME}"

# Helper: install CLI to /usr/local/bin (optional, run by user)
cat > "$APP_BUNDLE/Contents/Resources/bin/install-asv.sh" << 'EOF'
#!/usr/bin/env bash
set -euo pipefail
SRC="$(cd "$(dirname "$0")" && pwd)/asv"
DEST_DIR="${1:-/usr/local/bin}"
DEST="${DEST_DIR}/asv"
if [[ ! -x "$SRC" ]]; then
  echo "asv binary not found next to this script: $SRC" >&2
  exit 1
fi
mkdir -p "$DEST_DIR"
cp "$SRC" "$DEST"
chmod +x "$DEST"
echo "Installed: $DEST"
"$DEST" --version || true
EOF
chmod +x "$APP_BUNDLE/Contents/Resources/bin/install-asv.sh"

# Info.plist
cat > "$APP_BUNDLE/Contents/Info.plist" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleDevelopmentRegion</key>
	<string>en</string>
	<key>CFBundleExecutable</key>
	<string>${BIN_NAME}</string>
	<key>CFBundleIdentifier</key>
	<string>${BUNDLE_ID}</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleName</key>
	<string>${APP_NAME}</string>
	<key>CFBundleDisplayName</key>
	<string>${APP_NAME}</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<key>LSMinimumSystemVersion</key>
	<string>${MIN_MACOS}</string>
	<key>LSApplicationCategoryType</key>
	<string>public.app-category.developer-tools</string>
	<key>NSHighResolutionCapable</key>
	<true/>
	<key>NSPrincipalClass</key>
	<string>NSApplication</string>
	<key>CFBundleSupportedPlatforms</key>
	<array>
		<string>MacOSX</string>
	</array>
</dict>
</plist>
EOF

# PkgInfo
echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

# Install notes inside the app (Helpful for first run)
cat > "$APP_BUNDLE/Contents/Resources/INSTALL-CLI.txt" << EOF
Agent Session View — CLI (${CLI_NAME})

The ${CLI_NAME} binary is bundled at:

  ${APP_NAME}.app/Contents/Resources/bin/${CLI_NAME}

Install onto your PATH (example):

  "${APP_NAME}.app/Contents/Resources/bin/install-asv.sh"
  # or:
  cp "${APP_NAME}.app/Contents/Resources/bin/${CLI_NAME}" /usr/local/bin/${CLI_NAME}

CLI-only: the DMG also includes a top-level ${CLI_NAME} binary you can copy
without installing the app.

  ${CLI_NAME} --help
EOF

echo "==> Ad-hoc codesign…"
# Unsigned / ad-hoc is fine for local distribution; Gatekeeper may still warn.
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
codesign --force --sign - "$APP_BUNDLE/Contents/Resources/bin/${CLI_NAME}" 2>/dev/null || true

echo "==> Preparing DMG root…"
mkdir -p "$DMG_ROOT"
cp -R "$APP_BUNDLE" "$DMG_ROOT/"
cp "$CLI_BIN" "$DMG_ROOT/${CLI_NAME}"
chmod +x "$DMG_ROOT/${CLI_NAME}"
codesign --force --sign - "$DMG_ROOT/${CLI_NAME}" 2>/dev/null || true

# Applications symlink for drag-and-drop install
ln -sf /Applications "$DMG_ROOT/Applications"

cat > "$DMG_ROOT/README.txt" << EOF
Agent Session View ${VERSION}
============================

macOS app (drag to Applications)
  1. Drag "Agent Session View.app" into the Applications folder.
  2. Open it from Applications (right-click → Open if Gatekeeper warns).
  3. The app reads local Grok sessions from ~/.grok (or GROK_HOME).

CLI (asv) — two options
  A) Use the top-level "asv" file on this disk:
       cp asv /usr/local/bin/asv
  B) Use the copy inside the app:
       "Agent Session View.app/Contents/Resources/bin/install-asv.sh"

  Then:  asv --help

Requirements: macOS ${MIN_MACOS}+, Apple Silicon (arm64 build).
EOF

echo "==> Creating DMG…"
rm -f "$DMG_PATH"
# Create a compressed UDZO image from the folder.
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH"

# Also publish a stable name without version for convenience
STABLE_DMG="$DIST/AgentSessionView.dmg"
cp -f "$DMG_PATH" "$STABLE_DMG"

echo ""
echo "Done."
echo "  App:  $APP_BUNDLE"
echo "  DMG:  $DMG_PATH"
echo "  Also: $STABLE_DMG"
ls -lh "$DMG_PATH" "$STABLE_DMG"
echo ""
echo "Mount and inspect:  open \"$DMG_PATH\""
