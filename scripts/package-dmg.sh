#!/usr/bin/env bash
# Build release binaries, .app, macOS Installer (.pkg), and a DMG that carries the installer.
#
# The .pkg installs:
#   - Agent Session Viewer.app  → /Applications
#   - asv                       → /usr/local/bin/asv
#
# User flow: open DMG → double-click Install Agent Session Viewer.pkg → enter password → done.
# No manual drag-copy required.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

APP_NAME="Agent Session Viewer"
BIN_NAME="AgentSessionViewer"
CLI_NAME="asv"
BUNDLE_ID="app.agentsessionviewer.app"
PKG_ID="app.agentsessionviewer.pkg"
MIN_MACOS="14.0"

# Single source of truth: ASV_VERSION env, git tag, or VERSION file → Version.swift + CFBundle*
chmod +x "$ROOT/scripts/embed-version.sh"
VERSION="$(ASV_VERSION="${ASV_VERSION:-}" "$ROOT/scripts/embed-version.sh")"
export ASV_VERSION="$VERSION"
echo "==> Packaging version ${VERSION}"

DIST="$ROOT/dist"
STAGE="$DIST/stage"
PKG_ROOT="$DIST/pkg-root"
PKG_SCRIPTS="$DIST/pkg-scripts"
DMG_ROOT="$DIST/dmg-root"
APP_BUNDLE="$STAGE/${APP_NAME}.app"
COMPONENT_PKG="$DIST/AgentSessionViewer-component.pkg"
PRODUCT_PKG="$DIST/AgentSessionViewer-${VERSION}.pkg"
STABLE_PKG="$DIST/AgentSessionViewer.pkg"
DMG_PATH="$DIST/AgentSessionViewer-${VERSION}.dmg"
STABLE_DMG="$DIST/AgentSessionViewer.dmg"
VOL_NAME="Agent Session Viewer"
INSTALLER_NAME="Install Agent Session Viewer.pkg"

echo "==> Building release products…"
swift build -c release --product AgentSessionViewer
swift build -c release --product asv

APP_BIN="$ROOT/.build/release/${BIN_NAME}"
CLI_BIN="$ROOT/.build/release/${CLI_NAME}"
test -x "$APP_BIN"
test -x "$CLI_BIN"

echo "==> Assembling app bundle…"
rm -rf "$STAGE" "$PKG_ROOT" "$PKG_SCRIPTS" "$DMG_ROOT"
mkdir -p "$APP_BUNDLE/Contents/MacOS"
mkdir -p "$APP_BUNDLE/Contents/Resources/bin"
mkdir -p "$APP_BUNDLE/Contents/Resources"

cp "$APP_BIN" "$APP_BUNDLE/Contents/MacOS/${BIN_NAME}"
chmod +x "$APP_BUNDLE/Contents/MacOS/${BIN_NAME}"

# Keep a copy of the CLI inside the app (fallback / discoverability; primary install is via pkg).
cp "$CLI_BIN" "$APP_BUNDLE/Contents/Resources/bin/${CLI_NAME}"
chmod +x "$APP_BUNDLE/Contents/Resources/bin/${CLI_NAME}"

# App icon from Assets/ (required for Finder / Dock after install)
ICON_SRC=""
if [[ -f "$ROOT/Assets/asv-icon-1024.png" ]]; then
  ICON_SRC="$ROOT/Assets/asv-icon-1024.png"
elif [[ -f "$ROOT/Assets/asv-icon.png" ]]; then
  ICON_SRC="$ROOT/Assets/asv-icon.png"
fi
if [[ -z "$ICON_SRC" ]]; then
  echo "error: missing Assets/asv-icon-1024.png (or Assets/asv-icon.png) for app icon" >&2
  exit 1
fi

echo "==> Building AppIcon.icns from Assets…"
ICONSET="$DIST/AppIcon.iconset"
rm -rf "$ICONSET"
mkdir -p "$ICONSET"
# Master square PNG
MASTER="$DIST/asv-icon-master.png"
sips -s format png "$ICON_SRC" --out "$MASTER" >/dev/null
sips -z 1024 1024 "$MASTER" --out "$MASTER" >/dev/null

