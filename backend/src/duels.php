<?php
declare(strict_types=1);

const DUEL_SECONDS = 90;
const DUEL_GRACE_MS = 8000;

final class DuelError extends RuntimeException {
    public function __construct(public string $kind, string $message, public int $status = 422) {
        parent::__construct($message);
    }
}

function duel_now(): int { return (int) floor(microtime(true) * 1000); }
function duel_query(string $sql, array $args = []): PDOStatement {
    $q = db()->prepare($sql); $q->execute($args); return $q;
}
function duel_transaction(callable $action): mixed {
    db()->beginTransaction();
    try { $result = $action(); db()->commit(); return $result; }
    catch (Throwable $e) { if (db()->inTransaction()) db()->rollBack(); throw $e; }
}
function duel_require(bool $condition, string $code, string $message, int $status = 422): void {
    if (!$condition) throw new DuelError($code, $message, $status);
}
function duel_integer(mixed $v, int $min, int $max, string $field): int {
    duel_require(is_int($v) && $v >= $min && $v <= $max, 'invalid_event', "$field geçersiz."); return $v;
}
function duel_number(mixed $v, float $min, float $max, string $field): float {
    duel_require((is_int($v) || is_float($v)) && is_finite((float)$v) && $v >= $min && $v <= $max, 'invalid_event', "$field geçersiz."); return (float)$v;
}
function duel_vector(mixed $v, string $field, float $limit = 12000): void {
    duel_require(is_array($v) && array_is_list($v) && count($v) === 2, 'invalid_event', "$field geçersiz.");
    foreach ($v as $n) duel_number($n, -$limit, $limit, $field);
}

/** Validates the relay protocol and score transitions; visual replay is not a ranked physics proof. */
function duel_validate_event(array $e, array $p, array $duel, int $now): void {
    duel_integer($e['v'] ?? null, 1, 1, 'v');
    $seq = duel_integer($e['seq'] ?? null, 1, 300, 'seq');
    duel_require($seq === (int)$p['shots'] + 1, 'sequence_gap', 'Şut sırası eksik; bekleyen şutları yeniden gönder.', 409);
    $t = duel_integer($e['t'] ?? null, 0, DUEL_SECONDS * 1000 - 1, 't');
    duel_require($t >= (int)$p['last_shot_ms'] + 350 && $t <= $now - (int)$duel['starts_at_ms'] + 1000, 'invalid_timing', 'Şut zamanı geçersiz.');
    $stage = (int)$p['score'] >= 1200 ? 'stadium' : ((int)$p['score'] >= 700 ? 'cage' : ((int)$p['score'] >= 300 ? 'beach' : 'street'));
    duel_require(($e['stage'] ?? null) === $stage && ($e['view'] ?? null) === 'wide', 'invalid_event', 'Saha durumu geçersiz.');
    duel_require(in_array($e['path'] ?? null, ['net','keeper','post','out'], true), 'invalid_event', 'Şut yolu geçersiz.');
    duel_require(is_bool($e['hit'] ?? null) && is_bool($e['fever'] ?? null), 'invalid_event', 'Şut sonucu geçersiz.');
    if (($e['target'] ?? null) !== null) duel_vector($e['target'], 'target');
    duel_vector($e['chord'] ?? null, 'chord', 6000);
    duel_vector($e['end'] ?? null, 'end');
    if (($e['drop'] ?? null) !== null) duel_vector($e['drop'], 'drop');
    duel_number($e['dev'] ?? null, -3000, 3000, 'dev');
    duel_number($e['tMax'] ?? null, 0, 1, 'tMax');
    duel_number($e['power'] ?? null, 0, 1, 'power');
    duel_number($e['feverLeft'] ?? null, 0, 10, 'feverLeft');
    duel_require(is_array($e['keeper'] ?? null) && count($e['keeper']) === 2 && array_is_list($e['keeper']), 'invalid_event', 'Kaleci durumu geçersiz.');
    foreach ($e['keeper'] as $n) if ($n !== null) duel_number($n, 0, 86400, 'keeper');
    foreach (['score','shots','hits','misses','feverHits','maxStreak','streak','lives'] as $name) duel_integer($e[$name] ?? null, 0, $name === 'score' ? 18000 : 300, $name);
    $hit = $e['hit'] ? 1 : 0;
    duel_require($e['shots'] === $seq && $e['hits'] === (int)$p['hits'] + $hit && $e['misses'] === (int)$p['misses'] + 1 - $hit, 'score_math', 'Şut sayacı eşleşmedi.');
    duel_require($e['lives'] === 3 - $e['misses'] && $e['lives'] >= 0, 'score_math', 'Can sayacı eşleşmedi.');
    $feverDelta = $e['feverHits'] - (int)$p['fever_hits'];
    duel_require($feverDelta >= 0 && $feverDelta <= $hit && $e['feverHits'] <= $e['hits'], 'score_math', 'Kral modu sayacı eşleşmedi.');
    duel_require($e['score'] === ($e['hits'] - $e['feverHits'])*30 + $e['feverHits']*60 && $e['score'] >= (int)$p['score'], 'score_math', 'Skor eşleşmedi.');
    duel_require($e['maxStreak'] >= (int)$p['max_streak'] && $e['maxStreak'] <= $e['hits'] && $e['streak'] <= $e['maxStreak'], 'score_math', 'Seri sayacı eşleşmedi.');
}

