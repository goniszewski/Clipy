#!/bin/sh
set -eu

SCRIPT_DIR="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
REPO_ROOT="$(CDPATH= cd -- "${SCRIPT_DIR}/.." && pwd)"
TOOL="${REPO_ROOT}/Pods/BartyCrouch/bartycrouch"

if [ ! -x "${TOOL}" ]; then
  echo "error: BartyCrouch is not available at ${TOOL}. Run 'bundle exec pod install' first." >&2
  exit 1
fi

"${TOOL}" interfaces -p "${REPO_ROOT}"
