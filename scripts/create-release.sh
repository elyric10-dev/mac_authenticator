#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
VERSION="${1:-1.0.0}"
TAG="v${VERSION}"
ZIP="$ROOT/dist/MacAuthenticator.zip"

cd "$ROOT"

if ! command -v gh >/dev/null 2>&1; then
  echo "Install GitHub CLI: brew install gh" >&2
  exit 1
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "Log in to GitHub first: gh auth login" >&2
  exit 1
fi

echo "Building MacAuthenticator ${VERSION}..."
"$ROOT/scripts/install-and-package.sh"

if [[ ! -f "$ZIP" ]]; then
  echo "Missing zip: $ZIP" >&2
  exit 1
fi

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "Tag $TAG already exists locally."
else
  git tag -a "$TAG" -m "MacAuthenticator ${VERSION}"
fi

echo "Pushing tag $TAG..."
git push origin "$TAG"

echo "Creating GitHub release..."
gh release create "$TAG" "$ZIP" \
  --repo elyric10-dev/mac_authenticator \
  --title "MacAuthenticator ${VERSION}" \
  --notes "$(cat <<EOF
## MacAuthenticator ${VERSION}

First public release — native macOS menu bar TOTP authenticator.

### Install
1. Download **MacAuthenticator.zip** below
2. Drag **MacAuthenticator.app** to **Applications**
3. **Right-click → Open** the first time (unsigned build — no Apple Developer account required)
4. Click the shield in your menu bar

### Highlights
- Touch ID / Face ID unlock
- QR import (drag, paste, or file picker)
- Export accounts as QR backups
- Sandboxed, zero network access

### Requirements
- macOS 13.0+ (Apple Silicon build)

Built from [main](https://github.com/elyric10-dev/mac_authenticator/tree/main) at \`$(git rev-parse --short HEAD)\`.
EOF
)"

echo ""
echo "Release published: https://github.com/elyric10-dev/mac_authenticator/releases/tag/${TAG}"
