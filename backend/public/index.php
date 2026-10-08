<?php
declare(strict_types=1);
require dirname(__DIR__) . '/src/bootstrap.php';

header('Access-Control-Allow-Origin: *');
header('Access-Control-Allow-Headers: Authorization, Content-Type, X-Platform');
if ($_SERVER['REQUEST_METHOD'] === 'OPTIONS') output(['ok' => true]);
$path = '/' . trim(parse_url($_SERVER['REQUEST_URI'], PHP_URL_PATH), '/');
$method = $_SERVER['REQUEST_METHOD'];

// The container hosts the website at / and keeps the API under /api.
if (str_starts_with($path, '/api/')) $path = substr($path, 4);

if (str_starts_with($path, '/v1/duels/')) {
    header('Cache-Control: no-store');
    require dirname(__DIR__) . '/src/duels.php';
    $user = current_user();
    try { output(duel_route($method, $path, $user)); }
    catch (DuelError $e) { fail($e->kind, $e->getMessage(), $e->status); }
    catch (Throwable $e) {
        if (db()->inTransaction()) db()->rollBack();
        error_log('Duel request failed: '.get_class($e));
        fail('server', 'Düello servisine ulaşılamadı. Yeniden dene.', 503);
    }
}

if ($path === '/health') {
    try { db()->query('SELECT 1'); output(['ok'=>true,'service'=>'sut-ve-gol','duelVersion'=>1,'time'=>gmdate('c')]); }
    catch (Throwable $e) { fail('unhealthy','Servis hazırlanıyor.',503); }
}

if ($method === 'POST' && $path === '/v1/auth/register') {
    rate_limit('register',8,300);
    $data = body(); $email = mb_strtolower(trim((string) ($data['email'] ?? ''))); $password = (string) ($data['password'] ?? ''); $username = trim((string) ($data['username'] ?? ''));
    if (!filter_var($email, FILTER_VALIDATE_EMAIL) || strlen($password) < 8) fail('invalid_signup', 'Geçerli e-posta ve en az 8 karakter parola gerekli.');
    if (!valid_username($username)) fail('invalid_username', '3–20 karakter; yalnızca harf, rakam ve alt çizgi kullan.');
    try {
        db()->beginTransaction();
        db()->prepare('INSERT INTO users(public_id,email,password_hash,username,username_key) VALUES(?,?,?,?,?)')->execute([public_id(), $email, password_hash($password, PASSWORD_DEFAULT), $username, username_key($username)]);
        $id = (int) db()->lastInsertId();
        db()->prepare('INSERT INTO identities(user_id,provider,provider_subject,email) VALUES(?,"email",?,?)')->execute([$id, $email, $email]);
        db()->commit();
    } catch (PDOException $error) {
        if (db()->inTransaction()) db()->rollBack();
        $check = db()->prepare('SELECT email,username_key FROM users WHERE email=? OR username_key=? LIMIT 1');
        $check->execute([$email, username_key($username)]); $conflict = $check->fetch();
        if ($conflict && $conflict['username_key'] === username_key($username)) fail('username_taken', 'Bu kullanıcı adı alınmış.', 409);
        fail('email_taken', 'Bu e-posta zaten kayıtlı.', 409);
    }
    $query = db()->prepare('SELECT * FROM users WHERE id=?'); $query->execute([$id]); issue_session($query->fetch());
}

if ($method === 'POST' && $path === '/v1/auth/login') {
    rate_limit('login',12,300);
    $data = body(); $query = db()->prepare('SELECT * FROM users WHERE email=? AND status="active"');
    $query->execute([mb_strtolower(trim((string) ($data['email'] ?? '')))]); $user = $query->fetch();
    if (!$user || !$user['password_hash'] || !password_verify((string) ($data['password'] ?? ''), $user['password_hash'])) fail('bad_credentials', 'E-posta veya parola hatalı.', 401);
    issue_session($user);
}

if ($method === 'POST' && $path === '/v1/auth/apple/challenge') {
    rate_limit('apple_challenge',20,300);
    $id=bin2hex(random_bytes(16)); $nonce=bin2hex(random_bytes(32));
    db()->prepare('DELETE FROM auth_challenges WHERE expires_at < NOW()')->execute();
    db()->prepare('INSERT INTO auth_challenges(id,nonce_hash,expires_at) VALUES(?,?,DATE_ADD(NOW(),INTERVAL 5 MINUTE))')->execute([$id,hash('sha256',$nonce)]);
    output(['ok'=>true,'challengeId'=>$id,'nonce'=>$nonce]);
}

