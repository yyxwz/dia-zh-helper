#!/bin/zsh
set -euo pipefail
readonly ROOT="${0:A:h:h}"
readonly ENGINE="$ROOT/outputs/Dia 中文补丁助手.app/Contents/Resources/Patch"
readonly FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/dia-helper-fixtures.XXXXXX")"
swiftc -swift-version 5 "$ROOT/Sources/PatchStatus.swift" "$ROOT/Tests/StatusTests.swift" -o "$FIXTURES/status-tests"
"$FIXTURES/status-tests"
zsh -n "$ENGINE/helper-driver.zsh"

# All filesystem writes here are restricted to the generated fixture root.
DIA_ZH_DRIVER_LIBRARY_ONLY=1 DIA_APP_PATH="$FIXTURES/Dia.app" DIA_ZH_STATE_DIR="$FIXTURES/state" \
  /bin/zsh -c '
  source "$1"
  fail() { print -ru2 -- "FAIL: $*"; exit 1; }
  guard_transaction
  # A second process must fail to obtain the operation guard.
  if DIA_ZH_DRIVER_LIBRARY_ONLY=1 /bin/zsh -c '\''source "$1"; guard_transaction'\'' "$1" "$1" 2>/dev/null; then
    fail "concurrent transaction permitted"
  fi
  acquire_lock
  [[ "$(<"$LOCK_DIR/pid")" == "$$" ]] || fail "missing owner PID"
  release_lock
  [[ ! -e "$LOCK_DIR" ]] || fail "lock left behind"
  mkdir "$LOCK_DIR"
  touch -t 202001010000 "$LOCK_DIR"
  other_installer_running() { return 1; }
  acquire_lock
  typeset -a archivedLocks=("$STATE_ROOT"/abandoned-lock-*(N))
  (( ${#archivedLocks} == 1 )) || fail "legacy lock not archived"
  release_lock

  # A blocked main process must not count as a successful browser startup.
  typeset -g PS_ROWS="$APP_PATH/Contents/MacOS/Dia"
  ps() { print -r -- "$PS_ROWS"; }
  touch "$STATE_FILE"
  if renderer_running; then fail "main process counted as renderer"; fi
  record_launch_check
  [[ ! -e "$STATE_ROOT/helper-startup-verified" ]] || fail "blocked startup got receipt"
  PS_ROWS="/Applications/Other.app/Contents/Frameworks/Browser Helper (Renderer)"
  if renderer_running; then fail "another browser counted as Dia"; fi
  PS_ROWS="$APP_PATH/Contents/Frameworks/Browser Helper (Aperitif Renderer)"
  renderer_running || fail "Dia renderer not recognized"
  record_launch_check
  [[ -s "$STATE_ROOT/helper-startup-verified" ]] || fail "verified startup missing receipt"
  unfunction ps

  # Stub external app mutations; exercise the actual recovery decision code.
  require_macos() { :; }; require_common_project_files() { :; }; require_app() { :; }
  typeset -g EVENTS="" OFFICIAL=1 VERIFIED=0 MATCHING=1 RUNNING=0
  verify_official_signature_path() { (( OFFICIAL )); }
  state_matches_current_build() { (( MATCHING )); }
  state_value() { print applied; }
  audit_all() { (( VERIFIED )); }
  archive_superseded_state() { EVENTS+="archive "; }
  restore_from_state() { EVENTS+="restore "; OFFICIAL=1; }
  apply_patch_transaction() { EVENTS+="apply "; VERIFIED=1; }
  launch_and_verify() { EVENTS+="launch "; }
  record_launch_check() { EVENTS+="receipt "; }
  dia_running() { (( RUNNING )); }
  touch "$STATE_FILE"
  helper_repair
  [[ "$EVENTS" == "archive apply receipt " ]] || fail "official stale state: $EVENTS"
  release_lock
  EVENTS=""; OFFICIAL=0
  helper_repair
  [[ "$EVENTS" == "launch receipt " ]] || fail "verified repair not idempotent: $EVENTS"
  release_lock
  EVENTS=""; VERIFIED=0
  helper_repair
  [[ "$EVENTS" == "restore apply receipt " ]] || fail "damaged repair: $EVENTS"
  release_lock
  MATCHING=0; OFFICIAL=0
  if (helper_repair) 2>/dev/null; then fail "cross-build recovery allowed"; fi
  release_lock
  RUNNING=1; HELPER_BACKGROUND=1
  if helper_repair; then fail "background mutated running browser"; fi
  print "Engine regressions passed (locking, startup, recovery, idempotence, cross-build and running-browser guards)."
  ' "$ENGINE/helper-driver.zsh" "$ENGINE/helper-driver.zsh"
