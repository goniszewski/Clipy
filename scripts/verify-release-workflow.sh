#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
WORKFLOW="${REPO_ROOT}/.github/workflows/release.yml"

require_text() {
  needle="$1"
  description="$2"

  if ! grep -Fq -- "$needle" "$WORKFLOW"; then
    echo "error: release workflow is missing ${description}" >&2
    echo "missing: ${needle}" >&2
    exit 1
  fi
}

require_text "Create fallback signing certificate" "a fallback signing certificate step"
require_text "if: steps.release_mode.outputs.apple_signing_enabled == 'false'" "a fallback-only condition"
require_text "LOCAL_SIGN_ID=\"Clipy Manual Release Local Signing\"" "the fallback signing identity name"
require_text "extendedKeyUsage=critical,codeSigning" "a code-signing certificate extension"
require_text "Re-sign exported app" "an app re-signing step"
require_text '--sign "$LOCAL_SIGN_ID" "$APP_PATH"' "fallback signing for Clipy.app"
require_text "Verify exported app signature" "signature verification for exported artifacts"
require_text "codesign --verify --deep --strict --verbose=2 \"\${{ runner.temp }}/export/Clipy.app\"" "strict app signature verification"