if ($method === 'POST' && preg_match('#^/v1/auth/(google|apple)$#', $path, $match)) {
    rate_limit('social',20,300);
    $data = body(); $claims = identity_claims($match[1], (string) ($data['identityToken'] ?? '')); $subject = (string) ($claims['sub'] ?? '');
    if ($subject === '') fail('invalid_identity', 'Kimlik bilgisi eksik.', 401);
    if ($match[1] === 'apple') {
        $challengeId=(string)($data['challengeId']??'');
        $nonce=(string)($claims['nonce']??'');
        $consume=db()->prepare('UPDATE auth_challenges SET used_at=NOW() WHERE id=? AND nonce_hash=? AND used_at IS NULL AND expires_at>NOW()');
        $consume->execute([$challengeId,hash('sha256',$nonce)]);
        if ($nonce==='' || $consume->rowCount()!==1) fail('invalid_identity','Apple girişini yeniden başlat.',401);
    }
    $query = db()->prepare('SELECT u.* FROM users u JOIN identities i ON i.user_id=u.id WHERE i.provider=? AND i.provider_subject=?');
    $query->execute([$match[1], $subject]); $user = $query->fetch();
    if (!$user) {
        $verified = in_array($claims['email_verified'] ?? false, [true,'true',1], true);
        $email = $verified && isset($claims['email']) && filter_var($claims['email'], FILTER_VALIDATE_EMAIL) ? mb_strtolower((string)$claims['email']) : null;
        db()->beginTransaction();
        $existing = null;
        if ($email) { $find=db()->prepare('SELECT * FROM users WHERE email=?'); $find->execute([$email]); $existing=$find->fetch(); }
        if ($existing && $existing['status'] !== 'active') { db()->rollBack(); fail('account_unavailable','Hesap kullanılamıyor.',403); }
        if ($existing) $id=(int)$existing['id'];
        else { db()->prepare('INSERT INTO users(public_id,email,display_name) VALUES(?,?,?)')->execute([public_id(),$email,trim((string)($data['displayName']??''))?:null]); $id=(int)db()->lastInsertId(); }
        db()->prepare('INSERT INTO identities(user_id,provider,provider_subject,email) VALUES(?,?,?,?)')->execute([$id, $match[1], $subject, $email]);
        db()->commit(); $query = db()->prepare('SELECT * FROM users WHERE id=?'); $query->execute([$id]); $user = $query->fetch();
    }
    issue_session($user);
}

if ($method === 'POST' && $path === '/v1/auth/refresh') {
    $data = body(); $query = db()->prepare('SELECT u.* FROM refresh_tokens r JOIN users u ON u.id=r.user_id WHERE r.token_hash=? AND r.revoked_at IS NULL AND r.expires_at>NOW()');
    $query->execute([hash('sha256', (string) ($data['refreshToken'] ?? ''))]); $user = $query->fetch();
    if (!$user) fail('unauthorized', 'Oturum yenilenemedi.', 401);
    output(['ok' => true, 'accessToken' => access_token($user), 'expiresIn' => 900]);
}

if ($method === 'GET' && $path === '/v1/me') { $user = current_user(); output(['ok' => true, 'user' => public_user($user)]); }

if ($method === 'GET' && $path === '/v1/username/check') {
    rate_limit('username_check',60,60); $name = trim((string) ($_GET['username'] ?? '')); $available = false;
    if (valid_username($name)) { $query = db()->prepare('SELECT 1 FROM users WHERE username_key=?'); $query->execute([username_key($name)]); $available = !$query->fetchColumn(); }
    output(['ok' => true, 'valid' => valid_username($name), 'available' => $available]);
}

if ($method === 'PUT' && $path === '/v1/me/username') {
    $user = current_user(); $name = trim((string) (body()['username'] ?? ''));
    if (!valid_username($name)) fail('invalid_username', '3–20 karakter; yalnızca harf, rakam ve alt çizgi kullan.');
    try {
        $query = db()->prepare('UPDATE users SET username=?,username_key=? WHERE id=? AND username IS NULL');
        $query->execute([$name, username_key($name), $user['id']]);
        if (!$query->rowCount()) fail('username_locked', 'Kullanıcı adı destek üzerinden değiştirilebilir.', 409);
    } catch (PDOException $error) { fail('username_taken', 'Bu kullanıcı adı alınmış.', 409); }
    $query = db()->prepare('SELECT * FROM users WHERE id=?'); $query->execute([$user['id']]); output(['ok' => true, 'user' => public_user($query->fetch())]);
}

