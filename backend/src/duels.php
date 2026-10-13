<?php
declare(strict_types=1);
require_once __DIR__ . '/moderation.php';

/*
 * Düello v2 (hibrit): 90 sn ortak kronometreyle eşzamanlı canlı yarış. Can yok; ıskalama
 * yalnız combo'yu sıfırlar. Şut başına 5 sn şut saati; dolarsa istemci "timeout" ıskası
 * gönderir. Gol 30 puan × combo çarpanı (x1→x2→x3, tavan 3); Kral Modu'nda çarpan sabit x2.
 * Kuyrukta 15 sn canlı rakip yoksa gerçek bir oyuncunun bitmiş koşusuna (ghost, "Kayıtlı
 * rakip") karşı oynanır; havuz boşsa açıkça etiketli CPU koşusu üretilir. Canlı maçlar
 * Glicko-2 rating'e sayılır, ghost maçları yalnız XP verir.
 *
 * Zaman alanları (koşu başından ms, istemcinin oyun saati): `t` vuruş (ya da şut saati
 * ıskası) anı, `rt` sonucun skora işlendiği an (top fileye/yere düşüp sayıldığında). Kral
 * Modu kararları istemcideki gibi `rt` ile verilir; şut saati bir önceki şutun `rt`'sinden
 * ölçülür. Böylece direk sekmesi gibi uzun sonuçlanmalar dürüst oyuncuyu reddettirmez.
 */

const DUEL_VERSION = 2;
const DUEL_SECONDS = 90;
const DUEL_GRACE_MS = 8000;
const DUEL_COUNTDOWN_MS = 6000;
const DUEL_SHOT_CLOCK_MS = 5000;
/** Önceki şutun sonuçlanmasından (rt) yeni topun hazır olmasına kadar pay (yeni top 0,7 sn). */
const DUEL_CYCLE_TOLERANCE_MS = 5000;
/** Sahne geçişinde (arka plan üretimi + 1,2 sn afiş) şut saati sınırına eklenen pay. */
const DUEL_STAGE_TOLERANCE_MS = 4000;
/** Vuruştan sonucun işlenmesine kadar en uzun süre (uçuş ≤0,68 + direk düşüşü + 0,45 sn). */
const DUEL_RESOLVE_MAX_MS = 5000;
/** Bir şut sunucuya en geç bu kadar eski bir `t` ile ulaşabilir (geriye dönük koşu üretimi yok). */
const DUEL_MAX_LAG_MS = 12000;
/** Makullük tavanı: n. şut t ≥ (n-1) × 1,5 sn (dürüst en hızlı döngü ≈ 1,7 sn). */
const DUEL_SHOT_RATE_MS = 1500;
const DUEL_MIN_GAP_MS = 350;
const DUEL_GOAL_POINTS = 30;
const DUEL_MAX_MULT = 3;
const DUEL_FEVER_MULT = 2;
const DUEL_FEVER_STREAK = 5;
const DUEL_FEVER_MS = 10000;
/** Kral Modu `rt` (sonuçlanma anı) ile işler; yalnız ms yuvarlaması / kare adımı payı. */
const DUEL_FEVER_TOLERANCE_MS = 100;
const DUEL_GHOST_AFTER_MS = 15000;
const DUEL_REMATCH_MS = 10000;
const DUEL_STALE_MS = 15000;
const DUEL_FORFEIT_MS = 30000;
const DUEL_RATING_BAND = 200;
const DUEL_CALIBRATION_GAMES = 10;
const DUEL_GHOST_ID = 'ghost';
const DUEL_UPDATE_MESSAGE = 'Düello yenilendi. Oynamak için uygulamayı güncelle.';

