# Decrypt.sh - command decryption and payload decoding skeleton

ZC_ROOT="/data/local/zc"
ZC_LOG="$ZC_ROOT/zc.log"
ZC_DB="$ZC_ROOT/state.db"
ZC_CRYPT_DB="$ZC_ROOT/crypt_state.db"
ZC_CRYPT_LOG="$ZC_ROOT/crypt.log"
ZC_KEY_FILE="$ZC_ROOT/.key"
ZC_KEY_ALT_FILE="$ZC_ROOT/.key.alt"
ZC_IV_FILE="$ZC_ROOT/.iv"
ZC_KEY_LEN=32
ZC_IV_LEN=16
ZC_VERSION="1.0"
ZC_CIPHER="aes-256-cbc"
ZC_CIPHER_ALT="aes-128-cbc"
ZC_KDF_ITER=10000
ZC_MAX_LAYERS=5

zc_crypt_log() {
  local msg="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts] $msg" >> "$ZC_LOG" 2>/dev/null
  echo "[$ts] $msg" >> "$ZC_CRYPT_LOG" 2>/dev/null
}

zc_crypt_init_dirs() {
  mkdir -p "$ZC_ROOT" 2>/dev/null
  chmod 700 "$ZC_ROOT" 2>/dev/null
  zc_crypt_log "crypt dirs initialized"
}

zc_crypt_init_db() {
  if [ ! -f "$ZC_CRYPT_DB" ]; then
    echo "CREATE TABLE keys (id TEXT PRIMARY KEY, value TEXT, ts TEXT);" | sqlite3 "$ZC_CRYPT_DB" 2>/dev/null
    echo "CREATE TABLE payloads (id TEXT PRIMARY KEY, data TEXT, status TEXT, ts TEXT);" | sqlite3 "$ZC_CRYPT_DB" 2>/dev/null
    echo "CREATE TABLE crypt_state (key TEXT PRIMARY KEY, value TEXT);" | sqlite3 "$ZC_CRYPT_DB" 2>/dev/null
    zc_crypt_log "crypt db initialized"
  fi
}

zc_crypt_state_set() {
  local key="$1"
  local value="$2"
  echo "INSERT OR REPLACE INTO crypt_state (key, value) VALUES ('$key', '$value');" | sqlite3 "$ZC_CRYPT_DB" 2>/dev/null
}

zc_crypt_state_get() {
  local key="$1"
  sqlite3 "$ZC_CRYPT_DB" "SELECT value FROM crypt_state WHERE key='$key';" 2>/dev/null
}

zc_crypt_store_key() {
  local id="$1"
  local value="$2"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO keys (id, value, ts) VALUES ('$id', '$value', '$ts');" | sqlite3 "$ZC_CRYPT_DB" 2>/dev/null
}

zc_crypt_get_key() {
  local id="$1"
  sqlite3 "$ZC_CRYPT_DB" "SELECT value FROM keys WHERE id='$id';" 2>/dev/null
}

zc_crypt_store_payload() {
  local id="$1"
  local data="$2"
  local status="$3"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO payloads (id, data, status, ts) VALUES ('$id', '$data', '$status', '$ts');" | sqlite3 "$ZC_CRYPT_DB" 2>/dev/null
}

zc_crypt_mark_payload() {
  local id="$1"
  local status="$2"
  echo "UPDATE payloads SET status='$status' WHERE id='$id';" | sqlite3 "$ZC_CRYPT_DB" 2>/dev/null
}

zc_crypt_check_tools() {
  local tool
  for tool in openssl base64 xxd od; do
    if command -v "$tool" >/dev/null 2>&1; then
      zc_crypt_log "tool available: $tool"
    else
      zc_crypt_log "tool missing: $tool"
    fi
  done
}