function duel_lock_match(string $id, int $user): array {
    $duel = duel_query('SELECT * FROM duels WHERE id=? FOR UPDATE', [$id])->fetch();
    duel_require((bool)$duel, 'not_found', 'Düello bulunamadı.', 404);
    $players = duel_query('SELECT p.*,u.public_id,u.username,u.status user_status FROM duel_players p JOIN users u ON u.id=p.user_id WHERE p.duel_id=? ORDER BY p.seat', [$id])->fetchAll();
    duel_require(count($players) === 2 && count(array_filter($players, fn($p) => (int)$p['user_id'] === $user)) === 1, 'not_found', 'Düello bulunamadı.', 404);
    return [$duel, $players];
}

function duel_resolve(array &$duel, array $players, int $now): void {
    if ($duel['status'] === 'finished') return;
    $gone = array_filter($players, fn($p) => (int)$p['forfeited'] || $p['user_status'] !== 'active');
    $both = count(array_filter($players, fn($p) => (int)$p['finished'])) === 2;
    $deadline = $now >= (int)$duel['ends_at_ms'] + DUEL_GRACE_MS;
    if (!$gone && !$both && !$deadline) return;
    $winner = null; $reason = $gone ? 'forfeit' : ($both ? 'completed' : 'time');
    $eligible = array_values(array_filter($players, fn($p) => !(int)$p['forfeited'] && $p['user_status'] === 'active'));
    if (count($eligible) === 1) $winner = (int)$eligible[0]['user_id'];
    elseif (count($eligible) === 2) {
        $a = $eligible[0]; $b = $eligible[1];
        $cmp = ((int)$a['score'] <=> (int)$b['score']) ?: ((int)$a['hits'] <=> (int)$b['hits']);
        if ($cmp !== 0) $winner = (int)($cmp > 0 ? $a['user_id'] : $b['user_id']);
    }
    duel_query('UPDATE duels SET status="finished",winner_id=?,reason=? WHERE id=?', [$winner,$reason,$duel['id']]);
    $duel['status'] = 'finished'; $duel['winner_id'] = $winner; $duel['reason'] = $reason;
}

function duel_snapshot(string $id, int $user, int $since = 0): array {
    return duel_transaction(function() use ($id,$user,$since) {
        [$d,$players] = duel_lock_match($id,$user); $now = duel_now();
        duel_query('UPDATE duel_players SET last_seen_ms=? WHERE duel_id=? AND user_id=?', [$now,$id,$user]);
        duel_resolve($d,$players,$now);
        $events = duel_query('SELECT e.payload FROM duel_events e WHERE e.duel_id=? AND e.user_id<>? AND e.seq>? ORDER BY e.seq LIMIT 300', [$id,$user,$since])->fetchAll();
        $mine = null; $out = [];
        foreach ($players as $p) {
            if ((int)$p['user_id'] === $user) $mine = $p;
            $out[] = ['id'=>$p['public_id'],'username'=>$p['username'] ?? 'Oyuncu','seat'=>(int)$p['seat'],'score'=>(int)$p['score'],'lives'=>(int)$p['lives'],'shots'=>(int)$p['shots'],'hits'=>(int)$p['hits'],'finished'=>(bool)$p['finished'],'connected'=>$p['user_status']==='active' && ($now-(int)$p['last_seen_ms'] < 15000 || (int)$p['user_id']===$user)];
        }
        $winnerId = null;
        foreach ($players as $p) if ((int)$p['user_id'] === (int)$d['winner_id']) $winnerId = $p['public_id'];
        return ['ok'=>true,'serverNowMs'=>$now,'duel'=>['id'=>$id,'seed'=>(int)$d['seed'],'nonce'=>$mine['nonce'],'status'=>$d['status']==='finished'?'finished':($now<(int)$d['starts_at_ms']?'countdown':'live'),'startsAtMs'=>(int)$d['starts_at_ms'],'endsAtMs'=>(int)$d['ends_at_ms'],'players'=>$out,'myAcceptedSeq'=>(int)$mine['shots'],'events'=>array_map(fn($e)=>json_decode($e['payload'],true),$events),'result'=>$d['status']==='finished'?['winnerId'=>$winnerId,'draw'=>$winnerId===null,'reason'=>$d['reason']]:null]];
    });
}