final class DuelError extends RuntimeException {
    /** @param array $extra hata gövdesine eklenen alanlar (ör. reddedilen `seq`, `acceptedSeq`). */
    public function __construct(public string $kind, string $message, public int $status = 422, public array $extra = []) {
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

function duel_stage_for(int $score): string {
    return $score >= 1200 ? 'stadium' : ($score >= 700 ? 'cage' : ($score >= 300 ? 'beach' : 'street'));
}

function duel_initial_state(): array {
    return ['score'=>0,'shots'=>0,'hits'=>0,'misses'=>0,'streak'=>0,'max_streak'=>0,'fever'=>0,'fever_t'=>0,'fever_hits'=>0];
}

/**
 * Bir olaydan sonra geçerli olabilecek durumlar (saf fonksiyon). `$rt` sonucun işlendiği an;
 * Kral Modu da bu anda başlar/biter. Sınırın ±100 ms içindeki golde iki sonuç da (x2 sürüyor /
 * bitti, seri sıfır) geçerlidir.
 */
function duel_candidates(array $s, bool $hit, int $rt): array {
    $t = $rt;
    $n = $s; $n['shots'] = (int)$s['shots'] + 1;
    if (!$hit) {
        $n['misses'] = (int)$s['misses'] + 1;
        $n['streak'] = 0; $n['fever'] = 0; $n['fever_t'] = 0; $n['mult'] = 0;
        return [$n];
    }
    $n['hits'] = (int)$s['hits'] + 1;
    $fever = (bool)(int)$s['fever']; $feverT = (int)$s['fever_t'];
    $out = [];
    if ($fever && $t <= $feverT + DUEL_FEVER_MS + DUEL_FEVER_TOLERANCE_MS) {
        $a = $n;
        $a['mult'] = DUEL_FEVER_MULT; $a['streak'] = (int)$s['streak'] + 1;
        $a['fever'] = 1; $a['fever_t'] = $feverT; $a['fever_hits'] = (int)$s['fever_hits'] + 1;
        $a['score'] = (int)$s['score'] + DUEL_GOAL_POINTS * DUEL_FEVER_MULT;
        $a['max_streak'] = max((int)$s['max_streak'], $a['streak']);
        $out[] = $a;
    }
    if (!$fever || $t >= $feverT + DUEL_FEVER_MS - DUEL_FEVER_TOLERANCE_MS) {
        $b = $n;
        $b['streak'] = ($fever ? 0 : (int)$s['streak']) + 1;
        $b['mult'] = min(DUEL_MAX_MULT, $b['streak']);
        $b['score'] = (int)$s['score'] + DUEL_GOAL_POINTS * $b['mult'];
        $b['fever'] = $b['streak'] >= DUEL_FEVER_STREAK ? 1 : 0;
        $b['fever_t'] = $b['fever'] ? $t : 0;
        $b['max_streak'] = max((int)$s['max_streak'], $b['streak']);
        $out[] = $b;
    }
    return $out;
}

/**
 * Şema, sıra, zaman, şut saati ve skor/combo geçişini doğrular; kalıcı yazılacak yeni durumu döner.
 * `$p`: oyuncunun kayıtlı durumu; isteğe bağlı `last_rt_ms`, `last_path`, `last_stage` son olaydan.
 * `$elapsedNow`: sunucu saatine göre maç başından geçen ms.
 */
function duel_validate_event(array $e, array $p, int $elapsedNow): array {
    duel_require(($e['v'] ?? null) === DUEL_VERSION, 'update_required', DUEL_UPDATE_MESSAGE, 426);
    $seq = duel_integer($e['seq'] ?? null, 1, 300, 'seq');
    duel_require($seq === (int)$p['shots'] + 1, 'sequence_gap', 'Şut sırası eksik; bekleyen şutları yeniden gönder.', 409);
    $t = duel_integer($e['t'] ?? null, 0, DUEL_SECONDS * 1000 - 1, 't');
    $rt = duel_integer($e['rt'] ?? null, $t, $t + DUEL_RESOLVE_MAX_MS, 'rt');
    $first = (int)$p['shots'] === 0;
    $lastRt = $first ? 0 : (int)($p['last_rt_ms'] ?? $p['last_shot_ms']);
    $lastPath = $first ? null : ($p['last_path'] ?? null);
    $path = $e['path'] ?? null;
    duel_require(in_array($path, ['net','keeper','post','out','timeout'], true), 'invalid_event', 'Şut yolu geçersiz.');
    duel_require($t <= $elapsedNow + 1000 && $rt <= $elapsedNow + 1000, 'invalid_timing', 'Şut zamanı geçersiz.');
    // Alt sınır: olay geç ulaşabilir (ağ, toplu gönderim) ama geriye dönük koşu yazılamaz.
    duel_require($t >= $elapsedNow - DUEL_MAX_LAG_MS, 'invalid_timing', 'Şut sunucuya çok geç ulaştı.');
    // Yeni vuruş önceki sonuç işlendikten sonra (yeni top ≥0,6 sn); şut saati ıskasının ardından top zaten hazırdır.
    duel_require($t >= $lastRt + ($first || $lastPath === 'timeout' ? 0 : DUEL_MIN_GAP_MS), 'invalid_timing', 'Şut zamanı geçersiz.');
    duel_require($seq <= intdiv($t, DUEL_SHOT_RATE_MS) + 1, 'invalid_timing', 'Süreye göre çok fazla şut.');
    duel_require(is_bool($e['hit'] ?? null) && is_bool($e['fever'] ?? null), 'invalid_event', 'Şut sonucu geçersiz.');
    $stage = duel_stage_for((int)$p['score']);
    if ($path === 'timeout') {
        // Iskalama cezadır; uzun boşluk (arka plan, yeniden hizalama) sonrası tek timeout kabul edilir.
        duel_require($e['hit'] === false && $t - $lastRt >= DUEL_SHOT_CLOCK_MS - 300, 'shot_clock', 'Şut saati dolmadan süre ıskası gönderildi.');
    } else {
        $stageChanged = !$first && ($p['last_stage'] ?? $stage) !== $stage;
        $limit = DUEL_SHOT_CLOCK_MS + DUEL_CYCLE_TOLERANCE_MS + ($stageChanged ? DUEL_STAGE_TOLERANCE_MS : 0);
        duel_require($t - $lastRt <= $limit, 'shot_clock', 'Şut saati aşıldı.');
    }
    duel_require(!($e['hit'] && $path === 'out'), 'score_math', 'Auta giden şut gol olamaz.');
    duel_require(($e['stage'] ?? null) === $stage && ($e['view'] ?? null) === 'wide', 'invalid_event', 'Saha durumu geçersiz.');
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
    foreach (['score','shots','hits','misses','feverHits','maxStreak','streak','mult'] as $name) {
        duel_integer($e[$name] ?? null, 0, $name === 'score' ? 60000 : ($name === 'mult' ? DUEL_MAX_MULT : 300), $name);
    }
    duel_require($e['shots'] === $seq, 'score_math', 'Şut sayacı eşleşmedi.');
    foreach (duel_candidates($p, $e['hit'], $rt) as $c) {
        if ($e['score'] === $c['score'] && $e['hits'] === $c['hits'] && $e['misses'] === $c['misses']
            && $e['streak'] === $c['streak'] && $e['maxStreak'] === $c['max_streak'] && $e['feverHits'] === $c['fever_hits']
            && $e['mult'] === $c['mult'] && $e['fever'] === (bool)$c['fever']) {
            $c['last_shot_ms'] = $t;
            $c['last_rt_ms'] = $rt; $c['last_path'] = $path; $c['last_stage'] = $stage;
            return $c;
        }
    }
    throw new DuelError('score_math', 'Skor veya combo eşleşmedi.');
}

/** Oyuncunun `seq` numaralı kayıtlı olayı (yoksa null). */
function duel_event_payload(string $id, int $user, int $seq): ?array {
    if ($seq < 1) return null;
    $raw = duel_query('SELECT payload FROM duel_events WHERE duel_id=? AND user_id=? AND seq=?', [$id, $user, $seq])->fetchColumn();
    $e = $raw === false ? null : json_decode((string)$raw, true);
    return is_array($e) ? $e : null;
}

/** Doğrulamanın ihtiyaç duyduğu son olay bilgisi (rt, yol, sahne). */
function duel_with_last_event(array $p, ?array $last): array {
    if ($last) {
        $p['last_rt_ms'] = is_int($last['rt'] ?? null) ? $last['rt'] : (int)$p['last_shot_ms'];
        $p['last_path'] = $last['path'] ?? null;
        $p['last_stage'] = $last['stage'] ?? null;
    }
    return $p;
}

/** Kayıtlı koşunun belirli bir andaki (ms) durumu. */
function duel_ghost_progress(array $events, int $elapsed): array {
    $s = ['score'=>0,'hits'=>0,'shots'=>0,'streak'=>0,'max_streak'=>0];
    foreach ($events as $e) {
        if ((int)$e['t'] > $elapsed) break;
        $s = ['score'=>(int)$e['score'],'hits'=>(int)$e['hits'],'shots'=>(int)$e['shots'],'streak'=>(int)$e['streak'],'max_streak'=>(int)$e['maxStreak']];
    }
    return $s;
}

/** Kayıtlı oyuncu havuzu boşken (ilk günler) üretilen, açıkça "CPU" etiketli deterministik koşu. */
function duel_cpu_run(int $seed): array {
    $x = $seed & 0x7fffffff ?: 1;
    $rand = function () use (&$x): float { $x = ($x * 1103515245 + 12345) & 0x7fffffff; return $x / 0x7fffffff; };
    $state = duel_initial_state(); $events = []; $t = 0; $seq = 0;
    // kWide: top 665,2323; kale çizgisi 1636; kale yüksekliği 346; topun kale ölçeği 0.20.
    $trackEndY = 1636 - 108 * 0.20;
    while (true) {
        $t += 1600 + (int)($rand() * 2600);
        if ($t >= DUEL_SECONDS * 1000 - 1500) break;
        $hit = $rand() < 0.62;
        $rt = $t + 1000;
        $cands = duel_candidates($state, $hit, $rt);
        $next = (count($cands) > 1 && $rt >= (int)$state['fever_t'] + DUEL_FEVER_MS) ? $cands[1] : $cands[0];
        $tx = 480 + $rand() * 380; $ty = 1370 + $rand() * 190;
        $aim = $hit ? [$tx, $ty] : [$rand() < .5 ? 300.0 : 1030.0, 1576.0];
        $events[] = [
            'v'=>DUEL_VERSION,'seq'=>++$seq,'t'=>$t,'rt'=>$rt,'stage'=>duel_stage_for((int)$state['score']),'view'=>'wide',
            'target'=>[round($tx, 2), round($ty, 2)],
            'chord'=>[round(($aim[0] - 665) * 0.4, 2), round(($trackEndY - 2323) * 0.4, 2)],
            'dev'=>0,'tMax'=>0.5,'power'=>round(max(0.0, min(1.0, ($trackEndY - $aim[1]) / (346 * 1.15))), 3),
            'keeper'=>[null, null],'path'=>$hit ? 'net' : 'out','hit'=>$hit,
            'end'=>[round($aim[0], 2), round($aim[1], 2)],'drop'=>null,
            'score'=>$next['score'],'streak'=>$next['streak'],'fever'=>(bool)$next['fever'],
            'feverLeft'=>$next['fever'] ? round(max(0, min(10, ((int)$next['fever_t'] + DUEL_FEVER_MS - $rt) / 1000)), 2) : 0,
            'shots'=>$next['shots'],'hits'=>$next['hits'],'misses'=>$next['misses'],
            'feverHits'=>$next['fever_hits'],'maxStreak'=>$next['max_streak'],'mult'=>$next['mult'],
        ];
        $state = $next;
    }
    return $events;
}

/**
 * Ghost kaynağı: başka bir oyuncunun bitmiş, hükmen olmayan, tam süreli gerçek v2 koşusu (maç
 * süre/tamamlanma ile bitti ya da son şutu ≥ 60. sn; rakip erken çekildiyse yarım koşu seçilmez).
 * Benzer rating ve yakın tarih öne alınır; en iyi 5 adaydan biri rastgele seçilir. Kendi koşusu asla.
 */
function duel_pick_ghost_source(int $user, float $rating): ?array {
    // İki yönlü engel: engellediği ya da onu engelleyen oyuncunun koşusu kayıtlı rakip olmaz.
    $rows = duel_query('SELECT p.duel_id,p.user_id FROM duel_players p JOIN duels d ON d.id=p.duel_id JOIN users u ON u.id=p.user_id LEFT JOIN duel_ratings r ON r.user_id=p.user_id
        WHERE d.version>=2 AND d.status="finished" AND d.created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY) AND p.user_id<>? AND p.forfeited=0 AND p.shots>=3
          AND (d.reason IN ("completed","time") OR p.last_shot_ms>=60000)
          AND u.status="active" AND u.username IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=p.user_id) OR (b.blocker_id=p.user_id AND b.blocked_id=?))
        ORDER BY ABS(COALESCE(r.rating,1500)-?) + TIMESTAMPDIFF(HOUR,d.created_at,NOW())*2, d.created_at DESC LIMIT 5', [$user, $user, $user, $rating])->fetchAll();
    shuffle($rows);
    foreach ($rows as $row) {
        $events = [];
        foreach (duel_query('SELECT payload FROM duel_events WHERE duel_id=? AND user_id=? ORDER BY seq', [$row['duel_id'], $row['user_id']])->fetchAll() as $r) {
            $e = json_decode($r['payload'], true);
            if (!is_array($e) || ($e['v'] ?? null) !== DUEL_VERSION || ($events && (int)$e['t'] < (int)end($events)['t'])) { $events = []; break; }
            $events[] = $e;
        }
        if (count($events) >= 3) return ['duel_id'=>$row['duel_id'], 'user_id'=>(int)$row['user_id'], 'events'=>$events];
    }
    return null;
}