zc_crypt_gen_key() {
  local key
  if [ -r /dev/urandom ]; then
    key=$(head -c "$ZC_KEY_LEN" /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    key=$(date +%s%N | sha256sum | awk '{print $1}')
  fi
  echo "$key"
}

zc_crypt_gen_iv() {
  local iv
  if [ -r /dev/urandom ]; then
    iv=$(head -c "$ZC_IV_LEN" /dev/urandom | od -An -tx1 | tr -d ' \n')
  else
    iv=$(date +%s%N | sha256sum | cut -c1-32)
  fi
  echo "$iv"
}

zc_crypt_init_key() {
  if [ -f "$ZC_KEY_FILE" ]; then
    cat "$ZC_KEY_FILE"
    return 0
  fi
  local key
  key=$(zc_crypt_gen_key)
  echo "$key" > "$ZC_KEY_FILE" 2>/dev/null
  chmod 600 "$ZC_KEY_FILE" 2>/dev/null
  zc_crypt_store_key "primary" "$key"
  zc_crypt_log "primary key generated"
  echo "$key"
}

zc_crypt_get_primary_key() {
  if [ -f "$ZC_KEY_FILE" ]; then
    cat "$ZC_KEY_FILE"
    return 0
  fi
  zc_crypt_init_key
}

zc_crypt_get_alt_key() {
  if [ -f "$ZC_KEY_ALT_FILE" ]; then
    cat "$ZC_KEY_ALT_FILE"
    return 0
  fi
  local key
  key=$(zc_crypt_gen_key)
  echo "$key" > "$ZC_KEY_ALT_FILE" 2>/dev/null
  chmod 600 "$ZC_KEY_ALT_FILE" 2>/dev/null
  zc_crypt_store_key "alt" "$key"
  zc_crypt_log "alt key generated"
  echo "$key"
}

zc_crypt_rotate_key() {
  local old
  old=$(zc_crypt_get_primary_key)
  local new
  new=$(zc_crypt_gen_key)
  echo "$new" > "$ZC_KEY_FILE" 2>/dev/null
  chmod 600 "$ZC_KEY_FILE" 2>/dev/null
  zc_crypt_store_key "primary" "$new"
  zc_crypt_store_key "previous" "$old"
  zc_crypt_log "key rotated"
  echo "$new"
}

zc_crypt_derive_key() {
  local password="$1"
  local salt="$2"
  echo -n "$password$salt" | openssl dgst -sha256 2>/dev/null | awk '{print $NF}'
}

zc_crypt_derive_key_pbkdf2() {
  local password="$1"
  local salt="$2"
  openssl enc -aes-256-cbc -k "$password" -P -md sha256 -S "$salt" 2>/dev/null | grep key | cut -d= -f2
}

zc_crypt_aes_decrypt() {
  local data="$1"
  local key="$2"
  local iv="$3"
  echo "$data" | openssl enc -d -"$ZC_CIPHER" -a -K "$key" -iv "$iv" 2>/dev/null
}

zc_crypt_aes_encrypt() {
  local data="$1"
  local key="$2"
  local iv="$3"
  echo "$data" | openssl enc -e -"$ZC_CIPHER" -a -K "$key" -iv "$iv" 2>/dev/null
}

zc_crypt_aes_decrypt_pass() {
  local data="$1"
  local pass="$2"
  echo "$data" | openssl enc -d -"$ZC_CIPHER" -a -k "$pass" 2>/dev/null
}

zc_crypt_aes_encrypt_pass() {
  local data="$1"
  local pass="$2"
  echo "$data" | openssl enc -e -"$ZC_CIPHER" -a -k "$pass" 2>/dev/null
}

zc_crypt_base64_decode() {
  local data="$1"
  echo "$data" | base64 -d 2>/dev/null
}

zc_crypt_base64_encode() {
  local data="$1"
  echo "$data" | base64 2>/dev/null
}

zc_crypt_hex_decode() {
  local data="$1"
  echo "$data" | xxd -r -p 2>/dev/null
}

zc_crypt_hex_encode() {
  local data="$1"
  echo -n "$data" | xxd -p 2>/dev/null | tr -d '\n'
}

zc_crypt_url_decode() {
  local data="$1"
  printf '%b' "${data//%/\\x}" 2>/dev/null
}

zc_crypt_rot13() {
  local data="$1"
  echo "$data" | tr 'A-Za-z' 'N-ZA-Mn-za-m'
}

zc_crypt_xor() {
  local data="$1"
  local key="$2"
  local out=""
  local i
  local j=0
  local klen=${#key}
  for i in $(seq 1 ${#data}); do
    local c
    c=$(echo "$data" | cut -c "$i")
    local k
    k=$(echo "$key" | cut -c "$((j % klen + 1))")
    local cc
    local kc
    cc=$(printf '%d' "'$c" 2>/dev/null)
    kc=$(printf '%d' "'$k" 2>/dev/null)
    if [ -n "$cc" ] && [ -n "$kc" ]; then
      local xc
      xc=$((cc ^ kc))
      out="$out$(printf "\\$(printf '%03o' "$xc")")"
    fi
    j=$((j + 1))
  done
  echo "$out"
}

zc_crypt_layer_decode() {
  local data="$1"
  local layer="$2"
  case "$layer" in
    base64)
      zc_crypt_base64_decode "$data"
      ;;
    hex)
      zc_crypt_hex_decode "$data"
      ;;
    rot13)
      zc_crypt_rot13 "$data"
      ;;
    url)
      zc_crypt_url_decode "$data"
      ;;
    *)
      echo "$data"
      ;;
  esac
}