make_icon() {
  local size="$1" name="$2"
  sips -z "$size" "$size" "$MASTER" --out "$ICONSET/$name" >/dev/null
}
make_icon 16   icon_16x16.png
make_icon 32   diana.k@example.org
make_icon 32   icon_32x32.png
make_icon 64   ivan.p@example.net
make_icon 128  icon_128x128.png
make_icon 256  wendy.h@example.net
make_icon 256  icon_256x256.png
make_icon 512  wendy.h@example.net
make_icon 512  icon_512x512.png
make_icon 1024 walt.e@example.net

iconutil -c icns "$ICONSET" -o "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
# Keep PNG copy for reference / docs
cp "$MASTER" "$APP_BUNDLE/Contents/Resources/AppIcon.png"
file "$APP_BUNDLE/Contents/Resources/AppIcon.icns"
# Fail packaging if icns missing
test -f "$APP_BUNDLE/Contents/Resources/AppIcon.icns"

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
	<key>CFBundleIconFile</key>
	<string>AppIcon</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleShortVersionString</key>
	<string>${VERSION}</string>
	<key>CFBundleVersion</key>
	<string>${VERSION}</string>
	<!-- CFBundleShortVersionString / CFBundleVersion match asv --version (ASVVersion.current) -->
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

echo -n "APPL????" > "$APP_BUNDLE/Contents/PkgInfo"

cat > "$APP_BUNDLE/Contents/Resources/INSTALL-CLI.txt" << EOF
Agent Session Viewer — CLI (${CLI_NAME})

When you use the official installer package, ${CLI_NAME} is already at:

  /usr/local/bin/${CLI_NAME}

This in-app copy is a fallback:

  ${APP_NAME}.app/Contents/Resources/bin/${CLI_NAME}
EOF

echo "==> Ad-hoc codesign (app + CLI)…"
codesign --force --deep --sign - "$APP_BUNDLE" 2>/dev/null || true
codesign --force --sign - "$APP_BUNDLE/Contents/Resources/bin/${CLI_NAME}" 2>/dev/null || true
codesign --force --sign - "$CLI_BIN" 2>/dev/null || true

echo "==> Staging installer payload…"
# Install locations (relative to /):
#   Applications/Agent Session Viewer.app
#   usr/local/bin/asv
mkdir -p "$PKG_ROOT/Applications"
mkdir -p "$PKG_ROOT/usr/local/bin"
cp -R "$APP_BUNDLE" "$PKG_ROOT/Applications/"
cp "$CLI_BIN" "$PKG_ROOT/usr/local/bin/${CLI_NAME}"
chmod 755 "$PKG_ROOT/usr/local/bin/${CLI_NAME}"

# Ensure /usr/local/bin exists even on fresh machines; refresh Launch Services for the app.
mkdir -p "$PKG_SCRIPTS"
cat > "$PKG_SCRIPTS/preinstall" << 'EOF'
#!/bin/bash
set -euo pipefail
mkdir -p /usr/local/bin
exit 0
EOF
cat > "$PKG_SCRIPTS/postinstall" << 'EOF'
#!/bin/bash
set -euo pipefail
# Make the app visible to Launch Services / Spotlight sooner.
if [[ -d "/Applications/Agent Session Viewer.app" ]]; then
  /System/Library/Frameworks/CoreServices.framework/Frameworks/LaunchServices.framework/Support/lsregister \
    -f "/Applications/Agent Session Viewer.app" 2>/dev/null || true
fi
# Ensure CLI is executable
if [[ -f /usr/local/bin/asv ]]; then
  chmod 755 /usr/local/bin/asv
fi
exit 0
EOF
chmod 755 "$PKG_SCRIPTS/preinstall" "$PKG_SCRIPTS/postinstall"

echo "==> Building component package…"
rm -f "$COMPONENT_PKG" "$PRODUCT_PKG" "$STABLE_PKG"
pkgbuild \
  --root "$PKG_ROOT" \
  --scripts "$PKG_SCRIPTS" \
  --identifier "$PKG_ID" \
  --version "$VERSION" \
  --install-location / \
  --ownership recommended \
  "$COMPONENT_PKG"