function duel_rating_row(int $user): array {
    $r = duel_query('SELECT * FROM duel_ratings WHERE user_id=?', [$user])->fetch();
    return $r ?: ['rating'=>1500.0,'rd'=>350.0,'vol'=>0.06,'games'=>0,'wins'=>0,'losses'=>0,'draws'=>0,'xp'=>0];
}

/** Eşleşme bandı: ±200, her 5 sn beklemede genişler, 10 sn sonra sınırsız; havuz küçükse iki katı. */
function duel_band(int $waitMs, int $pool): float {
    if ($waitMs >= 10000) return INF;
    $band = DUEL_RATING_BAND * (1 + intdiv(max(0, $waitMs), 5000));
    return $pool <= 2 ? $band * 2 : (float)$band;
}

/** Tek maçlık Glicko-2 güncellemesi (Glickman 2012). $a,$b: [rating, rd, vol]; $score: 1/0.5/0. */
function duel_glicko(array $a, array $b, float $score, float $tau = 0.5): array {
    $k = 173.7178;
    $mu = ($a[0] - 1500) / $k; $phi = $a[1] / $k; $sigma = $a[2];
    $muJ = ($b[0] - 1500) / $k; $phiJ = $b[1] / $k;
    $g = 1 / sqrt(1 + 3 * $phiJ * $phiJ / (M_PI * M_PI));
    $E = 1 / (1 + exp(-$g * ($mu - $muJ)));
    $v = 1 / ($g * $g * $E * (1 - $E));
    $delta = $v * $g * ($score - $E);
    $aLn = log($sigma * $sigma);
    $f = function (float $x) use ($delta, $phi, $v, $aLn, $tau): float {
        $ex = exp($x);
        return $ex * ($delta * $delta - $phi * $phi - $v - $ex) / (2 * ($phi * $phi + $v + $ex) ** 2) - ($x - $aLn) / ($tau * $tau);
    };
    $A = $aLn;
    if ($delta * $delta > $phi * $phi + $v) { $B = log($delta * $delta - $phi * $phi - $v); }
    else { $i = 1; while ($f($aLn - $i * $tau) < 0 && $i < 100) $i++; $B = $aLn - $i * $tau; }
    $fA = $f($A); $fB = $f($B);
    for ($i = 0; abs($B - $A) > 1e-6 && $i < 100; $i++) {
        $C = $A + ($A - $B) * $fA / ($fB - $fA); $fC = $f($C);
        if ($fC * $fB <= 0) { $A = $B; $fA = $fB; } else { $fA /= 2; }
        $B = $C; $fB = $fC;
    }
    $sigmaNew = exp($A / 2);
    $phiStar = sqrt($phi * $phi + $sigmaNew * $sigmaNew);
    $phiNew = 1 / sqrt(1 / ($phiStar * $phiStar) + 1 / $v);
    $muNew = $mu + $phiNew * $phiNew * $g * ($score - $E);
    return [$k * $muNew + 1500, max(30.0, min(350.0, $k * $phiNew)), $sigmaNew];
}

