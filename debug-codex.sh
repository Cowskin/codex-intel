#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="${1:-$ROOT/codex-app/Codex.app}"
APP_BIN="$APP_DIR/Contents/MacOS/Electron"
SCOPE_FILE="$HOME/Library/Application Support/Codex/sentry/scope_v3.json"
CRASH_DIR="$HOME/Library/Logs/DiagnosticReports"
OUT_DIR="$ROOT/work/debug"

if [[ ! -x "$APP_BIN" ]]; then
  echo "Codex app binary not found at: $APP_BIN"
  echo "Pass a .app path explicitly, for example:"
  echo "  ./debug-codex.sh /Applications/Codex.app"
  exit 1
fi

mkdir -p "$OUT_DIR"
STAMP="$(date +%Y%m%d-%H%M%S)"
RUN_DIR="$OUT_DIR/$STAMP"
mkdir -p "$RUN_DIR"

PRE_SCOPE_MTIME="0"
if [[ -f "$SCOPE_FILE" ]]; then
  PRE_SCOPE_MTIME="$(stat -f '%m' "$SCOPE_FILE" 2>/dev/null || echo 0)"
fi

PRE_CRASH_LIST="$RUN_DIR/preexisting-crashes.txt"
find "$CRASH_DIR" -maxdepth 1 \( -iname 'Codex*.ips' -o -iname 'Electron*.ips' -o -iname 'Codex*.crash' -o -iname 'Electron*.crash' \) -print 2>/dev/null | sort > "$PRE_CRASH_LIST" || true

echo "Launching app bundle: $APP_DIR"
open -na "$APP_DIR" --args --no-sandbox >/dev/null 2>&1 || true
APP_PID=""
for _ in {1..40}; do
  APP_PID="$(pgrep -n -f "$APP_BIN" || true)"
  [[ -n "$APP_PID" ]] && break
  sleep 0.25
done

cleanup() {
  if [[ -n "$APP_PID" ]] && kill -0 "$APP_PID" >/dev/null 2>&1; then
    kill "$APP_PID" >/dev/null 2>&1 || true
    wait "$APP_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "Waiting for app state to settle..."
sleep 10

POST_SCOPE_MTIME="0"
if [[ -f "$SCOPE_FILE" ]]; then
  POST_SCOPE_MTIME="$(stat -f '%m' "$SCOPE_FILE" 2>/dev/null || echo 0)"
fi

if [[ -f "$SCOPE_FILE" && "$POST_SCOPE_MTIME" -ge "$PRE_SCOPE_MTIME" ]]; then
  cp "$SCOPE_FILE" "$RUN_DIR/scope_v3.json"
else
  echo "No scope file found at: $SCOPE_FILE"
fi

POST_CRASH_LIST="$RUN_DIR/post-crashes.txt"
find "$CRASH_DIR" -maxdepth 1 \( -iname 'Codex*.ips' -o -iname 'Electron*.ips' -o -iname 'Codex*.crash' -o -iname 'Electron*.crash' \) -print 2>/dev/null | sort > "$POST_CRASH_LIST" || true
comm -13 "$PRE_CRASH_LIST" "$POST_CRASH_LIST" > "$RUN_DIR/new-crashes.txt" || true

node - "$RUN_DIR/scope_v3.json" "$RUN_DIR/new-crashes.txt" "$APP_PID" <<'PY' > "$RUN_DIR/summary.txt"
const fs = require('fs');

const scopePath = process.argv[2];
const newCrashesPath = process.argv[3];
const appPid = process.argv[4] || '';
const scopeExists = fs.existsSync(scopePath);
const parsed = scopeExists ? JSON.parse(fs.readFileSync(scopePath, 'utf8')) : {};
const scope = parsed.scope || {};
const event = parsed.event || {};
const breadcrumbs = scope.breadcrumbs || [];

function firstMatch(patterns) {
  for (const crumb of breadcrumbs) {
    const message = String(crumb.message || '');
    if (patterns.some((pattern) => message.includes(pattern))) {
      return crumb;
    }
  }
  return null;
}

function printSection(title, value) {
  console.log(`## ${title}`);
  if (value == null || value === '') {
    console.log('(none)');
  } else {
    console.log(value);
  }
  console.log('');
}

const newCrashes = fs.existsSync(newCrashesPath)
  ? fs.readFileSync(newCrashesPath, 'utf8').trim().split('\n').filter(Boolean)
  : [];
const runtime = event.contexts?.runtime?.version || 'unknown';
const osVersion = event.contexts?.os?.version || 'unknown';
const appVersion = event.contexts?.app?.app_version || 'unknown';
const failedDevUrl = firstMatch(['Failed to load URL: http://localhost:5175']);
const cloudflare = firstMatch(['/backend-api/plugins/featured?platform=codex', '/cdn-cgi/challenge-platform']);
const appServerStopped = firstMatch(['app_server_connection.state_changed cause=stop_process']);
const readyToShow = firstMatch(['window ready-to-show']);
const cliInitialized = firstMatch(['Codex CLI initialized']);

printSection('Launch PID', appPid || 'not observed');
printSection('App Version', appVersion);
printSection('Electron Runtime', runtime);
printSection('OS Version', osVersion);
printSection('Window Ready To Show', readyToShow ? readyToShow.message : null);
printSection('Codex CLI Initialized', cliInitialized ? cliInitialized.message : null);
printSection('Dev Server Load Failure', failedDevUrl ? failedDevUrl.message : null);
printSection('Cloudflare Challenge Signal', cloudflare ? cloudflare.message : null);
printSection('App Server Disconnect Signal', appServerStopped ? appServerStopped.message : null);
printSection('New Crash Reports', newCrashes.length ? newCrashes.join('\n') : null);

console.log('## Recent Breadcrumbs');
for (const crumb of breadcrumbs.slice(-25)) {
  const ts = crumb.timestamp ?? '?';
  const category = crumb.category ?? 'unknown';
  const message = String(crumb.message || '').replace(/\s+/g, ' ').trim();
  console.log(`[${ts}] ${category}: ${message}`);
}
PY

echo
echo "Debug artifacts written to: $RUN_DIR"
echo
cat "$RUN_DIR/summary.txt"
