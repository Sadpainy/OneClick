# hash generation and command authentication skeleton

ZC_ROOT="/data/local/zc"
ZC_LOG="$ZC_ROOT/zc.log"
ZC_DB="$ZC_ROOT/state.db"
ZC_HASH_DB="$ZC_ROOT/hash_state.db"
ZC_HASH_LOG="$ZC_ROOT/hash.log"
ZC_SALT_FILE="$ZC_ROOT/.salt"
ZC_HASH_ALGO="sha256"
ZC_HASH_ALGO_ALT="sha1"
ZC_HASH_ALGO_FALLBACK="md5"
ZC_HASH_LEN=64
ZC_VERSION="1.0"
ZC_SALT_LEN=32

zc_hash_log() {
  local msg="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts] $msg" >> "$ZC_LOG" 2>/dev/null
  echo "[$ts] $msg" >> "$ZC_HASH_LOG" 2>/dev/null
}

zc_hash_init_dirs() {
  mkdir -p "$ZC_ROOT" 2>/dev/null
  chmod 700 "$ZC_ROOT" 2>/dev/null
  zc_hash_log "hash dirs initialized"
}

zc_hash_init_db() {
  if [ ! -f "$ZC_HASH_DB" ]; then
    echo "CREATE TABLE hashes (id TEXT PRIMARY KEY, value TEXT, ts TEXT);" | sqlite3 "$ZC_HASH_DB" 2>/dev/null
    echo "CREATE TABLE nonces (nonce TEXT PRIMARY KEY, ts TEXT);" | sqlite3 "$ZC_HASH_DB" 2>/dev/null
    echo "CREATE TABLE hash_state (key TEXT PRIMARY KEY, value TEXT);" | sqlite3 "$ZC_HASH_DB" 2>/dev/null
    zc_hash_log "hash db initialized"
  fi
}

zc_hash_state_set() {
  local key="$1"
  local value="$2"
  echo "INSERT OR REPLACE INTO hash_state (key, value) VALUES ('$key', '$value');" | sqlite3 "$ZC_HASH_DB" 2>/dev/null
}

zc_hash_state_get() {
  local key="$1"
  sqlite3 "$ZC_HASH_DB" "SELECT value FROM hash_state WHERE key='$key';" 2>/dev/null
}

zc_hash_store() {
  local id="$1"
  local value="$2"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO hashes (id, value, ts) VALUES ('$id', '$value', '$ts');" | sqlite3 "$ZC_HASH_DB" 2>/dev/null
}

zc_hash_store_get() {
  local id="$1"
  sqlite3 "$ZC_HASH_DB" "SELECT value FROM hashes WHERE id='$id';" 2>/dev/null
}

zc_hash_nonce_add() {
  local nonce="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO nonces (nonce, ts) VALUES ('$nonce', '$ts');" | sqlite3 "$ZC_HASH_DB" 2>/dev/null
}

zc_hash_nonce_seen() {
  local nonce="$1"
  local count
  count=$(sqlite3 "$ZC_HASH_DB" "SELECT COUNT(*) FROM nonces WHERE nonce='$nonce';" 2>/dev/null)
  if [ "$count" -gt 0 ]; then
    return 0
  fi
  return 1
}

zc_hash_check_tools() {
  local tool
  for tool in openssl sha256sum sha1sum md5sum; do
    if command -v "$tool" >/dev/null 2>&1; then
      zc_hash_log "tool available: $tool"
    else
      zc_hash_log "tool missing: $tool"
    fi
  done
}