function duel_xp(array $p, bool $won, bool $draw): int {
    if ((int)$p['forfeited']) return 0;
    return 10 + 2 * (int)$p['hits'] + ($won ? 25 : ($draw ? 10 : 0));
}

function duel_lock_match(string $id, int $user): array {
    $duel = duel_query('SELECT * FROM duels WHERE id=? FOR UPDATE', [$id])->fetch();
    duel_require((bool)$duel, 'not_found', 'Düello bulunamadı.', 404);
    $players = duel_query('SELECT p.*,u.public_id,u.username,u.status user_status FROM duel_players p JOIN users u ON u.id=p.user_id WHERE p.duel_id=? ORDER BY p.seat', [$id])->fetchAll();
    $expected = $duel['kind'] === 'ghost' ? 1 : 2;
    duel_require(count($players) === $expected && count(array_filter($players, fn($p) => (int)$p['user_id'] === $user)) === 1, 'not_found', 'Düello bulunamadı.', 404);
    return [$duel, $players];
}

/**
 * XP her maçta; rating yalnız iki tarafın da gerçek olduğu canlı maçta, en az biri hükmen değilse ve
 * iki taraf da en az bir şut kaydettiyse (geri sayımda / şut atmadan çekilme rating'li galibiyet vermez).
 */
function duel_apply_rewards(array $duel, array &$players, ?int $winner, bool $draw): void {
    $ids = array_map(fn($p) => (int)$p['user_id'], $players); sort($ids);
    $rows = [];
    foreach ($ids as $uid) {
        duel_query('INSERT IGNORE INTO duel_ratings(user_id) VALUES(?)', [$uid]);
        $rows[$uid] = duel_query('SELECT * FROM duel_ratings WHERE user_id=? FOR UPDATE', [$uid])->fetch();
    }
    $counted = $duel['kind'] === 'live' && count($players) === 2
        && count(array_filter($players, fn($p) => !(int)$p['forfeited'])) > 0
        && count(array_filter($players, fn($p) => (int)$p['shots'] > 0)) === 2;
    $next = [];
    foreach ($players as $p) {
        $uid = (int)$p['user_id']; $won = $winner === $uid;
        $next[$uid] = null;
        if ($counted) {
            $opp = $rows[(int)array_values(array_filter($players, fn($q) => (int)$q['user_id'] !== $uid))[0]['user_id']];
            $me = $rows[$uid];
            $next[$uid] = duel_glicko([(float)$me['rating'], (float)$me['rd'], (float)$me['vol']], [(float)$opp['rating'], (float)$opp['rd'], (float)$opp['vol']], $won ? 1.0 : ($draw ? 0.5 : 0.0));
        }
    }
    foreach ($players as &$p) {
        $uid = (int)$p['user_id']; $won = $winner === $uid; $xp = duel_xp($p, $won, $draw); $r = $rows[$uid];
        if ($next[$uid]) {
            [$rating, $rd, $vol] = $next[$uid];
            duel_query('UPDATE duel_ratings SET rating=?,rd=?,vol=?,games=games+1,wins=wins+?,losses=losses+?,draws=draws+?,xp=xp+? WHERE user_id=?',
                [$rating, $rd, $vol, $won ? 1 : 0, (!$won && !$draw) ? 1 : 0, $draw ? 1 : 0, $xp, $uid]);
            $before = (int)round((float)$r['rating']); $after = (int)round($rating);
        } else {
            duel_query('UPDATE duel_ratings SET xp=xp+? WHERE user_id=?', [$xp, $uid]);
            $before = null; $after = null;
        }
        duel_query('UPDATE duel_players SET xp_gain=?,rating_before=?,rating_after=? WHERE duel_id=? AND user_id=?', [$xp, $before, $after, $duel['id'], $uid]);
        $p['xp_gain'] = $xp; $p['rating_before'] = $before; $p['rating_after'] = $after;
    }
    unset($p);
}

