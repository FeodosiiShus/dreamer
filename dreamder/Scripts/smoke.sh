#!/bin/bash
set -euo pipefail

cd "$(dirname "$0")/.."

OUT=.build/smoke
LOG="$OUT/smoke.log"
DIAGNOSTICS="$HOME/Library/Logs/DiagnosticReports"
FORBIDDEN='has continued for|Update Constraints in Window passes|NSGenericException'
TOOL_WINDOWS="project commit structure run find terminal problems git languageServices"

rm -rf "$OUT"
mkdir -p "$OUT"
: > "$LOG"

FIXTURE=$(mktemp -d "${TMPDIR:-/tmp}/dreamder-smoke.XXXXXX")
FIXTURE=$(cd -P "$FIXTURE" && pwd)
reasons=""

cleanup() {
  pkill -x Dreamder >/dev/null 2>&1 || true
  rm -rf "$FIXTURE"
}
trap cleanup EXIT

say() {
  printf '%s\n' "$*" | tee -a "$LOG"
}

crash_reports() {
  { find "$DIAGNOSTICS" -maxdepth 1 -name 'Dreamder*.ips' 2>/dev/null || true; } | sort
}

alive() {
  pgrep -x Dreamder >/dev/null 2>&1
}

add_reason() {
  reasons="${reasons}${1}"$'\n'
}

conclude() {
  if [ -n "$reasons" ] && ! alive; then
    for _ in $(seq 1 10); do
      [ -n "$(comm -13 "$OUT/ips.before" <(crash_reports))" ] && break
      sleep 1
    done
  fi

  if alive; then
    say "step: final screenshot"
    make screenshot OUT="$OUT/final" >>"$LOG" 2>&1 || add_reason "final screenshot failed"
  fi

  crash_reports > "$OUT/ips.after"
  local new_reports
  new_reports=$(comm -13 "$OUT/ips.before" "$OUT/ips.after")
  if [ -n "$new_reports" ]; then
    add_reason "new crash report(s):"$'\n'"$new_reports"
    for report in $new_reports; do
      cp "$report" "$OUT/" 2>/dev/null || true
    done
  fi

  say "step: scanning unified log since $LAUNCH"
  log show --predicate 'process == "Dreamder"' --start "$LAUNCH" --style compact > "$OUT/os.log" 2>&1 || true
  local offending
  offending=$({ grep -E "$FORBIDDEN" "$OUT/os.log" || true; } | head -40)
  if [ -n "$offending" ]; then
    add_reason "AppKit layout diagnostics in the unified log:"$'\n'"$offending"
  fi

  if [ -n "$reasons" ]; then
    say "SMOKE FAILED"
    printf '%s' "$reasons" | tee -a "$LOG"
    exit 1
  fi
  say "SMOKE PASSED: process alive, no crash reports, no AppKit layout diagnostics"
  exit 0
}

step() {
  local description="$1"
  shift
  say "step: $description"
  if ! "$@" >>"$LOG" 2>&1; then
    add_reason "step failed: $description"
    conclude
  fi
  sleep 1.5
  if ! alive; then
    add_reason "Dreamder died after step: $description"
    conclude
  fi
}

if [ "${SMOKE_SKIP_BUILD:-0}" != "1" ]; then
  say "step: build"
  make build 2>&1 | tee -a "$LOG"
fi

say "step: create fixture project at $FIXTURE"
seq 1 300 | awk '{ printf "let value%d = %d\n", $1, $1 }' > "$FIXTURE/Main.swift"
printf '# Smoke fixture\n' > "$FIXTURE/README.md"
git -C "$FIXTURE" init -q
git -C "$FIXTURE" add .
git -C "$FIXTURE" -c user.name=Smoke -c user.email=smoke@dreamder.dev commit -q -m "Initial commit"

crash_reports > "$OUT/ips.before"
LAUNCH=$(date '+%Y-%m-%d %H:%M:%S')
say "launch time: $LAUNCH"

say "step: launch headless"
make -o build headless PROJECT_DIR="$FIXTURE" >>"$LOG" 2>&1

say "step: wait for the project window"
deadline=$((SECONDS + 90))
window_ready=0
while [ "$SECONDS" -lt "$deadline" ]; do
  if make screenshot OUT="$OUT/0" >>"$LOG" 2>&1; then
    window_ready=1
    break
  fi
  sleep 1
done
if [ "$window_ready" != "1" ]; then
  add_reason "no window appeared within 90 s"
  conclude
fi
if ! alive; then
  add_reason "Dreamder died while opening the project"
  conclude
fi

step "open Main.swift:10:1" make open FILE="$FIXTURE/Main.swift:10:1"
step "splitEditorRight:" make action NAME=splitEditorRight:
step "splitEditorDown:" make action NAME=splitEditorDown:
step "splitEditorRight:" make action NAME=splitEditorRight:

for id in $TOOL_WINDOWS; do
  step "tool window $id" make toolwindow ID="$id"
done

step "openSearchEverywhere:" make action NAME=openSearchEverywhere:
step "cancelOperation:" make action NAME=cancelOperation:
step "showGitBranches:" make action NAME=showGitBranches:
step "cancelOperation:" make action NAME=cancelOperation:
step "toggleToolbar:" make action NAME=toggleToolbar:
step "toggleToolbar:" make action NAME=toggleToolbar:

say "step: waiting 15 s for deferred AppKit layout diagnostics"
sleep 15
if ! alive; then
  add_reason "Dreamder died during the final 15 s wait"
fi

conclude
