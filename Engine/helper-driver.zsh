#!/bin/zsh
# Stored next to the pinned upstream dia-zh.command inside the app bundle.
set -euo pipefail
export DIA_ZH_LIBRARY_ONLY=1
source "${0:A:h}/dia-zh.command"
typeset -g HELPER_BACKGROUND=0 HELPER_GUARD_FD=0

dia_running() {
  pgrep -x Dia >/dev/null 2>&1
}

other_installer_running() {
  pgrep -f 'dia-zh[.]command (apply|restore)|scripts/sign-app[.]zsh' >/dev/null 2>&1
}

# The file descriptor lock covers inspection, recovery and patching. The kernel
# releases it on process exit, including SIGKILL, unlike the upstream directory.
guard_transaction() {
  mkdir -p "$STATE_ROOT"
  zmodload zsh/system
  touch "$STATE_ROOT/helper-operation.lock"
  if ! zsystem flock -t 0 -f HELPER_GUARD_FD "$STATE_ROOT/helper-operation.lock"; then
    warn "另一个安装或检查任务正在进行，请稍后重试。"
    return 75
  fi
}

acquire_lock() {
  (( LOCK_HELD )) && return 0
  mkdir -p "$STATE_ROOT"
  if [[ -d "$LOCK_DIR" ]]; then
    local owner="" modified age
    [[ -f "$LOCK_DIR/pid" ]] && owner="$(<"$LOCK_DIR/pid")"
    if [[ "$owner" == <-> ]] && kill -0 "$owner" 2>/dev/null; then
      die "补丁安装进程仍在运行（PID $owner），请稍后重试。"
    fi
    other_installer_running && die "检测到其他安装器正在运行，请稍后重试。"
    modified="$(stat -f %m "$LOCK_DIR")"
    age=$(( $(date +%s) - modified ))
    (( age >= 10 )) || die "安装锁刚被创建，请稍后重试。"
    # Keep abandoned locks for diagnosis; never remove an unverified live lock.
    mv "$LOCK_DIR" "$STATE_ROOT/abandoned-lock-$(date -u +%Y%m%dT%H%M%SZ)-$$"
    log "已归档上次中断留下的安装锁。"
  fi
  mkdir "$LOCK_DIR" || die "无法获得安装锁。"
  print -r -- "$$" > "$LOCK_DIR/pid"
  LOCK_HELD=1
}

release_lock() {
  if (( LOCK_HELD )); then
    if [[ -f "$LOCK_DIR/pid" && "$(<"$LOCK_DIR/pid")" == "$$" ]]; then
      rm "$LOCK_DIR/pid"
      rmdir "$LOCK_DIR" 2>/dev/null || true
    fi
    LOCK_HELD=0
  fi
}

# Background checks must not quit a browser opened after the initial check.
functions[upstream_stop_dia]="$functions[stop_dia]"
stop_dia() {
  if (( HELPER_BACKGROUND )) && dia_running; then
    die "Dia 已启动，本次后台安装暂停；退出后再试。"
  fi
  upstream_stop_dia "${1:-0}"
}

launch_and_verify() {
  log "正在启动 Dia 并检查进程稳定性…"
  open -a "$APP_PATH" || return 1
  local attempt
  for attempt in {1..30}; do
    dia_running && break
    sleep 0.5
  done
  dia_running || return 1
  sleep 3
  dia_running || return 1
  log "Dia 进程已启动；如果窗口未出现，请处理系统钥匙串授权提示。"
}

smoke_test() {
  if (( HELPER_BACKGROUND )); then
    log "后台模式：文件校验完成后保持 Dia 关闭，标记为待启动验证。"
    return 0
  fi
  launch_and_verify
}

renderer_running() {
  ps -axo comm= | awk -v prefix="$APP_PATH/Contents/Frameworks/" '
    index($0, prefix) && /\/Browser Helper \((Aperitif )?Renderer\)$/ { found=1 }
    END { exit !found }'
}

record_launch_check() {
  # A main process blocked by a Keychain prompt is not a verified startup.
  if ! renderer_running; then
    log "启动验证尚未完成：等待浏览器页面或系统授权。"
    return 0
  fi
  shasum -a 256 "$STATE_FILE" | awk '{print $1}' > "$STATE_ROOT/helper-startup-verified"
}

helper_status() {
  show_status
  if state_matches_current_build && [[ "$(state_value STATUS)" == applied ]]; then
    if verify_official_signature_path "$APP_PATH"; then
      print -r -- "资源校验：失败（官方应用已覆盖补丁）"
    elif (audit_all) >/dev/null 2>&1; then
      print -r -- "资源校验：通过"
      if dia_running && ! renderer_running; then
        print -r -- "启动检查：等待窗口或系统授权"
      elif [[ -f "$STATE_ROOT/helper-startup-verified" &&
            "$(<"$STATE_ROOT/helper-startup-verified")" == "$(shasum -a 256 "$STATE_FILE" | awk '{print $1}')" ]]; then
        print -r -- "启动检查：通过"
      else
        print -r -- "启动检查：待验证"
      fi
    else
      print -r -- "资源校验：失败"
    fi
  else
    print -r -- "资源校验：未完成"
  fi
}

helper_repair() {
  require_macos
  require_common_project_files
  require_app
  if (( HELPER_BACKGROUND )) && dia_running; then
    log "Dia 正在运行，等待退出后修复。"
    return 75
  fi
  acquire_lock
  trap 'release_lock' EXIT

  if verify_official_signature_path "$APP_PATH"; then
    # An intact official bundle is authoritative, even for the same build.
    # Archive stale applying/applied state without replacing a healthy app.
    if [[ -f "$STATE_FILE" ]]; then
      archive_superseded_state
    fi
  else
    state_matches_current_build || die "签名异常且没有匹配此版本的状态，请先恢复官方 Dia。"
    if [[ "$(state_value STATUS)" == applied ]] && (audit_all) >/dev/null 2>&1; then
      log "当前补丁资源与签名均已校验，无需重复安装。"
      if (( ! HELPER_BACKGROUND )); then
        launch_and_verify || die "资源完整，但 Dia 启动失败；请恢复官方版。"
        record_launch_check
      fi
      return 0
    fi
    log "上次安装未完成或资源损坏，先恢复同版本官方备份。"
    restore_from_state 0
  fi

  apply_patch_transaction
  if ! (audit_all); then
    warn "安装后的资源审计失败，恢复官方备份。"
    restore_from_state 0
    return 1
  fi
  if (( ! HELPER_BACKGROUND )); then record_launch_check; fi
}

helper_main() {
  guard_transaction
  case "${1:-status}" in
    status) helper_status ;;
    repair) helper_repair ;;
    repair-background) HELPER_BACKGROUND=1; helper_repair ;;
    audit) audit_all ;;
    restore) restore_command ;;
    launch)
      (audit_all) || die "资源校验未通过，请先检查并修复。"
      launch_and_verify || die "Dia 启动失败。"
      record_launch_check ;;
    *) die "未知助手命令。" ;;
  esac
}

if [[ "${DIA_ZH_DRIVER_LIBRARY_ONLY:-0}" != 1 ]]; then
  helper_main "${1:-status}"
fi