function duel_resolve(array &$duel, array &$players, int $now): void {
    if ($duel['status'] === 'finished') return;
    $v2 = (int)($duel['version'] ?? 1) >= 2;
    $starts = (int)$duel['starts_at_ms'];
    $deadline = $now >= (int)$duel['ends_at_ms'] + DUEL_GRACE_MS;
    // 30 sn hiç yoklama yapmayan oyuncu hükmen kaybeder (arka plana almak süreyi durdurmaz).
    if ($v2 && !$deadline && $now >= $starts) {
        foreach ($players as &$p) {
            if ((int)$p['finished'] || (int)$p['forfeited']) continue;
            if ($now - max((int)$p['last_seen_ms'], $starts) >= DUEL_FORFEIT_MS) {
                duel_query('UPDATE duel_players SET forfeited=1,finished=1,disconnected=1 WHERE duel_id=? AND user_id=?', [$duel['id'], $p['user_id']]);
                $p['forfeited'] = 1; $p['finished'] = 1; $p['disconnected'] = 1;
            }
        }
        unset($p);
    }
    $ghost = ($duel['kind'] ?? 'live') === 'ghost';
    $gone = array_values(array_filter($players, fn($p) => (int)$p['forfeited'] || $p['user_status'] !== 'active'));
    $allDone = count(array_filter($players, fn($p) => (int)$p['finished'])) === count($players);
    if (!$gone && !$allDone && !$deadline) return;
    $reason = $gone ? (count(array_filter($gone, fn($p) => (int)($p['disconnected'] ?? 0))) ? 'disconnect' : 'forfeit') : ($allDone ? 'completed' : 'time');
    $eligible = array_values(array_filter($players, fn($p) => !(int)$p['forfeited'] && $p['user_status'] === 'active'));
    $winner = null; $draw = false;
    if ($ghost) {
        if ($eligible) {
            $h = $eligible[0];
            $cmp = ((int)$h['score'] <=> (int)$duel['ghost_score']) ?: ((int)$h['hits'] <=> (int)$duel['ghost_hits']);
            if ($cmp > 0) $winner = (int)$h['user_id']; elseif ($cmp === 0) $draw = true;
        }
    } elseif (count($eligible) === 1) {
        $winner = (int)$eligible[0]['user_id'];
    } elseif (count($eligible) === 2) {
        [$a, $b] = $eligible;
        $cmp = ((int)$a['score'] <=> (int)$b['score']) ?: ((int)$a['hits'] <=> (int)$b['hits']);
        if ($cmp !== 0) $winner = (int)($cmp > 0 ? $a['user_id'] : $b['user_id']); else $draw = true;
    } else {
        $draw = true;
    }
    if (!$v2) {
        duel_query('UPDATE duels SET status="finished",winner_id=?,reason=? WHERE id=?', [$winner, $reason, $duel['id']]);
    } else {
        duel_query('UPDATE duels SET status="finished",winner_id=?,reason=?,draw=?,finished_at_ms=? WHERE id=?', [$winner, $reason, $draw ? 1 : 0, $now, $duel['id']]);
        duel_apply_rewards($duel, $players, $winner, $draw);
        $duel['draw'] = $draw ? 1 : 0; $duel['finished_at_ms'] = $now;
    }
    $duel['status'] = 'finished'; $duel['winner_id'] = $winner; $duel['reason'] = $reason;
}

function duel_snapshot(string $id, int $user, int $since = 0, bool $withGhost = false): array {
    return duel_transaction(function () use ($id, $user, $since, $withGhost) {
        [$d, $players] = duel_lock_match($id, $user); $now = duel_now();
        duel_query('UPDATE duel_players SET last_seen_ms=? WHERE duel_id=? AND user_id=?', [$now, $id, $user]);
        foreach ($players as &$p) if ((int)$p['user_id'] === $user) $p['last_seen_ms'] = $now;
        unset($p);
        duel_resolve($d, $players, $now);
        $finished = $d['status'] === 'finished';
        $ghost = ($d['kind'] ?? 'live') === 'ghost';
        $starts = (int)$d['starts_at_ms'];
        $events = $ghost ? [] : duel_query('SELECT e.payload FROM duel_events e WHERE e.duel_id=? AND e.user_id<>? AND e.seq>? ORDER BY e.seq LIMIT 300', [$id, $user, $since])->fetchAll();
        $ratings = [];
        foreach ($players as $p) $ratings[(int)$p['user_id']] = duel_rating_row((int)$p['user_id']);
        // Rakip adı izleyiciye göre: engellediyse "Engellenen oyuncu", 3 şikâyet / uygunsuz ad "Oyuncu#XXXX".
        $owner = $ghost && $d['ghost_source'] !== 'cpu' && $d['ghost_user_id'] !== null
            ? (duel_query('SELECT id,public_id,username FROM users WHERE id=? AND status="active"', [(int)$d['ghost_user_id']])->fetch() ?: null) : null;
        $nameRows = array_map(fn($p) => ['id'=>(int)$p['user_id'], 'public_id'=>$p['public_id'], 'username'=>$p['username']], $players);
        if ($owner) $nameRows[] = ['id'=>(int)$owner['id'], 'public_id'=>$owner['public_id'], 'username'=>$owner['username']];
        $names = mod_public_names($user, $nameRows);
        $mine = null; $other = null; $out = [];
        foreach ($players as $p) {
            $isMe = (int)$p['user_id'] === $user;
            if ($isMe) $mine = $p; else $other = $p;
            $r = $ratings[(int)$p['user_id']];
            $out[] = ['id'=>$p['public_id'],'username'=>$names[(int)$p['user_id']]['name'],'blocked'=>$names[(int)$p['user_id']]['blocked'],'seat'=>(int)$p['seat'],'score'=>(int)$p['score'],'lives'=>(int)$p['lives'],
                'shots'=>(int)$p['shots'],'hits'=>(int)$p['hits'],'combo'=>(int)($p['streak'] ?? 0),'maxStreak'=>(int)$p['max_streak'],'finished'=>(bool)$p['finished'],
                'connected'=>$p['user_status'] === 'active' && ($isMe || $now - (int)$p['last_seen_ms'] < DUEL_STALE_MS),
                'silentMs'=>$isMe ? 0 : max(0, $now - max((int)$p['last_seen_ms'], min($now, $starts))),
                'ghost'=>false,'rating'=>(int)round((float)$r['rating']),'calibrating'=>(int)$r['games'] < DUEL_CALIBRATION_GAMES];
        }
        $ghostInfo = null;
        if ($ghost) {
            $ghostEvents = json_decode((string)$d['ghost_payload'], true) ?: [];
            $elapsed = $finished ? PHP_INT_MAX : $now - $starts;
            $prog = duel_ghost_progress($ghostEvents, $elapsed);
            $cpu = $d['ghost_source'] === 'cpu';
            $ownerName = $owner ? $names[(int)$owner['id']] : null;
            // ownerId: kayıtlı koşunun sahibi (şikâyet/engel hedefi); CPU ya da silinmiş sahipte null.
            $out[] = ['id'=>DUEL_GHOST_ID,'username'=>$cpu ? 'CPU' : ($ownerName['name'] ?? 'Kayıtlı oyuncu'),'ownerId'=>$owner['public_id'] ?? null,
                'blocked'=>$ownerName['blocked'] ?? false,'seat'=>1,'score'=>$prog['score'],'lives'=>3,
                'shots'=>$prog['shots'],'hits'=>$prog['hits'],'combo'=>$prog['streak'],'maxStreak'=>$prog['max_streak'],
                'finished'=>$finished || $now - $starts >= DUEL_SECONDS * 1000,'connected'=>true,'silentMs'=>0,'ghost'=>true,'rating'=>null,'calibrating'=>false];
            $ghostInfo = ['source'=>$cpu ? 'cpu' : 'recorded','eventCount'=>count($ghostEvents),'events'=>$withGhost ? $ghostEvents : null];
        }
        $winnerId = null;
        foreach ($players as $p) if ($d['winner_id'] !== null && (int)$p['user_id'] === (int)$d['winner_id']) $winnerId = $p['public_id'];
        $v2 = (int)($d['version'] ?? 1) >= 2;
        $draw = $v2 ? (bool)(int)$d['draw'] : $winnerId === null;
        if ($ghost && $finished && $winnerId === null && !$draw) $winnerId = DUEL_GHOST_ID;
        $rematch = null;
        if ($finished && !$ghost && $v2 && $other && !mod_pair_blocked($user, (int)$other['user_id'])) {
            $rematch = ['expiresAtMs'=>(int)$d['finished_at_ms'] + DUEL_REMATCH_MS,'mine'=>(bool)(int)$mine['rematch'],'theirs'=>(bool)(int)$other['rematch'],
                'duelId'=>duel_query('SELECT id FROM duels WHERE rematch_of=?', [$id])->fetchColumn() ?: null];
        }
        // Yerel oyunun sayaçlarını sunucuya yeniden hizalaması için (reddedilen şut sonrası).
        $last = duel_event_payload($id, $user, (int)$mine['shots']);
        $me = ['score'=>(int)$mine['score'],'shots'=>(int)$mine['shots'],'hits'=>(int)$mine['hits'],'misses'=>(int)($mine['misses'] ?? 0),
            'streak'=>(int)($mine['streak'] ?? 0),'maxStreak'=>(int)$mine['max_streak'],'feverHits'=>(int)($mine['fever_hits'] ?? 0),
            'fever'=>(bool)(int)($mine['fever'] ?? 0),'feverT'=>(int)($mine['fever_t'] ?? 0),'lastT'=>(int)($mine['last_shot_ms'] ?? 0),
            'lastRt'=>is_int($last['rt'] ?? null) ? $last['rt'] : (int)($mine['last_shot_ms'] ?? 0),'lastStage'=>$last['stage'] ?? 'street'];
        return ['ok'=>true,'serverNowMs'=>$now,'duel'=>[
            'id'=>$id,'version'=>(int)($d['version'] ?? 1),'kind'=>$d['kind'] ?? 'live','seed'=>(int)$d['seed'],'nonce'=>$mine['nonce'],
            'status'=>$finished ? 'finished' : ($now < $starts ? 'countdown' : 'live'),
            'startsAtMs'=>$starts,'endsAtMs'=>(int)$d['ends_at_ms'],'shotClockMs'=>DUEL_SHOT_CLOCK_MS,
            'players'=>$out,'myAcceptedSeq'=>(int)$mine['shots'],'me'=>$me,
            'events'=>array_map(fn($e) => json_decode($e['payload'], true), $events),
            'ghost'=>$ghostInfo,
            'result'=>$finished ? ['winnerId'=>$winnerId,'draw'=>$draw,'reason'=>$d['reason'],
                'xp'=>$mine['xp_gain'] === null ? null : (int)$mine['xp_gain'],
                'ratingBefore'=>$mine['rating_before'] === null ? null : (int)$mine['rating_before'],
                'ratingAfter'=>$mine['rating_after'] === null ? null : (int)$mine['rating_after'],
                'ratingCounted'=>$mine['rating_after'] !== null] : null,
            'rematch'=>$rematch,
        ]];
    });
}