zc_crypt_auto_decode() {
  local data="$1"
  local layer=0
  local current="$data"
  while [ "$layer" -lt "$ZC_MAX_LAYERS" ]; do
    local next
    next=$(zc_crypt_base64_decode "$current" 2>/dev/null)
    if [ -n "$next" ] && [ "$next" != "$current" ]; then
      current="$next"
      layer=$((layer + 1))
      continue
    fi
    next=$(zc_crypt_hex_decode "$current" 2>/dev/null)
    if [ -n "$next" ] && [ "$next" != "$current" ]; then
      current="$next"
      layer=$((layer + 1))
      continue
    fi
    break
  done
  zc_crypt_log "auto decode layers: $layer"
  echo "$current"
}

zc_crypt_decrypt_payload() {
  local payload="$1"
  local key
  key=$(zc_crypt_get_primary_key)
  local iv
  iv=$(zc_crypt_gen_iv)
  local decoded
  decoded=$(zc_crypt_aes_decrypt "$payload" "$key" "$iv")
  if [ -z "$decoded" ]; then
    zc_crypt_log "primary decrypt failed, trying alt"
    key=$(zc_crypt_get_alt_key)
    decoded=$(zc_crypt_aes_decrypt "$payload" "$key" "$iv")
  fi
  if [ -z "$decoded" ]; then
    zc_crypt_log "alt decrypt failed, trying pass"
    decoded=$(zc_crypt_aes_decrypt_pass "$payload" "$(zc_crypt_get_primary_key)")
  fi
  echo "$decoded"
}

zc_crypt_decrypt_with_key() {
  local payload="$1"
  local key="$2"
  local iv="$3"
  zc_crypt_aes_decrypt "$payload" "$key" "$iv"
}

zc_crypt_decrypt_with_pass() {
  local payload="$1"
  local pass="$2"
  zc_crypt_aes_decrypt_pass "$payload" "$pass"
}

zc_crypt_unpack() {
  local payload="$1"
  local decoded
  decoded=$(zc_crypt_decrypt_payload "$payload")
  if [ -z "$decoded" ]; then
    zc_crypt_log "unpack failed at decrypt"
    return 1
  fi
  local unpacked
  unpacked=$(zc_crypt_auto_decode "$decoded")
  if [ -z "$unpacked" ]; then
    zc_crypt_log "unpack failed at auto decode"
    return 1
  fi
  zc_crypt_log "unpack success"
  echo "$unpacked"
}

