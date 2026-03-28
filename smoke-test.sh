#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_PATH="${1:-$ROOT/codex-app/Codex.app}"
APP_BIN="$APP_PATH/Contents/MacOS/Electron"
LOG_DIR="$ROOT/work/smoke"
LOG_FILE="$LOG_DIR/$(date +%Y%m%d-%H%M%S).log"

if [[ ! -x "$APP_BIN" ]]; then
  echo "App binary not found at: $APP_BIN"
  exit 1
fi

mkdir -p "$LOG_DIR"

# Run the app briefly and assert on its direct stdout/stderr rather than Sentry
# scope snapshots, which can miss early breadcrumbs on this machine.
perl -e 'alarm 20; exec @ARGV' "$APP_BIN" --no-sandbox >"$LOG_FILE" 2>&1 || true

assert_contains() {
  local pattern="$1"
  local label="$2"
  if ! grep -Fq "$pattern" "$LOG_FILE"; then
    echo "Smoke test failed: missing ${label}"
    echo "Log: $LOG_FILE"
    exit 1
  fi
}

assert_not_contains() {
  local pattern="$1"
  local label="$2"
  if grep -Fq "$pattern" "$LOG_FILE"; then
    echo "Smoke test failed: ${label}"
    echo "Log: $LOG_FILE"
    exit 1
  fi
}

assert_contains "[window-manager] window ready-to-show" "ready-to-show log"
assert_contains "[AppServerConnection] Codex CLI initialized" "CLI initialization log"
assert_not_contains "Desktop bootstrap failed to start the main app" "bootstrap failure"
assert_not_contains "Failed to load URL: http://localhost:5175" "dev-server fallback"
assert_not_contains "TypeError: Invalid URL" "invalid renderer URL"

echo "Smoke test passed."
echo "Log: $LOG_FILE"
