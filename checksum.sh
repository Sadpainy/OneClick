# Checksum.sh - hash verification and integrity check skeleton

ZC_ROOT="/data/local/zc"
ZC_LOG="$ZC_ROOT/zc.log"
ZC_DB="$ZC_ROOT/state.db"
ZC_CHK_DB="$ZC_ROOT/chk_state.db"
ZC_CHK_LOG="$ZC_ROOT/chk.log"
ZC_SIG_FILE="$ZC_ROOT/.sig"
ZC_HASH_ALGO="sha256"
ZC_HASH_LEN=64
ZC_VERSION="1.0"
ZC_TIME_WINDOW=300
ZC_MAX_BATCH=1000
ZC_CHK_RETRY=3

zc_chk_log() {
  local msg="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts] $msg" >> "$ZC_LOG" 2>/dev/null
  echo "[$ts] $msg" >> "$ZC_CHK_LOG" 2>/dev/null
}

zc_chk_init_dirs() {
  mkdir -p "$ZC_ROOT" 2>/dev/null
  chmod 700 "$ZC_ROOT" 2>/dev/null
  zc_chk_log "chk dirs initialized"
}

zc_chk_init_db() {
  if [ ! -f "$ZC_CHK_DB" ]; then
    echo "CREATE TABLE checks (id TEXT PRIMARY KEY, value TEXT, status TEXT, ts TEXT);" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
    echo "CREATE TABLE nonces (nonce TEXT PRIMARY KEY, ts TEXT);" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
    echo "CREATE TABLE chk_state (key TEXT PRIMARY KEY, value TEXT);" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
    zc_chk_log "chk db initialized"
  fi
}

zc_chk_state_set() {
  local key="$1"
  local value="$2"
  echo "INSERT OR REPLACE INTO chk_state (key, value) VALUES ('$key', '$value');" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
}

zc_chk_state_get() {
  local key="$1"
  sqlite3 "$ZC_CHK_DB" "SELECT value FROM chk_state WHERE key='$key';" 2>/dev/null
}

zc_chk_store() {
  local id="$1"
  local value="$2"
  local status="$3"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO checks (id, value, status, ts) VALUES ('$id', '$value', '$status', '$ts');" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
}

zc_chk_get() {
  local id="$1"
  sqlite3 "$ZC_CHK_DB" "SELECT value FROM checks WHERE id='$id';" 2>/dev/null
}

zc_chk_get_status() {
  local id="$1"
  sqlite3 "$ZC_CHK_DB" "SELECT status FROM checks WHERE id='$id';" 2>/dev/null
}

zc_chk_mark() {
  local id="$1"
  local status="$2"
  echo "UPDATE checks SET status='$status' WHERE id='$id';" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
}

zc_chk_nonce_add() {
  local nonce="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO nonces (nonce, ts) VALUES ('$nonce', '$ts');" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
}

zc_chk_nonce_seen() {
  local nonce="$1"
  local count
  count=$(sqlite3 "$ZC_CHK_DB" "SELECT COUNT(*) FROM nonces WHERE nonce='$nonce';" 2>/dev/null)
  if [ "$count" -gt 0 ]; then
    return 0
  fi
  return 1
}

zc_chk_check_tools() {
  local tool
  for tool in openssl sha256sum sha1sum md5sum; do
    if command -v "$tool" >/dev/null 2>&1; then
      zc_chk_log "tool available: $tool"
    else
      zc_chk_log "tool missing: $tool"
    fi
  done
}

zc_chk_hash() {
  local input="$1"
  echo -n "$input" | openssl dgst -"$ZC_HASH_ALGO" 2>/dev/null | awk '{print $NF}'
}

zc_chk_hash_file() {
  local file="$1"
  openssl dgst -"$ZC_HASH_ALGO" "$file" 2>/dev/null | awk '{print $NF}'
}

zc_chk_hash_sha1() {
  local input="$1"
  echo -n "$input" | openssl dgst -sha1 2>/dev/null | awk '{print $NF}'
}

zc_chk_hash_md5() {
  local input="$1"
  echo -n "$input" | openssl dgst -md5 2>/dev/null | awk '{print $NF}'
}

