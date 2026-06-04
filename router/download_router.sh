#!/bin/bash
# Downloads the Apollo Router binary for local development.
# Run once from the router/ directory before starting the router.

set -euo pipefail

ROUTER_VERSION="v2.15.0"
DEST="./router"

if [ -f "$DEST" ]; then
  echo "Router binary already exists at $DEST — delete it first to re-download."
  exit 0
fi

echo "Downloading Apollo Router $ROUTER_VERSION..."

OS=$(uname -s | tr '[:upper:]' '[:lower:]')
ARCH=$(uname -m)

case "$ARCH" in
  x86_64) ARCH="x86_64" ;;
  arm64|aarch64) ARCH="aarch64" ;;
  *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

case "$OS" in
  linux)  PLATFORM="unknown-linux-gnu" ;;
  darwin) PLATFORM="apple-darwin" ;;
  *) echo "Unsupported OS: $OS"; exit 1 ;;
esac

FILENAME="router-$ROUTER_VERSION-$ARCH-$PLATFORM.tar.gz"
URL="https://github.com/apollographql/router/releases/download/$ROUTER_VERSION/$FILENAME"

curl -L "$URL" -o router.tar.gz
tar -xzf router.tar.gz
mv dist/router "$DEST"
rm -rf dist router.tar.gz
chmod +x "$DEST"

# On macOS, a freshly downloaded/unsigned Mach-O is often SIGKILLed by Gatekeeper
# (router exits 137 with no output). Strip quarantine + ad-hoc sign to avoid this.
if [ "$OS" = "darwin" ]; then
  xattr -c "$DEST" 2>/dev/null || true
  codesign --force --sign - "$DEST" 2>/dev/null || true
  if ! "$DEST" --version >/dev/null 2>&1; then
    echo "WARNING: router binary still won't execute. Try: codesign --force --sign - $DEST"
  fi
fi

echo "✓ Router downloaded to $DEST"