function duel_queue(int $user): array {
    // A named lock serializes pairing without requiring SKIP LOCKED on older MariaDB.
    $lock = 'svduel_'.substr(hash('sha256',(string)envv('DB_DSN')),0,40);
    duel_require((int)duel_query('SELECT GET_LOCK(?,3)',[$lock])->fetchColumn() === 1,'busy','Eşleşme yoğun; yeniden dene.',503);
    try {
        $id = duel_transaction(function() use ($user) {
            $now = duel_now();
            $active = duel_query('SELECT d.* FROM duels d JOIN duel_players p ON p.duel_id=d.id WHERE p.user_id=? AND d.status="active" ORDER BY d.created_at DESC LIMIT 1',[$user])->fetch();
            if ($active) {
                [$d,$players] = duel_lock_match($active['id'],$user); duel_resolve($d,$players,$now);
                if ($d['status'] !== 'finished') return $d['id'];
            }
            duel_query('DELETE FROM duel_queue WHERE last_seen_ms<?',[$now-15000]);
            duel_query('INSERT INTO duel_queue(user_id,joined_ms,last_seen_ms) VALUES(?,?,?) ON DUPLICATE KEY UPDATE last_seen_ms=VALUES(last_seen_ms)',[$user,$now,$now]);
            $other = duel_query('SELECT q.user_id FROM duel_queue q JOIN users u ON u.id=q.user_id WHERE q.user_id<>? AND u.status="active" AND u.username IS NOT NULL ORDER BY q.joined_ms,q.user_id LIMIT 1 FOR UPDATE',[$user])->fetchColumn();
            if (!$other) return null;
            $id = bin2hex(random_bytes(16)); $start = $now + 6000;
            duel_query('INSERT INTO duels(id,seed,starts_at_ms,ends_at_ms) VALUES(?,?,?,?)',[$id,random_int(1,2147483647),$start,$start+DUEL_SECONDS*1000]);
            foreach ([(int)$other,$user] as $seat=>$player) duel_query('INSERT INTO duel_players(duel_id,user_id,seat,nonce,last_seen_ms) VALUES(?,?,?,?,?)',[$id,$player,$seat,bin2hex(random_bytes(16)),$now]);
            duel_query('DELETE FROM duel_queue WHERE user_id IN (?,?)',[$user,$other]);
            return $id;
        });
    } finally { duel_query('SELECT RELEASE_LOCK(?)',[$lock]); }
    return $id ? duel_snapshot($id,$user) : ['ok'=>true,'status'=>'waiting','serverNowMs'=>duel_now()];
}