function duel_create_live(array $userIds, int $now, ?string $rematchOf = null): string {
    $id = bin2hex(random_bytes(16)); $start = $now + DUEL_COUNTDOWN_MS;
    duel_query('INSERT INTO duels(id,seed,starts_at_ms,ends_at_ms,version,kind,rematch_of) VALUES(?,?,?,?,?,"live",?)',
        [$id, random_int(1, 2147483647), $start, $start + DUEL_SECONDS * 1000, DUEL_VERSION, $rematchOf]);
    foreach (array_values($userIds) as $seat => $player) {
        duel_query('INSERT INTO duel_players(duel_id,user_id,seat,nonce,last_seen_ms) VALUES(?,?,?,?,?)', [$id, $player, $seat, bin2hex(random_bytes(16)), $now]);
    }
    duel_query('DELETE FROM duel_queue WHERE user_id IN (?,?)', [$userIds[0], $userIds[1]]);
    return $id;
}

function duel_create_ghost(int $user, float $rating, int $now): string {
    $id = bin2hex(random_bytes(16)); $start = $now + DUEL_COUNTDOWN_MS; $seed = random_int(1, 2147483647);
    $src = duel_pick_ghost_source($user, $rating);
    $events = $src ? $src['events'] : duel_cpu_run($seed);
    $final = duel_ghost_progress($events, PHP_INT_MAX);
    duel_query('INSERT INTO duels(id,seed,starts_at_ms,ends_at_ms,version,kind,ghost_source,ghost_user_id,ghost_duel_id,ghost_payload,ghost_score,ghost_hits,ghost_max_streak) VALUES(?,?,?,?,?,"ghost",?,?,?,?,?,?,?)',
        [$id, $seed, $start, $start + DUEL_SECONDS * 1000, DUEL_VERSION, $src ? 'recorded' : 'cpu', $src['user_id'] ?? null, $src['duel_id'] ?? null,
         json_encode($events, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR), $final['score'], $final['hits'], $final['max_streak']]);
    duel_query('INSERT INTO duel_players(duel_id,user_id,seat,nonce,last_seen_ms) VALUES(?,?,0,?,?)', [$id, $user, bin2hex(random_bytes(16)), $now]);
    duel_query('DELETE FROM duel_queue WHERE user_id=?', [$user]);
    return $id;
}

/**
 * Maç açan her yol (kuyruk eşleşmesi, ghost, rövanş) aynı adlandırılmış kilidi alır: bir oyuncu
 * aynı anda iki aktif maça giremez. Older MariaDB'de SKIP LOCKED gerektirmez.
 */
function duel_with_match_lock(callable $action): mixed {
    $lock = 'svduel_'.substr(hash('sha256', (string)envv('DB_DSN')), 0, 40);
    duel_require((int)duel_query('SELECT GET_LOCK(?,3)', [$lock])->fetchColumn() === 1, 'busy', 'Eşleşme yoğun; yeniden dene.', 503);
    try { return $action(); }
    finally { duel_query('SELECT RELEASE_LOCK(?)', [$lock]); }
}

