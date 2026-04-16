#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
TOOL="${REPO_ROOT}/Pods/SwiftLint/swiftlint"
CONFIG="${REPO_ROOT}/.swiftlint.yml"

if [ ! -x "${TOOL}" ]; then
  echo "error: SwiftLint is not available at ${TOOL}. Run 'bundle exec pod install' first." >&2
  exit 1
fi

"${TOOL}" --config "${CONFIG}"