zc_crypt_verify_integrity() {
  local payload="$1"
  local expected="$2"
  local actual
  actual=$(echo -n "$payload" | openssl dgst -sha256 2>/dev/null | awk '{print $NF}')
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_crypt_check_hmac() {
  local payload="$1"
  local key="$2"
  local expected="$3"
  local actual
  actual=$(echo -n "$payload" | openssl dgst -sha256 -hmac "$key" 2>/dev/null | awk '{print $NF}')
  if [ "$actual" = "$expected" ]; then
    return 0
  fi
  return 1
}

zc_crypt_strip_header() {
  local payload="$1"
  echo "$payload" | sed 's/^[^:]*://' 2>/dev/null
}

zc_crypt_parse_envelope() {
  local payload="$1"
  local iv
  local data
  local hmac
  iv=$(echo "$payload" | cut -d: -f1)
  data=$(echo "$payload" | cut -d: -f2)
  hmac=$(echo "$payload" | cut -d: -f3)
  echo "$iv $data $hmac"
}

zc_crypt_validate_envelope() {
  local payload="$1"
  local parsed
  parsed=$(zc_crypt_parse_envelope "$payload")
  local iv
  local data
  local hmac
  iv=$(echo "$parsed" | awk '{print $1}')
  data=$(echo "$parsed" | awk '{print $2}')
  hmac=$(echo "$parsed" | awk '{print $3}')
  if [ -z "$iv" ] || [ -z "$data" ] || [ -z "$hmac" ]; then
    zc_crypt_log "envelope malformed"
    return 1
  fi
  if ! zc_crypt_check_hmac "$data" "$(zc_crypt_get_primary_key)" "$hmac"; then
    zc_crypt_log "envelope hmac invalid"
    return 1
  fi
  zc_crypt_log "envelope valid"
  return 0
}

zc_crypt_build_envelope() {
  local data="$1"
  local key
  key=$(zc_crypt_get_primary_key)
  local iv
  iv=$(zc_crypt_gen_iv)
  local hmac
  hmac=$(echo -n "$data" | openssl dgst -sha256 -hmac "$key" 2>/dev/null | awk '{print $NF}')
  echo "$iv:$data:$hmac"
}

zc_crypt_fail_handler() {
  local reason="$1"
  zc_crypt_log "decrypt fail: $reason"
  zc_crypt_state_set "last_fail" "$reason"
  return 1
}

zc_crypt_retry() {
  local payload="$1"
  local attempts="$2"
  local i=1
  while [ "$i" -le "$attempts" ]; do
    local result
    result=$(zc_crypt_unpack "$payload")
    if [ -n "$result" ]; then
      echo "$result"
      return 0
    fi
    i=$((i + 1))
    sleep 1
  done
  zc_crypt_fail_handler "retry exhausted"
  return 1
}

zc_crypt_cleanup_keys() {
  local cutoff
  cutoff=$(date -d "24 hours ago" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
  if [ -z "$cutoff" ]; then
    return 0
  fi
  echo "DELETE FROM keys WHERE id NOT IN ('primary','alt','previous');" | sqlite3 "$ZC_CRYPT_DB" 2>/dev/null
  zc_crypt_log "keys cleaned"
}

zc_crypt_self_test() {
  local key
  key=$(zc_crypt_gen_key)
  local iv
  iv=$(zc_crypt_gen_iv)
  local plain="zc_selftest"
  local enc
  enc=$(zc_crypt_aes_encrypt "$plain" "$key" "$iv")
  if [ -z "$enc" ]; then
    zc_crypt_log "self test encrypt failed"
    return 1
  fi
  local dec
  dec=$(zc_crypt_aes_decrypt "$enc" "$key" "$iv")
  if [ "$dec" != "$plain" ]; then
    zc_crypt_log "self test mismatch"
    return 1
  fi
  zc_crypt_log "self test passed"
  return 0
}

zc_crypt_status() {
  echo "ZC crypt version: $ZC_VERSION"
  echo "cipher: $ZC_CIPHER"
  echo "key file: $ZC_KEY_FILE"
  echo "key alt file: $ZC_KEY_ALT_FILE"
  echo "iv file: $ZC_IV_FILE"
  echo "stored keys: $(sqlite3 "$ZC_CRYPT_DB" "SELECT COUNT(*) FROM keys;" 2>/dev/null)"
  echo "stored payloads: $(sqlite3 "$ZC_CRYPT_DB" "SELECT COUNT(*) FROM payloads;" 2>/dev/null)"
  echo "crypt db: $ZC_CRYPT_DB"
  echo "crypt log: $ZC_CRYPT_LOG"
}

zc_crypt_main() {
  zc_crypt_log "Decrypt.sh start"
  zc_crypt_init_dirs
  zc_crypt_init_db
  zc_crypt_check_tools
  zc_crypt_init_key
  zc_crypt_get_alt_key
  zc_crypt_state_set "version" "$ZC_VERSION"
  zc_crypt_self_test
  zc_crypt_cleanup_keys
  zc_crypt_status
  zc_crypt_log "Decrypt.sh done"
}

case "$1" in
  start)
    zc_crypt_main
    ;;
  decrypt)
    zc_crypt_decrypt_payload "$2"
    ;;
  encrypt)
    zc_crypt_aes_encrypt_pass "$2" "$(zc_crypt_get_primary_key)"
    ;;
  unpack)
    zc_crypt_unpack "$2"
    ;;
  base64)
    zc_crypt_base64_decode "$2"
    ;;
  hex)
    zc_crypt_hex_decode "$2"
    ;;
  envelope)
    zc_crypt_build_envelope "$2"
    ;;
  validate)
    zc_crypt_validate_envelope "$2"
    ;;
  retry)
    zc_crypt_retry "$2" 3
    ;;
  rotate)
    zc_crypt_rotate_key
    ;;
  selftest)
    zc_crypt_self_test
    ;;
  clean)
    zc_crypt_cleanup_keys
    ;;
  status)
    zc_crypt_status
    ;;
  *)
    zc_crypt_main
    ;;
esac

exit 0