if ($method === 'DELETE' && $path === '/v1/me') {
    $user=current_user();
    if (in_array('apple', providers((int)$user['id']), true)) {
        $data=body(); $claims=identity_claims('apple',(string)($data['identityToken']??''));
        $q=db()->prepare('SELECT provider_subject FROM identities WHERE user_id=? AND provider="apple"'); $q->execute([$user['id']]);
        if (!hash_equals((string)$q->fetchColumn(),(string)($claims['sub']??''))) fail('apple_account','Hesabına bağlı Apple kimliğini kullan.',403);
        require dirname(__DIR__).'/src/apple.php';
        apple_revoke_code((string)($data['authorizationCode']??''),(string)$claims['sub']);
    }
    db()->beginTransaction();
    db()->prepare('DELETE FROM duel_queue WHERE user_id=?')->execute([$user['id']]);
    db()->prepare('DELETE FROM identities WHERE user_id=?')->execute([$user['id']]);
    db()->prepare('DELETE FROM refresh_tokens WHERE user_id=?')->execute([$user['id']]);
    db()->prepare('DELETE FROM daily_user_stats WHERE user_id=?')->execute([$user['id']]);
    db()->prepare('UPDATE users SET email=NULL,password_hash=NULL,username=NULL,username_key=NULL,display_name=NULL,avatar_url=NULL,public_id=?,status="deleted" WHERE id=?')->execute([public_id(),$user['id']]);
    db()->commit(); output(['ok'=>true]);
}

if ($method === 'POST' && $path === '/v1/games') {
    $user = current_user(); if (!$user['username']) fail('username_required', 'Önce kullanıcı adını belirle.', 409); $data = body();
    $id = bin2hex(random_bytes(16)); $nonce = bin2hex(random_bytes(16));
    db()->prepare('INSERT INTO game_sessions(public_id,user_id,nonce,client_version,platform) VALUES(?,?,?,?,?)')
        ->execute([$id, $user['id'], $nonce, substr((string) ($data['version'] ?? ''), 0, 24), substr($_SERVER['HTTP_X_PLATFORM'] ?? '', 0, 20)]);
    output(['ok' => true, 'sessionId' => $id, 'nonce' => $nonce, 'startedAt' => gmdate('c')], 201);
}

if ($method === 'POST' && preg_match('#^/v1/games/([a-f0-9]{32})/finish$#', $path, $match)) {
    $user = current_user(); $data = body(); $query = db()->prepare('SELECT * FROM game_sessions WHERE public_id=? AND user_id=? AND finished_at IS NULL');
    $query->execute([$match[1], $user['id']]); $game = $query->fetch(); if (!$game) fail('invalid_session', 'Oyun oturumu bulunamadı.', 404);
    $score=max(0,(int)($data['score']??0)); $shots=max(0,(int)($data['shots']??0)); $hits=max(0,(int)($data['hits']??0));
    $misses=max(0,(int)($data['misses']??0)); $feverHits=max(0,(int)($data['feverHits']??0)); $duration=max(0,(int)($data['durationMs']??0));
    $expected=($hits-$feverHits)*30+$feverHits*60; $reason=null;
    if (($data['nonce']??'') !== $game['nonce']) $reason='nonce';
    elseif ($feverHits>$hits || $hits+$misses>$shots || $expected!==$score) $reason='score_math';
    elseif ($duration<max(1000,$shots*350) || $score>100000) $reason='impossible_rate';
    $query=db()->prepare('UPDATE game_sessions SET score=?,shots=?,hits=?,misses=?,fever_hits=?,max_streak=?,duration_ms=?,stage=?,suspicious=?,reject_reason=?,finished_at=NOW() WHERE id=?');
    $query->execute([$score,$shots,$hits,$misses,$feverHits,max(0,(int)($data['maxStreak']??0)),$duration,substr((string)($data['stage']??'street'),0,20),$reason?1:0,$reason,$game['id']]);
    if (!$reason) db()->prepare('INSERT INTO daily_user_stats(stat_date,user_id,sessions,shots,hits,play_ms,best_score) VALUES(CURDATE(),?,1,?,?,?,?) ON DUPLICATE KEY UPDATE sessions=sessions+1,shots=shots+VALUES(shots),hits=hits+VALUES(hits),play_ms=play_ms+VALUES(play_ms),best_score=GREATEST(best_score,VALUES(best_score))')->execute([$user['id'],$shots,$hits,$duration,$score]);
    output(['ok'=>true,'accepted'=>$reason===null,'reason'=>$reason]);
}

if ($method === 'GET' && $path === '/v1/leaderboard') {
    $period=in_array($_GET['period']??'all',['daily','weekly','all'],true)?$_GET['period']:'all';
    $time=$period==='daily'?'AND g.finished_at>=CURDATE()':($period==='weekly'?'AND g.finished_at>=DATE_SUB(NOW(),INTERVAL 7 DAY)':'');
    $query=db()->query("SELECT u.public_id id,u.username,MAX(g.score) score,COUNT(g.id) games FROM users u JOIN game_sessions g ON g.user_id=u.id AND g.suspicious=0 AND g.finished_at IS NOT NULL $time WHERE u.status='active' AND u.username IS NOT NULL GROUP BY u.id ORDER BY score DESC,MIN(g.finished_at) ASC LIMIT 100");
    output(['ok'=>true,'period'=>$period,'entries'=>$query->fetchAll()]);
}

fail('not_found', 'Uç nokta bulunamadı.', 404);
