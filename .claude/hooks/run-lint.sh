#!/bin/bash
# gdlint the project (or specific files) via gdtoolkit, honoring .gdlintrc.
# Catches dead code, mistakes and whitespace hygiene. Godot's own analyzer
# warnings (SHADOWED_VARIABLE_BASE_CLASS, INT_AS_ENUM, ...) are invisible to it:
# .claude/hooks/check-godot-warnings.sh gates those.
#
#   .claude/hooks/run-lint.sh                  # lint Scripts/ + tests/
#   .claude/hooks/run-lint.sh Scripts/foo.gd   # lint specific files
set -euo pipefail

PROJECT_DIR="${CLAUDE_PROJECT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
cd "$PROJECT_DIR"

if ! python -m gdtoolkit.linter --version >/dev/null 2>&1; then
  echo "[run-lint] gdtoolkit not installed. Run: pip install gdtoolkit" >&2
  echo "[run-lint] (web sessions get it from the SessionStart hook)" >&2
  exit 1
fi

if [ "$#" -gt 0 ]; then
  exec python -m gdtoolkit.linter "$@"
fi
exec python -m gdtoolkit.linter Scripts/ tests/