function duel_queue(int $user): array {
    $waited = 0;
    $id = duel_with_match_lock(function () use ($user, &$waited) {
        return duel_transaction(function () use ($user, &$waited) {
            $now = duel_now();
            $active = duel_query('SELECT d.* FROM duels d JOIN duel_players p ON p.duel_id=d.id WHERE p.user_id=? AND d.status="active" ORDER BY d.created_at DESC LIMIT 1', [$user])->fetch();
            if ($active) {
                [$d, $players] = duel_lock_match($active['id'], $user); duel_resolve($d, $players, $now);
                if ($d['status'] !== 'finished') return $d['id'];
            }
            // Kuyruğa giren oyuncu açık rövanş teklifini geri çekmiş olur.
            duel_query('UPDATE duel_players p JOIN duels d ON d.id=p.duel_id SET p.rematch=0 WHERE p.user_id=? AND p.rematch=1 AND d.status="finished"', [$user]);
            duel_query('DELETE FROM duel_queue WHERE last_seen_ms<?', [$now - 15000]);
            duel_query('INSERT INTO duel_queue(user_id,joined_ms,last_seen_ms) VALUES(?,?,?) ON DUPLICATE KEY UPDATE last_seen_ms=VALUES(last_seen_ms)', [$user, $now, $now]);
            $joined = (int)duel_query('SELECT joined_ms FROM duel_queue WHERE user_id=?', [$user])->fetchColumn();
            $waited = $now - $joined;
            $mine = (float)duel_rating_row($user)['rating'];
            // İki yönlü engel: engellediği ya da onu engelleyen oyuncuyla eşleşmez.
            $cands = duel_query('SELECT q.user_id,q.joined_ms,COALESCE(r.rating,1500) rating FROM duel_queue q JOIN users u ON u.id=q.user_id LEFT JOIN duel_ratings r ON r.user_id=q.user_id
                WHERE q.user_id<>? AND u.status="active" AND u.username IS NOT NULL
                  AND NOT EXISTS (SELECT 1 FROM user_blocks b WHERE (b.blocker_id=? AND b.blocked_id=q.user_id) OR (b.blocker_id=q.user_id AND b.blocked_id=?))
                ORDER BY q.joined_ms,q.user_id LIMIT 50 FOR UPDATE', [$user, $user, $user])->fetchAll();
            foreach ($cands as $c) {
                $band = duel_band(max($waited, $now - (int)$c['joined_ms']), count($cands));
                if (abs((float)$c['rating'] - $mine) <= $band) return duel_create_live([(int)$c['user_id'], $user], $now);
            }
            if ($waited >= DUEL_GHOST_AFTER_MS) return duel_create_ghost($user, $mine, $now);
            return null;
        });
    });
    return $id ? duel_snapshot($id, $user, 0, true)
        : ['ok'=>true,'status'=>'waiting','serverNowMs'=>duel_now(),'waitedMs'=>$waited,'ghostAfterMs'=>DUEL_GHOST_AFTER_MS];
}

function duel_rematch(string $id, int $user): array {
    // Rövanş da maç açar: kuyruk eşleşmesiyle aynı kilit (A yeni rakiple eşleşirken B'nin rövanşı).
    duel_with_match_lock(fn() => duel_transaction(function () use ($id, $user) {
        [$d, $players] = duel_lock_match($id, $user); $now = duel_now();
        duel_resolve($d, $players, $now);
        duel_require($d['status'] === 'finished' && $d['kind'] === 'live' && (int)$d['version'] >= 2, 'rematch_unavailable', 'Bu maç için rövanş yok.', 409);
        if (duel_query('SELECT id FROM duels WHERE rematch_of=?', [$id])->fetchColumn()) return;
        duel_require($now <= (int)$d['finished_at_ms'] + DUEL_REMATCH_MS + 1000, 'rematch_expired', 'Rövanş süresi doldu.', 409);
        $other = array_values(array_filter($players, fn($p) => (int)$p['user_id'] !== $user))[0];
        // Maçtan sonra engellenen (ya da engelleyen) rakiple rövanş yok.
        duel_require(!mod_pair_blocked($user, (int)$other['user_id']), 'rematch_unavailable', 'Bu oyuncuyla rövanş yapılamıyor.', 409);
        duel_query('UPDATE duel_players SET rematch=1 WHERE duel_id=? AND user_id=?', [$id, $user]);
        if (!(int)$other['rematch']) return;
        $busy = (int)duel_query('SELECT COUNT(*) FROM duel_players p JOIN duels x ON x.id=p.duel_id WHERE p.user_id IN (?,?) AND x.status="active"', [$user, $other['user_id']])->fetchColumn();
        duel_require(!$busy && $other['user_status'] === 'active', 'rematch_unavailable', 'Rakibin başka bir maça geçti.', 409);
        duel_create_live([(int)$players[0]['user_id'], (int)$players[1]['user_id']], $now, $id);
    }));
    return duel_snapshot($id, $user);
}

function duel_stats(int $user): array {
    $r = duel_rating_row($user);
    return ['ok'=>true,'stats'=>['rating'=>(int)round((float)$r['rating']),'games'=>(int)$r['games'],'wins'=>(int)$r['wins'],'losses'=>(int)$r['losses'],
        'draws'=>(int)$r['draws'],'xp'=>(int)$r['xp'],'calibrating'=>(int)$r['games'] < DUEL_CALIBRATION_GAMES,
        'calibrationLeft'=>max(0, DUEL_CALIBRATION_GAMES - (int)$r['games'])]];
}

/** İstemcinin düello protokol sürümü: POST gövdesi ya da GET sorgusu `duelVersion`. */
function duel_client_version(string $method): int {
    if ($method === 'GET') return (int)($_GET['duelVersion'] ?? 0);
    $b = json_decode((string)file_get_contents('php://input') ?: '{}', true);
    return is_array($b) && is_int($b['duelVersion'] ?? null) ? $b['duelVersion'] : 0;
}

function duel_route(string $method, string $path, array $user): array {
    $uid = (int)$user['id'];
    duel_require((bool)$user['username'], 'username_required', 'Önce kullanıcı adını belirle.', 409);
    if ($path === '/v1/duels/queue') {
        if ($method === 'GET' || $method === 'POST') {
            // Build 9/11 (v1, can sistemi) gövdesiz gelir: anlaşılır güncelleme hatası.
            duel_require(duel_client_version($method) === DUEL_VERSION, 'update_required', DUEL_UPDATE_MESSAGE, 426);
            return duel_queue($uid);
        }
        if ($method === 'DELETE') {
            duel_query('DELETE FROM duel_queue WHERE user_id=?', [$uid]);
            $id = duel_query('SELECT d.id FROM duels d JOIN duel_players p ON p.duel_id=d.id WHERE p.user_id=? AND d.status="active" LIMIT 1', [$uid])->fetchColumn();
            // Cancellation racing a match is a forfeit, never leaves a stranded opponent.
            if ($id) return duel_forfeit((string)$id, $uid);
            return ['ok'=>true,'status'=>'left','serverNowMs'=>duel_now()];
        }
    }
    if ($path === '/v1/duels/stats' && $method === 'GET') return duel_stats($uid);
    duel_require((bool)preg_match('#^/v1/duels/([a-f0-9]{32})(?:/(events|finish|forfeit|rematch))?$#', $path, $m), 'not_found', 'Uç nokta bulunamadı.', 404);
    $id = $m[1]; $action = $m[2] ?? '';
    if ($method === 'GET' && $action === '') return duel_snapshot($id, $uid, max(0, min(300, (int)($_GET['since'] ?? 0))), ($_GET['ghost'] ?? '') === '1');
    if ($method === 'POST' && $action === 'forfeit') return duel_forfeit($id, $uid);
    if ($method === 'POST' && $action === 'rematch') return duel_rematch($id, $uid);
    duel_require($method === 'POST' && in_array($action, ['events','finish'], true), 'not_found', 'Uç nokta bulunamadı.', 404);
    $data = body();
    $rejected = duel_transaction(function () use ($id, $uid, $action, $data) {
        [$d, $players] = duel_lock_match($id, $uid); $now = duel_now();
        $p = array_values(array_filter($players, fn($p) => (int)$p['user_id'] === $uid))[0];
        duel_require(is_string($data['nonce'] ?? null) && hash_equals($p['nonce'], $data['nonce']), 'invalid_nonce', 'Düello kimliği eşleşmedi.', 403);
        if ($d['status'] === 'finished') return;
        duel_require($now >= (int)$d['starts_at_ms'], 'not_started', 'Düello henüz başlamadı.', 409);
        duel_require($now <= (int)$d['ends_at_ms'] + DUEL_GRACE_MS, 'match_expired', 'Düello süresi doldu.', 409);
        if ($action === 'events') {
            duel_require((int)($d['version'] ?? 1) >= DUEL_VERSION, 'update_required', DUEL_UPDATE_MESSAGE, 426);
            $events = $data['events'] ?? null;
            duel_require(is_array($events) && array_is_list($events) && count($events) > 0 && count($events) <= 30, 'invalid_event', 'Şut paketi geçersiz.');
            $p = duel_with_last_event($p, duel_event_payload($id, $uid, (int)$p['shots']));
            foreach ($events as $e) {
                // Reddedilen şuttan önceki geçerli şutlar kalıcı olur; istemci reddi görüp
                // olayı düşürür ve `me` durumuna göre yeniden hizalanır (paket sonsuza dek tekrarlanmaz).
                try {
                    duel_require(is_array($e), 'invalid_event', 'Şut kaydı geçersiz.');
                    $seq = duel_integer($e['seq'] ?? null, 1, 300, 'seq');
                    $payload = json_encode($e, JSON_UNESCAPED_UNICODE | JSON_UNESCAPED_SLASHES | JSON_THROW_ON_ERROR); $hash = hash('sha256', $payload);
                    duel_require(strlen($payload) <= 4096, 'invalid_event', 'Şut kaydı çok büyük.');
                    if ($seq <= (int)$p['shots']) {
                        $old = duel_query('SELECT payload_hash FROM duel_events WHERE duel_id=? AND user_id=? AND seq=?', [$id, $uid, $seq])->fetchColumn();
                        duel_require($old && hash_equals((string)$old, $hash), 'event_conflict', 'Bu şut daha önce farklı kaydedilmiş.', 409); continue;
                    }
                    duel_require(!(int)$p['finished'], 'already_finished', 'Koşu tamamlandı.', 409);
                    $next = duel_validate_event($e, $p, $now - (int)$d['starts_at_ms']);
                } catch (DuelError $err) {
                    return new DuelError($err->kind, $err->getMessage(), $err->status,
                        ['seq'=>is_array($e) && is_int($e['seq'] ?? null) ? $e['seq'] : null, 'acceptedSeq'=>(int)$p['shots']]);
                }
                duel_query('INSERT INTO duel_events(duel_id,user_id,seq,payload,payload_hash) VALUES(?,?,?,?,?)', [$id, $uid, $seq, $payload, $hash]);
                foreach (['score','shots','hits','misses','streak','max_streak','fever','fever_t','fever_hits','last_shot_ms','last_rt_ms','last_path','last_stage'] as $key) $p[$key] = $next[$key];
                duel_query('UPDATE duel_players SET score=?,shots=?,hits=?,misses=?,streak=?,max_streak=?,fever=?,fever_t=?,fever_hits=?,last_shot_ms=?,last_seen_ms=? WHERE duel_id=? AND user_id=?',
                    [$p['score'], $p['shots'], $p['hits'], $p['misses'], $p['streak'], $p['max_streak'], $p['fever'], $p['fever_t'], $p['fever_hits'], $p['last_shot_ms'], $now, $id, $uid]);
            }
        } else {
            // The persisted event stream is the result; never accept a client supplied summary.
            duel_query('UPDATE duel_players SET finished=1,last_seen_ms=? WHERE duel_id=? AND user_id=?', [$now, $id, $uid]);
        }
        return null;
    });
    if ($rejected) throw $rejected;
    return duel_snapshot($id, $uid, max(0, min(300, (int)($data['since'] ?? 0))));
}

function duel_forfeit(string $id, int $user): array {
    duel_transaction(function () use ($id, $user) {
        [$d, $players] = duel_lock_match($id, $user);
        if ($d['status'] === 'finished') return;
        duel_query('UPDATE duel_players SET forfeited=1,finished=1 WHERE duel_id=? AND user_id=?', [$id, $user]);
        foreach ($players as &$p) if ((int)$p['user_id'] === $user) { $p['forfeited'] = 1; $p['finished'] = 1; }
        unset($p); duel_resolve($d, $players, duel_now());
    });
    return duel_snapshot($id, $user);
}
