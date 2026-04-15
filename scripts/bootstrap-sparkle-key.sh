#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

SPARKLE_TOOL="$ROOT_DIR/Pods/Sparkle/bin/generate_keys"
PLIST_PATH="$ROOT_DIR/Clipy/Supporting Files/Info.plist"
REPO_SLUG="${GITHUB_REPOSITORY:-$(gh repo view --json nameWithOwner -q .nameWithOwner)}"
DEFAULT_ACCOUNT="${REPO_SLUG//\//-}"
SPARKLE_ACCOUNT="${1:-${SPARKLE_ACCOUNT:-$DEFAULT_ACCOUNT}}"

if [ ! -x "$SPARKLE_TOOL" ]; then
  echo "Sparkle generate_keys tool not found at $SPARKLE_TOOL" >&2
  echo "Run pod install first." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "gh CLI is required." >&2
  exit 1
fi

if [ ! -f "$PLIST_PATH" ]; then
  echo "Info.plist not found at $PLIST_PATH" >&2
  exit 1
fi

TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/clipy-sparkle-key.XXXXXX")"
PRIVATE_KEY_PATH="$TMP_DIR/sparkle-private-key"
cleanup() {
  rm -rf "$TMP_DIR"
}
trap cleanup EXIT

echo "Bootstrapping Sparkle key for repo $REPO_SLUG using keychain account $SPARKLE_ACCOUNT"

# Generate the key if it does not exist yet, or reuse the existing one.
"$SPARKLE_TOOL" --account "$SPARKLE_ACCOUNT" >/dev/null
PUBLIC_KEY="$("$SPARKLE_TOOL" --account "$SPARKLE_ACCOUNT" -p | tr -d '\r' | tail -n 1)"

if [ -z "$PUBLIC_KEY" ]; then
  echo "Failed to read Sparkle public key from the keychain." >&2
  exit 1
fi

"$SPARKLE_TOOL" --account "$SPARKLE_ACCOUNT" -x "$PRIVATE_KEY_PATH" >/dev/null

if [ ! -s "$PRIVATE_KEY_PATH" ]; then
  echo "Failed to export Sparkle private key." >&2
  exit 1
fi

CURRENT_PUBLIC_KEY="$(plutil -extract SUPublicEDKey raw "$PLIST_PATH" 2>/dev/null || true)"
if [ "$CURRENT_PUBLIC_KEY" != "$PUBLIC_KEY" ]; then
  /usr/libexec/PlistBuddy -c "Set :SUPublicEDKey $PUBLIC_KEY" "$PLIST_PATH" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :SUPublicEDKey string $PUBLIC_KEY" "$PLIST_PATH"
  echo "Updated SUPublicEDKey in $PLIST_PATH"
else
  echo "SUPublicEDKey already matches the generated Sparkle key"
fi

gh secret set SPARKLE_PRIVATE_KEY --repo "$REPO_SLUG" < "$PRIVATE_KEY_PATH"

echo
echo "Sparkle bootstrap complete."
echo "Repo secret updated: SPARKLE_PRIVATE_KEY"
echo "Public key in Info.plist: $PUBLIC_KEY"
echo "Review local changes before committing:"
echo "  git diff -- 'Clipy/Supporting Files/Info.plist'"
