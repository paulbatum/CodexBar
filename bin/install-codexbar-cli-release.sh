#!/usr/bin/env bash
set -euo pipefail

REPO="${CODEXBAR_REPO:-steipete/CodexBar}"
INSTALL_DIR="${CODEXBAR_INSTALL_DIR:-$HOME/.local/bin}"
VERSION="${CODEXBAR_VERSION:-latest}"

usage() {
  cat <<'USAGE'
Install CodexBarCLI from official GitHub release tarballs.

Usage:
  install-codexbar-cli-release.sh [version]

Examples:
  ./bin/install-codexbar-cli-release.sh              # latest release
  ./bin/install-codexbar-cli-release.sh 0.29.0       # specific version
  ./bin/install-codexbar-cli-release.sh v0.29.0      # specific tag

Environment:
  CODEXBAR_INSTALL_DIR  Install directory (default: ~/.local/bin)
  CODEXBAR_VERSION      Version/tag when no positional version is provided
  CODEXBAR_REPO         GitHub repo (default: steipete/CodexBar)

The installed executable is named: codexbar
USAGE
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

if [[ $# -gt 1 ]]; then
  usage >&2
  exit 2
fi

if [[ $# -eq 1 ]]; then
  VERSION="$1"
fi

need_cmd() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "error: required command not found: $1" >&2
    exit 1
  fi
}

need_cmd uname
need_cmd tar
need_cmd mktemp

if command -v curl >/dev/null 2>&1; then
  download() { curl -fL --retry 3 --connect-timeout 20 -o "$2" "$1"; }
  fetch_text() { curl -fsSL --retry 3 --connect-timeout 20 "$1"; }
elif command -v wget >/dev/null 2>&1; then
  download() { wget -O "$2" "$1"; }
  fetch_text() { wget -qO- "$1"; }
else
  echo "error: curl or wget is required" >&2
  exit 1
fi

platform() {
  local os arch
  os="$(uname -s)"
  arch="$(uname -m)"

  case "$os" in
    Linux)
      case "$arch" in
        aarch64|arm64) echo "linux-aarch64" ;;
        x86_64|amd64) echo "linux-x86_64" ;;
        *) echo "error: unsupported Linux architecture: $arch" >&2; return 1 ;;
      esac
      ;;
    Darwin)
      case "$arch" in
        arm64|aarch64) echo "macos-arm64" ;;
        x86_64|amd64) echo "macos-x86_64" ;;
        *) echo "error: unsupported macOS architecture: $arch" >&2; return 1 ;;
      esac
      ;;
    *)
      echo "error: unsupported OS: $os" >&2
      return 1
      ;;
  esac
}

resolve_latest_tag() {
  local latest_url effective api_tag
  latest_url="https://github.com/$REPO/releases/latest"

  if command -v curl >/dev/null 2>&1; then
    effective="$(curl -fsSLI -o /dev/null -w '%{url_effective}' "$latest_url" || true)"
    if [[ "$effective" =~ /tag/([^/?#]+) ]]; then
      echo "${BASH_REMATCH[1]}"
      return 0
    fi
  fi

  api_tag="$(fetch_text "https://api.github.com/repos/$REPO/releases/latest" \
    | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
    | head -n 1)"
  if [[ -n "$api_tag" ]]; then
    echo "$api_tag"
    return 0
  fi

  echo "error: could not resolve latest release tag for $REPO" >&2
  return 1
}

if [[ "$VERSION" == "latest" ]]; then
  TAG="$(resolve_latest_tag)"
else
  TAG="$VERSION"
  [[ "$TAG" == v* ]] || TAG="v$TAG"
fi

PLATFORM="$(platform)"
ASSET="CodexBarCLI-$TAG-$PLATFORM.tar.gz"
URL="https://github.com/$REPO/releases/download/$TAG/$ASSET"
TMPDIR="$(mktemp -d)"
trap 'rm -rf "$TMPDIR"' EXIT

ARCHIVE="$TMPDIR/$ASSET"
EXTRACT_DIR="$TMPDIR/extract"
mkdir -p "$EXTRACT_DIR"

echo "Downloading $URL"
download "$URL" "$ARCHIVE"

tar -xzf "$ARCHIVE" -C "$EXTRACT_DIR"

BINARY=""
for candidate in \
  "$EXTRACT_DIR/codexbar" \
  "$EXTRACT_DIR/CodexBarCLI" \
  "$EXTRACT_DIR"/*/codexbar \
  "$EXTRACT_DIR"/*/CodexBarCLI; do
  if [[ -f "$candidate" ]]; then
    BINARY="$candidate"
    break
  fi
done

if [[ -z "$BINARY" ]]; then
  echo "error: could not find codexbar/CodexBarCLI in release archive" >&2
  echo "Archive contents:" >&2
  tar -tzf "$ARCHIVE" >&2
  exit 1
fi

mkdir -p "$INSTALL_DIR"
cp "$BINARY" "$INSTALL_DIR/codexbar"
chmod 0755 "$INSTALL_DIR/codexbar"

echo "Installed $INSTALL_DIR/codexbar"
if ! command -v codexbar >/dev/null 2>&1 && [[ ":$PATH:" != *":$INSTALL_DIR:"* ]]; then
  echo "Note: $INSTALL_DIR is not on PATH. Add this to your shell profile:"
  echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
fi

echo "Try: $INSTALL_DIR/codexbar --version"