zc_hash_gen_salt() {
  if [ -f "$ZC_SALT_FILE" ]; then
    cat "$ZC_SALT_FILE"
    return 0
  fi
  local salt
  if [ -r /dev/urandom ]; then
    salt=$(head -c "$ZC_SALT_LEN" /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    salt=$(date +%s%N | sha256sum | awk '{print $1}')
  fi
  echo "$salt" > "$ZC_SALT_FILE" 2>/dev/null
  chmod 600 "$ZC_SALT_FILE" 2>/dev/null
  zc_hash_log "salt generated"
  echo "$salt"
}

zc_hash_rotate_salt() {
  local salt
  salt=$(head -c "$ZC_SALT_LEN" /dev/urandom | od -An -tx1 | tr -d ' \n')
  echo "$salt" > "$ZC_SALT_FILE" 2>/dev/null
  zc_hash_log "salt rotated"
  echo "$salt"
}

zc_hash_openssl() {
  local algo="$1"
  local input="$2"
  echo -n "$input" | openssl dgst -"$algo" 2>/dev/null | awk '{print $NF}'
}

zc_hash_openssl_file() {
  local algo="$1"
  local file="$2"
  openssl dgst -"$algo" "$file" 2>/dev/null | awk '{print $NF}'
}

zc_hash_sha256() {
  local input="$1"
  zc_hash_openssl "sha256" "$input"
}

zc_hash_sha1() {
  local input="$1"
  zc_hash_openssl "sha1" "$input"
}

zc_hash_md5() {
  local input="$1"
  zc_hash_openssl "md5" "$input"
}

zc_hash_sha256_file() {
  local file="$1"
  zc_hash_openssl_file "sha256" "$file"
}

zc_hash_sha1_file() {
  local file="$1"
  zc_hash_openssl_file "sha1" "$file"
}

zc_hash_md5_file() {
  local file="$1"
  zc_hash_openssl_file "md5" "$file"
}

zc_hash_with_salt() {
  local input="$1"
  local salt
  salt=$(zc_hash_gen_salt)
  zc_hash_sha256 "$salt$input"
}

zc_hash_with_nonce() {
  local input="$1"
  local nonce
  nonce=$(date +%s%N)
  echo "$nonce$input"
}

zc_hash_verify() {
  local input="$1"
  local expected="$2"
  local actual
  actual=$(zc_hash_sha256 "$input")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_hash_verify_file() {
  local file="$1"
  local expected="$2"
  local actual
  actual=$(zc_hash_sha256_file "$file")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_hash_verify_with_salt() {
  local input="$1"
  local expected="$2"
  local actual
  actual=$(zc_hash_with_salt "$input")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_hash_extract() {
  local line="$1"
  echo "$line" | grep -oE '[a-f0-9]{64}' | head -n 1
}

zc_hash_extract_sha1() {
  local line="$1"
  echo "$line" | grep -oE '[a-f0-9]{40}' | head -n 1
}

zc_hash_extract_md5() {
  local line="$1"
  echo "$line" | grep -oE '[a-f0-9]{32}' | head -n 1
}

zc_hash_extract_any() {
  local line="$1"
  local h
  h=$(zc_hash_extract "$line")
  if [ -n "$h" ]; then
    echo "$h"
    return 0
  fi
  h=$(zc_hash_extract_sha1 "$line")
  if [ -n "$h" ]; then
    echo "$h"
    return 0
  fi
  h=$(zc_hash_extract_md5 "$line")
  if [ -n "$h" ]; then
    echo "$h"
    return 0
  fi
  return 1
}

zc_hash_is_valid() {
  local hash="$1"
  if [ ${#hash} -ne "$ZC_HASH_LEN" ]; then
    return 1
  fi
  if echo "$hash" | grep -qE '^[a-f0-9]+$'; then
    return 0
  fi
  return 1
}

zc_hash_is_valid_sha1() {
  local hash="$1"
  if [ ${#hash} -ne 40 ]; then
    return 1
  fi
  if echo "$hash" | grep -qE '^[a-f0-9]+$'; then
    return 0
  fi
  return 1
}

zc_hash_is_valid_md5() {
  local hash="$1"
  if [ ${#hash} -ne 32 ]; then
    return 1
  fi
  if echo "$hash" | grep -qE '^[a-f0-9]+$'; then
    return 0
  fi
  return 1
}

zc_hash_compare() {
  local a="$1"
  local b="$2"
  if [ "$a" = "$b" ]; then
    return 0
  fi
  return 1
}

zc_hash_constant_compare() {
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

zc_hash_sign() {
  local payload="$1"
  local key="$2"
  echo -n "$payload" | openssl dgst -sha256 -hmac "$key" 2>/dev/null | awk '{print $NF}'
}

zc_hash_verify_sign() {
  local payload="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual=$(zc_hash_sign "$payload" "$key")
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_hash_bind_timestamp() {
  local payload="$1"
  local ts
  ts=$(date +%s)
  echo "$ts$payload"
}

zc_hash_check_timestamp() {
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

zc_hash_gen_nonce() {
  local nonce
  nonce=$(head -c 16 /dev/urandom | od -An -tx1 | tr -d ' \n')
  zc_hash_nonce_add "$nonce"
  echo "$nonce"
}

zc_hash_check_replay() {
  local nonce="$1"
  if zc_hash_nonce_seen "$nonce"; then
    zc_hash_log "replay detected: $nonce"
    return 0
  fi
  return 1
}

zc_hash_build_command() {
  local cmd="$1"
  local nonce
  local ts
  local sig
  nonce=$(zc_hash_gen_nonce)
  ts=$(date +%s)
  sig=$(zc_hash_sign "$nonce$ts$cmd" "$(zc_hash_gen_salt)")
  echo "$nonce:$ts:$sig:$cmd"
}

zc_hash_parse_command() {
  local payload="$1"
  local nonce
  local ts
  local sig
  local cmd
  nonce=$(echo "$payload" | cut -d: -f1)
  ts=$(echo "$payload" | cut -d: -f2)
  sig=$(echo "$payload" | cut -d: -f3)
  cmd=$(echo "$payload" | cut -d: -f4-)
  echo "$nonce $ts $sig $cmd"
}

zc_hash_validate_command() {
  local payload="$1"
  local parsed
  parsed=$(zc_hash_parse_command "$payload")
  local nonce
  local ts
  local sig
  local cmd
  nonce=$(echo "$parsed" | awk '{print $1}')
  ts=$(echo "$parsed" | awk '{print $2}')
  sig=$(echo "$parsed" | awk '{print $3}')
  cmd=$(echo "$parsed" | awk '{print $4}')
  if zc_hash_check_replay "$nonce"; then
    return 1
  fi
  if ! zc_hash_check_timestamp "$ts" 300; then
    zc_hash_log "timestamp expired"
    return 1
  fi
  if ! zc_hash_verify_sign "$nonce$ts$cmd" "$(zc_hash_gen_salt)" "$sig"; then
    zc_hash_log "signature invalid"
    return 1
  fi
  zc_hash_nonce_add "$nonce"
  zc_hash_log "command validated"
  return 0
}

zc_hash_batch_file() {
  local file="$1"
  if [ ! -f "$file" ]; then
    return 1
  fi
  local line
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    local h
    h=$(zc_hash_sha256 "$line")
    echo "$h $line"
  done < "$file"
}

zc_hash_batch_verify() {
  local file="$1"
  local expected_file="$2"
  if [ ! -f "$file" ] || [ ! -f "$expected_file" ]; then
    return 1
  fi
  local ok=0
  local fail=0
  local line
  while IFS= read -r line; do
    local h
    h=$(echo "$line" | awk '{print $1}')
    local rest
    rest=$(echo "$line" | cut -d' ' -f2-)
    local actual
    actual=$(zc_hash_sha256 "$rest")
    if [ "$actual" = "$h" ]; then
      ok=$((ok + 1))
    else
      fail=$((fail + 1))
    fi
  done < "$file"
  zc_hash_log "batch verify ok=$ok fail=$fail"
  echo "$ok $fail"
}

zc_hash_export() {
  local out="$1"
  sqlite3 "$ZC_HASH_DB" "SELECT id, value FROM hashes;" 2>/dev/null > "$out"
  zc_hash_log "exported hashes to $out"
}

zc_hash_import() {
  local in="$1"
  if [ ! -f "$in" ]; then
    return 1
  fi
  local line
  while IFS= read -r line; do
    local id
    local value
    id=$(echo "$line" | cut -d'|' -f1)
    value=$(echo "$line" | cut -d'|' -f2)
    if [ -n "$id" ] && [ -n "$value" ]; then
      zc_hash_store "$id" "$value"
    fi
  done < "$in"
  zc_hash_log "imported hashes from $in"
}

zc_hash_cleanup_nonces() {
  local cutoff
  cutoff=$(date -d "1 hour ago" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
  if [ -z "$cutoff" ]; then
    cutoff=$(date +"%Y-%m-%d %H:%M:%S")
  fi
  echo "DELETE FROM nonces WHERE ts < '$cutoff';" | sqlite3 "$ZC_HASH_DB" 2>/dev/null
  zc_hash_log "nonces cleaned"
}

zc_hash_self_test() {
  local test_input="zc_selftest"
  local h
  h=$(zc_hash_sha256 "$test_input")
  if [ ${#h} -ne 64 ]; then
    zc_hash_log "self test failed"
    return 1
  fi
  local expected
  expected=$(echo -n "$test_input" | sha256sum | awk '{print $1}')
  if [ "$h" != "$expected" ]; then
    zc_hash_log "self test mismatch"
    return 1
  fi
  zc_hash_log "self test passed"
  return 0
}

zc_hash_status() {
  echo "ZC hash version: $ZC_VERSION"
  echo "algo: $ZC_HASH_ALGO"
  echo "algo alt: $ZC_HASH_ALGO_ALT"
  echo "algo fallback: $ZC_HASH_ALGO_FALLBACK"
  echo "salt file: $ZC_SALT_FILE"
  echo "stored hashes: $(sqlite3 "$ZC_HASH_DB" "SELECT COUNT(*) FROM hashes;" 2>/dev/null)"
  echo "stored nonces: $(sqlite3 "$ZC_HASH_DB" "SELECT COUNT(*) FROM nonces;" 2>/dev/null)"
  echo "hash db: $ZC_HASH_DB"
  echo "hash log: $ZC_HASH_LOG"
}

zc_hash_main() {
  zc_hash_log "SHA256.sh1 start"
  zc_hash_init_dirs
  zc_hash_init_db
  zc_hash_check_tools
  zc_hash_gen_salt
  zc_hash_state_set "version" "$ZC_VERSION"
  zc_hash_self_test
  zc_hash_cleanup_nonces
  zc_hash_status
  zc_hash_log "SHA256.sh1 done"
}

case "$1" in
  start)
    zc_hash_main
    ;;
  sha256)
    zc_hash_sha256 "$2"
    ;;
  sha1)
    zc_hash_sha1 "$2"
    ;;
  md5)
    zc_hash_md5 "$2"
    ;;
  file)
    zc_hash_sha256_file "$2"
    ;;
  verify)
    zc_hash_verify "$2" "$3"
    ;;
  sign)
    zc_hash_sign "$2" "$3"
    ;;
  validate)
    zc_hash_validate_command "$2"
    ;;
  build)
    zc_hash_build_command "$2"
    ;;
  salt)
    zc_hash_gen_salt
    ;;
  rotate)
    zc_hash_rotate_salt
    ;;
  selftest)
    zc_hash_self_test
    ;;
  clean)
    zc_hash_cleanup_nonces
    ;;
  status)
    zc_hash_status
    ;;
  *)
    zc_hash_main
    ;;
esac

exit 0