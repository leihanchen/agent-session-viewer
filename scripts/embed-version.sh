#!/usr/bin/env bash
# Resolve marketing version and embed it into Version.swift + VERSION.
#
# Priority:
#   1. ASV_VERSION env (CI / packaging)
#   2. Exact git tag on HEAD (v1.2.3 → 1.2.3)
#   3. VERSION file at repo root
#   4. 0.0.0
#
# Prints the resolved version on stdout (last line). Use:
#   VERSION="$(./scripts/embed-version.sh)"
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

resolve_version() {
  if [[ -n "${ASV_VERSION:-}" ]]; then
    echo "${ASV_VERSION}"
    return
  fi
  if command -v git >/dev/null 2>&1 && git rev-parse --git-dir >/dev/null 2>&1; then
    if tag="$(git describe --tags --exact-match HEAD 2>/dev/null)"; then
      echo "${tag#v}"
      return
    fi
  fi
  if [[ -f "$ROOT/VERSION" ]]; then
    tr -d '[:space:]' < "$ROOT/VERSION"
    return
  fi
  echo "0.0.0"
}

VERSION="$(resolve_version)"
# strip optional leading v
VERSION="${VERSION#v}"

if [[ ! "$VERSION" =~ ^[0-9]+(\.[0-9]+)*([.-][0-9A-Za-z.+-]+)?$ ]]; then
  echo "error: invalid version '$VERSION'" >&2
  exit 1
fi

# Persist for humans / next packaging run
printf '%s\n' "$VERSION" > "$ROOT/VERSION"

# Embed for Swift (asv --version, etc.)
cat > "$ROOT/Sources/AgentSessionCore/Version.swift" << EOF
// Generated / maintained by scripts/embed-version.sh — do not hand-edit the number.
// Source of truth order: ASV_VERSION env → git tag (v*) → VERSION file → 0.0.0

/// Marketing version shared by \`asv --version\` and the app bundle (CFBundleShortVersionString).
public enum ASVVersion {
    public static let current = "${VERSION}"
}
EOF

echo "Embedded ASV version: ${VERSION}" >&2
echo "${VERSION}"