function duel_route(string $method, string $path, array $user): array {
    $uid = (int)$user['id'];
    duel_require((bool)$user['username'], 'username_required','Önce kullanıcı adını belirle.',409);
    if ($path === '/v1/duels/queue') {
        if ($method === 'GET' || $method === 'POST') return duel_queue($uid);
        if ($method === 'DELETE') {
            duel_query('DELETE FROM duel_queue WHERE user_id=?',[$uid]);
            $id = duel_query('SELECT d.id FROM duels d JOIN duel_players p ON p.duel_id=d.id WHERE p.user_id=? AND d.status="active" LIMIT 1',[$uid])->fetchColumn();
            // Cancellation racing a match is a forfeit, never leaves a stranded opponent.
            if ($id) return duel_forfeit((string)$id,$uid);
            return ['ok'=>true,'status'=>'left','serverNowMs'=>duel_now()];
        }
    }
    duel_require((bool)preg_match('#^/v1/duels/([a-f0-9]{32})(?:/(events|finish|forfeit))?$#',$path,$m),'not_found','Uç nokta bulunamadı.',404);
    $id=$m[1]; $action=$m[2]??'';
    if ($method==='GET' && $action==='') return duel_snapshot($id,$uid,max(0,min(300,(int)($_GET['since']??0))));
    if ($method==='POST' && $action==='forfeit') return duel_forfeit($id,$uid);
    duel_require($method==='POST' && in_array($action,['events','finish'],true),'not_found','Uç nokta bulunamadı.',404);
    $data=body();
    duel_transaction(function() use ($id,$uid,$action,$data) {
        [$d,$players]=duel_lock_match($id,$uid); $now=duel_now();
        $p=array_values(array_filter($players,fn($p)=>(int)$p['user_id']===$uid))[0];
        duel_require(is_string($data['nonce']??null) && hash_equals($p['nonce'],$data['nonce']),'invalid_nonce','Düello kimliği eşleşmedi.',403);
        if ($d['status']==='finished') return;
        duel_require($now>=(int)$d['starts_at_ms'],'not_started','Düello henüz başlamadı.',409);
        duel_require($now<=(int)$d['ends_at_ms']+DUEL_GRACE_MS,'match_expired','Düello süresi doldu.',409);
        if ($action==='events') {
            $events=$data['events']??null;
            duel_require(is_array($events) && array_is_list($events) && count($events)>0 && count($events)<=30,'invalid_event','Şut paketi geçersiz.');
            foreach ($events as $e) {
                duel_require(is_array($e),'invalid_event','Şut kaydı geçersiz.');
                $seq=duel_integer($e['seq']??null,1,300,'seq'); $payload=json_encode($e,JSON_UNESCAPED_UNICODE|JSON_UNESCAPED_SLASHES|JSON_THROW_ON_ERROR); $hash=hash('sha256',$payload);
                duel_require(strlen($payload)<=4096,'invalid_event','Şut kaydı çok büyük.');
                if ($seq<=(int)$p['shots']) {
                    $old=duel_query('SELECT payload_hash FROM duel_events WHERE duel_id=? AND user_id=? AND seq=?',[$id,$uid,$seq])->fetchColumn();
                    duel_require($old && hash_equals((string)$old,$hash),'event_conflict','Bu şut daha önce farklı kaydedilmiş.',409); continue;
                }
                duel_require(!(int)$p['finished'],'already_finished','Koşu tamamlandı.',409);
                duel_validate_event($e,$p,$d,$now);
                duel_query('INSERT INTO duel_events(duel_id,user_id,seq,payload,payload_hash) VALUES(?,?,?,?,?)',[$id,$uid,$seq,$payload,$hash]);
                foreach (['score','lives','shots','hits','misses'] as $key) $p[$key]=$e[$key];
                $p['fever_hits']=$e['feverHits']; $p['max_streak']=$e['maxStreak']; $p['last_shot_ms']=$e['t'];
                duel_query('UPDATE duel_players SET score=?,lives=?,shots=?,hits=?,misses=?,fever_hits=?,max_streak=?,last_shot_ms=?,last_seen_ms=?,finished=? WHERE duel_id=? AND user_id=?',[$p['score'],$p['lives'],$p['shots'],$p['hits'],$p['misses'],$p['fever_hits'],$p['max_streak'],$p['last_shot_ms'],$now,$p['lives']===0?1:0,$id,$uid]);
                if ($p['lives']===0) $p['finished']=1;
            }
        } else {
            // The persisted event stream is the result; never accept a client supplied summary.
            duel_query('UPDATE duel_players SET finished=1,last_seen_ms=? WHERE duel_id=? AND user_id=?',[$now,$id,$uid]);
        }
    });
    return duel_snapshot($id,$uid,max(0,min(300,(int)($data['since']??0))));
}

function duel_forfeit(string $id,int $user): array {
    duel_transaction(function() use ($id,$user) {
        [$d,$players]=duel_lock_match($id,$user);
        if ($d['status']==='finished') return;
        duel_query('UPDATE duel_players SET forfeited=1,finished=1 WHERE duel_id=? AND user_id=?',[$id,$user]);
        foreach ($players as &$p) if ((int)$p['user_id']===$user) { $p['forfeited']=1; $p['finished']=1; }
        unset($p); duel_resolve($d,$players,duel_now());
    });
    return duel_snapshot($id,$user);
}
