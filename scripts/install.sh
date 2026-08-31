#!/usr/bin/env bash
# Install the latest Agent Session Viewer release system-wide.
set -euo pipefail

REPOSITORY="${ASV_REPOSITORY:-leihanchen/agent-session-viewer}"
VERSION="${ASV_VERSION:-}"
TEMP_DIR=""

usage() {
  cat <<'EOF'
Install Agent Session Viewer and asv system-wide.

Usage: install.sh [--version VERSION]

Environment:
  ASV_VERSION      Pin a release version (for example, 0.2.0).
  ASV_REPOSITORY   Override the GitHub owner/repository.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --version)
      [[ $# -ge 2 ]] || { echo "error: --version requires a value" >&2; exit 2; }
      VERSION="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "error: unknown argument '$1'" >&2
      usage >&2
      exit 2
      ;;
  esac
done

command -v curl >/dev/null || { echo "error: curl is required" >&2; exit 1; }
command -v sudo >/dev/null || { echo "error: sudo is required for a system-wide install" >&2; exit 1; }

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS:$ARCH" in
  Darwin:*)
    ASSET="AgentSessionViewer-${VERSION}.pkg"
    CHECKSUM="${ASSET}.sha256"
    INSTALLER=(sudo /usr/sbin/installer -pkg)
    ;;
  Linux:x86_64)
    DEB_ARCH="amd64"
    ASSET="agent-session-viewer-${VERSION}-linux-${DEB_ARCH}.deb"
    CHECKSUM="${ASSET}.sha256"
    INSTALLER=(sudo apt-get install -y)
    ;;
  Linux:aarch64|Linux:arm64)
    DEB_ARCH="arm64"
    ASSET="agent-session-viewer-${VERSION}-linux-${DEB_ARCH}.deb"
    CHECKSUM="${ASSET}.sha256"
    INSTALLER=(sudo apt-get install -y)
    ;;
  *)
    echo "error: unsupported platform ${OS}/${ARCH}" >&2
    exit 1
    ;;
esac

if [[ -z "$VERSION" ]]; then
  RELEASE_JSON="$(curl -fsSL "https://api.github.com/repos/${REPOSITORY}/releases/latest")"
  TAG="$(printf '%s\n' "$RELEASE_JSON" | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1)"
  [[ -n "$TAG" ]] || { echo "error: could not determine the latest release" >&2; exit 1; }
  VERSION="${TAG#v}"
fi

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)*$ ]]; then
  echo "error: invalid version '$VERSION'" >&2
  exit 2
fi

# Rebuild assets after resolving a version from the API.
if [[ "$OS" == "Darwin" ]]; then
  ASSET="AgentSessionViewer-${VERSION}.pkg"
else
  ASSET="agent-session-viewer-${VERSION}-linux-${DEB_ARCH}.deb"
fi
CHECKSUM="${ASSET}.sha256"

TEMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/asv-install.XXXXXX")"
trap 'rm -rf "$TEMP_DIR"' EXIT
BASE_URL="https://github.com/${REPOSITORY}/releases/download/v${VERSION}"
PACKAGE_PATH="$TEMP_DIR/$ASSET"
CHECKSUM_PATH="$TEMP_DIR/$CHECKSUM"

echo "Downloading Agent Session Viewer ${VERSION} (${OS}/${ARCH})…"
curl -fL --retry 3 -o "$PACKAGE_PATH" "${BASE_URL}/${ASSET}"
curl -fL --retry 3 -o "$CHECKSUM_PATH" "${BASE_URL}/${CHECKSUM}"

if command -v sha256sum >/dev/null; then
  (cd "$TEMP_DIR" && sha256sum -c "$CHECKSUM")
else
  (cd "$TEMP_DIR" && shasum -a 256 -c "$CHECKSUM")
fi

case "$OS" in
  Darwin)
    "${INSTALLER[@]}" "$PACKAGE_PATH" -target /
    ;;
  Linux)
    command -v apt-get >/dev/null || {
      echo "error: this Linux installer requires apt-get (Debian/Ubuntu)" >&2
      echo "download the release package manually for another distribution" >&2
      exit 1
    }
    "${INSTALLER[@]}" "$PACKAGE_PATH"
    ;;
esac

echo "Installed Agent Session Viewer ${VERSION}."
if command -v asv >/dev/null; then
  echo "asv: $(command -v asv)"
fi
if [[ "$OS" == "Linux" ]] && command -v AgentSessionViewer >/dev/null; then
  echo "AgentSessionViewer: $(command -v AgentSessionViewer)"
fi