zc_chk_verify() {
  local input="$1"
  local expected="$2"
  local actual
  actual=$(zc_chk_hash "$input")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_chk_verify_file() {
  local file="$1"
  local expected="$2"
  local actual
  actual=$(zc_chk_hash_file "$file")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_chk_verify_sha1() {
  local input="$1"
  local expected="$2"
  local actual
  actual=$(zc_chk_hash_sha1 "$input")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_chk_verify_md5() {
  local input="$1"
  local expected="$2"
  local actual
  actual=$(zc_chk_hash_md5 "$input")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_chk_constant_compare() {
  local a="$1"
  local b="$2"
  local result=0
  local i
  if [ ${#a} -ne ${#b} ]; then
    return 1
  fi
  for i in $(seq 1 ${#a}); do
    local ca
    local cb
    ca=$(echo "$a" | cut -c "$i")
    cb=$(echo "$b" | cut -c "$i")
    if [ "$ca" != "$cb" ]; then
      result=1
    fi
  done
  return "$result"
}

zc_chk_is_valid_hash() {
  local hash="$1"
  if [ ${#hash} -ne "$ZC_HASH_LEN" ]; then
    return 1
  fi
  if echo "$hash" | grep -qE '^[a-f0-9]+$'; then
    return 0
  fi
  return 1
}

zc_chk_is_valid_sha1() {
  local hash="$1"
  if [ ${#hash} -ne 40 ]; then
    return 1
  fi
  if echo "$hash" | grep -qE '^[a-f0-9]+$'; then
    return 0
  fi
  return 1
}

zc_chk_is_valid_md5() {
  local hash="$1"
  if [ ${#hash} -ne 32 ]; then
    return 1
  fi
  if echo "$hash" | grep -qE '^[a-f0-9]+$'; then
    return 0
  fi
  return 1
}

zc_chk_extract_hash() {
  local line="$1"
  echo "$line" | grep -oE '[a-f0-9]{64}' | head -n 1
}

zc_chk_extract_any() {
  local line="$1"
  local h
  h=$(echo "$line" | grep -oE '[a-f0-9]{64}' | head -n 1)
  if [ -n "$h" ]; then
    echo "$h"
    return 0
  fi
  h=$(echo "$line" | grep -oE '[a-f0-9]{40}' | head -n 1)
  if [ -n "$h" ]; then
    echo "$h"
    return 0
  fi
  h=$(echo "$line" | grep -oE '[a-f0-9]{32}' | head -n 1)
  if [ -n "$h" ]; then
    echo "$h"
    return 0
  fi
  return 1
}

zc_chk_sign() {
  local payload="$1"
  local key="$2"
  echo -n "$payload" | openssl dgst -sha256 -hmac "$key" 2>/dev/null | awk '{print $NF}'
}

zc_chk_verify_sign() {
  local payload="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual=$(zc_chk_sign "$payload" "$key")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_chk_check_timestamp() {
  local ts="$1"
  local window="$2"
  local now
  now=$(date +%s)
  local diff
  diff=$((now - ts))
  if [ "$diff" -lt 0 ]; then
    diff=$((-diff))
  fi
  if [ "$diff" -le "$window" ]; then
    return 0
  fi
  return 1
}

zc_chk_check_replay() {
  local nonce="$1"
  if zc_chk_nonce_seen "$nonce"; then
    zc_chk_log "replay detected: $nonce"
    return 0
  fi
  return 1
}

zc_chk_validate_command() {
  local payload="$1"
  local nonce
  local ts
  local sig
  local cmd
  nonce=$(echo "$payload" | cut -d: -f1)
  ts=$(echo "$payload" | cut -d: -f2)
  sig=$(echo "$payload" | cut -d: -f3)
  cmd=$(echo "$payload" | cut -d: -f4-)
  if [ -z "$nonce" ] || [ -z "$ts" ] || [ -z "$sig" ]; then
    zc_chk_log "command malformed"
    return 1
  fi
  if zc_chk_check_replay "$nonce"; then
    return 1
  fi
  if ! zc_chk_check_timestamp "$ts" "$ZC_TIME_WINDOW"; then
    zc_chk_log "timestamp expired"
    return 1
  fi
  local key
  key=$(cat "$ZC_ROOT/.key" 2>/dev/null)
  if [ -z "$key" ]; then
    zc_chk_log "key missing"
    return 1
  fi
  if ! zc_chk_verify_sign "$nonce$ts$cmd" "$key" "$sig"; then
    zc_chk_log "signature invalid"
    return 1
  fi
  zc_chk_nonce_add "$nonce"
  zc_chk_store "$nonce" "$sig" "valid"
  zc_chk_log "command validated"
  return 0
}

zc_chk_batch_verify() {
  local file="$1"
  if [ ! -f "$file" ]; then
    zc_chk_log "batch file missing"
    return 1
  fi
  local ok=0
  local fail=0
  local count=0
  local line
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    count=$((count + 1))
    if [ "$count" -gt "$ZC_MAX_BATCH" ]; then
      zc_chk_log "batch limit reached"
      break
    fi
    local h
    h=$(echo "$line" | awk '{print $1}')
    local rest
    rest=$(echo "$line" | cut -d' ' -f2-)
    if zc_chk_verify "$rest" "$h"; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
      zc_chk_log "batch fail: $h"
    fi
  done < "$file"
  zc_chk_log "batch verify ok=$ok fail=$fail"
  echo "$ok $fail"
}

zc_chk_batch_files() {
  local dir="$1"
  if [ ! -d "$dir" ]; then
    return 1
  fi
  local f
  local ok=0
  local fail=0
  for f in "$dir"/*; do
    if [ -f "$f" ]; then
      local h
      h=$(zc_chk_hash_file "$f")
      if [ -n "$h" ]; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
      fi
    fi
  done
  zc_chk_log "batch files ok=$ok fail=$fail"
  echo "$ok $fail"
}

zc_chk_verify_manifest() {
  local manifest="$1"
  if [ ! -f "$manifest" ]; then
    zc_chk_log "manifest missing"
    return 1
  fi
  local ok=0
  local fail=0
  local line
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    local path
    local expected
    path=$(echo "$line" | awk '{print $1}')
    expected=$(echo "$line" | awk '{print $2}')
    if [ -f "$path" ]; then
      if zc_chk_verify_file "$path" "$expected"; then
        ok=$((ok + 1))
      else
        fail=$((fail + 1))
        zc_chk_log "manifest fail: $path"
      fi
    else
      fail=$((fail + 1))
      zc_chk_log "manifest missing: $path"
    fi
  done < "$manifest"
  zc_chk_log "manifest verify ok=$ok fail=$fail"
  echo "$ok $fail"
}

zc_chk_retry() {
  local input="$1"
  local expected="$2"
  local attempts="$3"
  local i=1
  while [ "$i" -le "$attempts" ]; do
    if zc_chk_verify "$input" "$expected"; then
      zc_chk_log "retry success at $i"
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  zc_chk_log "retry exhausted"
  return 1
}

zc_chk_fail_handler() {
  local reason="$1"
  zc_chk_log "chk fail: $reason"
  zc_chk_state_set "last_fail" "$reason"
  return 1
}

zc_chk_cleanup_nonces() {
  local cutoff
  cutoff=$(date -d "1 hour ago" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
  if [ -z "$cutoff" ]; then
    return 0
  fi
  echo "DELETE FROM nonces WHERE ts < '$cutoff';" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
  zc_chk_log "nonces cleaned"
}

zc_chk_cleanup_checks() {
  local cutoff
  cutoff=$(date -d "24 hours ago" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
  if [ -z "$cutoff" ]; then
    return 0
  fi
  echo "DELETE FROM checks WHERE ts < '$cutoff' AND status='valid';" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
  zc_chk_log "checks cleaned"
}

zc_chk_self_test() {
  local test_input="zc_selftest"
  local expected
  expected=$(echo -n "$test_input" | sha256sum | awk '{print $1}')
  local actual
  actual=$(zc_chk_hash "$test_input")
  if [ "$actual" != "$expected" ]; then
    zc_chk_log "self test mismatch"
    return 1
  fi
  local key="zc_test_key"
  local sig
  sig=$(zc_chk_sign "$test_input" "$key")
  if ! zc_chk_verify_sign "$test_input" "$key" "$sig"; then
    zc_chk_log "self test sign failed"
    return 1
  fi
  zc_chk_log "self test passed"
  return 0
}

zc_chk_status() {
  echo "ZC chk version: $ZC_VERSION"
  echo "algo: $ZC_HASH_ALGO"
  echo "time window: $ZC_TIME_WINDOW"
  echo "stored checks: $(sqlite3 "$ZC_CHK_DB" "SELECT COUNT(*) FROM checks;" 2>/dev/null)"
  echo "stored nonces: $(sqlite3 "$ZC_CHK_DB" "SELECT COUNT(*) FROM nonces;" 2>/dev/null)"
  echo "chk db: $ZC_CHK_DB"
  echo "chk log: $ZC_CHK_LOG"
}

zc_chk_main() {
  zc_chk_log "Checksum.sh start"
  zc_chk_init_dirs
  zc_chk_init_db
  zc_chk_check_tools
  zc_chk_state_set "version" "$ZC_VERSION"
  zc_chk_self_test
  zc_chk_cleanup_nonces
  zc_chk_cleanup_checks
  zc_chk_status
  zc_chk_log "Checksum.sh done"
}

case "$1" in
  start)
    zc_chk_main
    ;;
  verify)
    zc_chk_verify "$2" "$3"
    ;;
  file)
    zc_chk_verify_file "$2" "$3"
    ;;
  sha1)
    zc_chk_verify_sha1 "$2" "$3"
    ;;
  md5)
    zc_chk_verify_md5 "$2" "$3"
    ;;
  sign)
    zc_chk_sign "$2" "$3"
    ;;
  validate)
    zc_chk_validate_command "$2"
    ;;
  batch)
    zc_chk_batch_verify "$2"
    ;;
  manifest)
    zc_chk_verify_manifest "$2"
    ;;
  retry)
    zc_chk_retry "$2" "$3" "$ZC_CHK_RETRY"
    ;;
  extract)
    zc_chk_extract_any "$2"
    ;;
  selftest)
    zc_chk_self_test
    ;;
  clean)
    zc_chk_cleanup_nonces
    zc_chk_cleanup_checks
    ;;
  status)
    zc_chk_status
    ;;
  *)
    zc_chk_main
    ;;
esac

exit 0