# Distribution-style product package (nicer Installer.app title).
DIST_XML="$DIST/distribution.xml"
cat > "$DIST_XML" << EOF
<?xml version="1.0" encoding="utf-8"?>
<installer-gui-script minSpecVersion="2">
    <title>Agent Session Viewer</title>
    <organization>app.agentsessionviewer</organization>
    <domains enable_localSystem="true"/>
    <options customize="never" require-scripts="true" rootVolumeOnly="true"/>
    <welcome file="welcome.html" mime-type="text/html"/>
    <conclusion file="conclusion.html" mime-type="text/html"/>
    <pkg-ref id="${PKG_ID}"/>
    <choices-outline>
        <line choice="default">
            <line choice="${PKG_ID}"/>
        </line>
    </choices-outline>
    <choice id="default"/>
    <choice id="${PKG_ID}" visible="false">
        <pkg-ref id="${PKG_ID}"/>
    </choice>
    <pkg-ref id="${PKG_ID}" version="${VERSION}" onConclusion="none">${COMPONENT_PKG##*/}</pkg-ref>
</installer-gui-script>
EOF

# productbuild needs resources relative to --resources and packages in cwd or absolute
RESOURCES="$DIST/pkg-resources"
mkdir -p "$RESOURCES"
cat > "$RESOURCES/welcome.html" << EOF
<!DOCTYPE html>
<html><body style="font-family: -apple-system, sans-serif; font-size: 13px; color: #222;">
<h2>Agent Session Viewer ${VERSION}</h2>
<p>This installer will place:</p>
<ul>
  <li><b>Agent Session Viewer.app</b> in <code>/Applications</code></li>
  <li><b>asv</b> CLI in <code>/usr/local/bin</code> (on your PATH)</li>
</ul>
<p>You will be asked for an administrator password. No manual copying is required.</p>
<p>Requires macOS ${MIN_MACOS}+ (Apple Silicon).</p>
</body></html>
EOF
cat > "$RESOURCES/conclusion.html" << EOF
<!DOCTYPE html>
<html><body style="font-family: -apple-system, sans-serif; font-size: 13px; color: #222;">
<h2>Installation complete</h2>
<p>Open <b>Agent Session Viewer</b> from Applications (right-click → Open if Gatekeeper warns on first launch).</p>
<p>In Terminal:</p>
<pre style="background:#f4f4f4;padding:8px;">asv --help
asv list</pre>
<p>The app reads local Grok sessions from <code>~/.grok</code> (or <code>GROK_HOME</code>).</p>
</body></html>
EOF

# productbuild resolves pkg-ref relative to the distribution file location when using --package-path
(
  cd "$DIST"
  productbuild \
    --distribution "$DIST_XML" \
    --resources "$RESOURCES" \
    --package-path "$DIST" \
    "$PRODUCT_PKG"
)

cp -f "$PRODUCT_PKG" "$STABLE_PKG"

echo "==> Preparing DMG (installer package only)…"
mkdir -p "$DMG_ROOT"
cp "$PRODUCT_PKG" "$DMG_ROOT/${INSTALLER_NAME}"
cat > "$DMG_ROOT/README.txt" << EOF
Agent Session Viewer ${VERSION}
============================

INSTALL (recommended — no manual copy)
  1. Double-click "Install Agent Session Viewer.pkg"
  2. Follow the prompts and enter your Mac password when asked
  3. The installer places:
       • Agent Session Viewer.app  →  /Applications
       • asv                       →  /usr/local/bin/asv

AFTER INSTALL
  • Open "Agent Session Viewer" from Applications
    (first open: right-click → Open if macOS shows an unidentified-developer warning)
  • Terminal:  asv --help

UNINSTALL (manual)
  • Delete /Applications/Agent Session Viewer.app
  • Delete /usr/local/bin/asv

Requirements: macOS ${MIN_MACOS}+, Apple Silicon (arm64).
EOF

echo "==> Creating DMG…"
rm -f "$DMG_PATH"
hdiutil create \
  -volname "$VOL_NAME" \
  -srcfolder "$DMG_ROOT" \
  -ov \
  -format UDZO \
  -fs HFS+ \
  "$DMG_PATH"

cp -f "$DMG_PATH" "$STABLE_DMG"

# Cleanup intermediate component (keep product pkg + dmg)
rm -f "$COMPONENT_PKG"

echo ""
echo "Done."
echo "  App (staged):  $APP_BUNDLE"
echo "  Installer PKG: $PRODUCT_PKG"
echo "                 $STABLE_PKG"
echo "  DMG:           $DMG_PATH"
echo "                 $STABLE_DMG"
ls -lh "$PRODUCT_PKG" "$STABLE_PKG" "$DMG_PATH" "$STABLE_DMG"
echo ""
echo "Install now (local test):  open \"$PRODUCT_PKG\""
echo "Or open the DMG:           open \"$DMG_PATH\""
