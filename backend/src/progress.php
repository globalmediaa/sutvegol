<?php
declare(strict_types=1);
/*
 * Oyuncu ilerlemesi (bulut kaydı). Standart: anlık senkron, yeniden yüklemede giriş yapınca
 * soru sormadan geri yükleme, sıfırlama yalnız açık "Sil ve baştan başla" ile.
 *
 * payload birleştirilebilir (CRDT benzeri) JSON'dur; birleştirme değişmeli, birleşmeli ve
 * idempotenttir, bu yüzden hangi cihaz önce yazarsa yazsın "ileride olan kazanır":
 *   best / maxStreak  → en büyük
 *   devices.<id>.*    → cihaz başı sayaçlar (runs, shots, hits, feverHits, playMs) en büyük;
 *                       toplam istatistik = cihazların toplamı (aynı oyun iki kez sayılmaz)
 *   settings          → son yazan (at, ms); eşitlikte deterministik kod
 *   tutorialDone      → VEYA
 * epoch "Sil ve baştan başla" ile artar; eski epoch'la gelen yazım 409 `progress_reset` alır,
 * istemci yerel ilerlemesini siler ve sunucu durumunu benimser (diğer cihazlara yayılım).
 * İstemci karşılığı: lib/services/progress_service.dart (ProgressData.merge).
 */

const PROGRESS_SCHEMA = 1;
const PROGRESS_MAX_BYTES = 16384;
const PROGRESS_MAX_DEVICES = 48;
const PROGRESS_COUNTERS = ['runs', 'shots', 'hits', 'feverHits', 'playMs'];
const PROGRESS_COUNTER_MAX = 1000000000000; // 1e12: playMs için de yeter, JS/Dart güvenli tamsayı

final class ProgressError extends RuntimeException {
    public function __construct(public string $kind, string $message, public int $status = 422, public array $extra = []) {
        parent::__construct($message);
    }
}

function progress_int(mixed $v, int $max): int {
    if (is_int($v)) return max(0, min($max, $v));
    if (is_float($v) && is_finite($v)) return $v <= 0 ? 0 : ($v >= $max ? $max : (int) $v);
    if (is_string($v) && preg_match('/^\d{1,15}$/', $v)) return max(0, min($max, (int) $v));
    return 0;
}

function progress_empty(): array {
    return ['v' => PROGRESS_SCHEMA, 'best' => 0, 'maxStreak' => 0, 'tutorialDone' => false, 'devices' => [], 'settings' => null];
}

/** Güvenilmeyen girdiyi kanonik biçime getirir (bilinmeyen alanlar atılır, sınırlar uygulanır). */
function progress_normalize(mixed $raw): array {
    $p = is_array($raw) ? $raw : [];
    $out = progress_empty();
    $out['best'] = progress_int($p['best'] ?? 0, 10000000);
    $out['maxStreak'] = progress_int($p['maxStreak'] ?? 0, 1000000);
    $out['tutorialDone'] = ($p['tutorialDone'] ?? false) === true;
    $devices = [];
    foreach ((is_array($p['devices'] ?? null) ? $p['devices'] : []) as $id => $c) {
        $id = (string) $id;
        if (!preg_match('/^[A-Za-z0-9_-]{8,40}$/', $id) || !is_array($c)) continue;
        $row = [];
        foreach (PROGRESS_COUNTERS as $k) $row[$k] = progress_int($c[$k] ?? 0, PROGRESS_COUNTER_MAX);
        $devices[$id] = $row;
    }
    if (count($devices) > PROGRESS_MAX_DEVICES) {
        // Sınır aşılırsa en çok oynanan cihazlar kalır (deterministik: runs, sonra kimlik).
        uksort($devices, fn($a, $b) => [$devices[$b]['runs'], $a] <=> [$devices[$a]['runs'], $b]);
        $devices = array_slice($devices, 0, PROGRESS_MAX_DEVICES, true);
    }
    ksort($devices, SORT_STRING);
    $out['devices'] = $devices;
    $s = $p['settings'] ?? null;
    if (is_array($s) && is_bool($s['sound'] ?? null) && is_bool($s['haptics'] ?? null)) {
        $out['settings'] = ['sound' => $s['sound'], 'haptics' => $s['haptics'], 'at' => progress_int($s['at'] ?? 0, PROGRESS_COUNTER_MAX * 10)];
    }
    return $out;
}

function progress_settings_code(array $s): int { return ($s['sound'] ? 2 : 0) + ($s['haptics'] ? 1 : 0); }

/** İki ilerlemeyi birleştirir; sıra önemsizdir: merge(a,b) == merge(b,a). */
function progress_merge(mixed $a, mixed $b): array {
    $a = progress_normalize($a); $b = progress_normalize($b);
    $out = progress_empty();
    $out['best'] = max($a['best'], $b['best']);
    $out['maxStreak'] = max($a['maxStreak'], $b['maxStreak']);
    $out['tutorialDone'] = $a['tutorialDone'] || $b['tutorialDone'];
    $devices = $a['devices'];
    foreach ($b['devices'] as $id => $c) {
        if (!isset($devices[$id])) { $devices[$id] = $c; continue; }
        foreach (PROGRESS_COUNTERS as $k) $devices[$id][$k] = max($devices[$id][$k], $c[$k]);
    }
    $out['devices'] = $devices;
    $sa = $a['settings']; $sb = $b['settings'];
    if ($sa === null || $sb === null) $out['settings'] = $sa ?? $sb;
    elseif ($sa['at'] !== $sb['at']) $out['settings'] = $sa['at'] > $sb['at'] ? $sa : $sb;
    else $out['settings'] = progress_settings_code($sa) >= progress_settings_code($sb) ? $sa : $sb;
    return progress_normalize($out);
}

/** Sıfırlama: rekor ve istatistikler silinir; ayarlar ve rehber durumu tercih olduğu için kalır. */
function progress_wiped(mixed $p): array {
    $p = progress_normalize($p);
    $out = progress_empty();
    $out['settings'] = $p['settings'];
    $out['tutorialDone'] = $p['tutorialDone'];
    return $out;
}

function progress_totals(array $p): array {
    $t = array_fill_keys(PROGRESS_COUNTERS, 0);
    foreach ($p['devices'] as $c) foreach (PROGRESS_COUNTERS as $k) $t[$k] += $c[$k];
    return $t;
}

/** JSON çıktısı: boş eşlemler nesne olarak gider. */
function progress_json(array $p): array {
    $p['devices'] = (object) array_map(fn($c) => (object) $c, $p['devices']);
    return $p;
}

function progress_view(array $row): array {
    $payload = progress_normalize(json_decode((string) $row['payload'], true));
    return ['epoch' => (int) $row['epoch'], 'revision' => (int) $row['revision'], 'payload' => progress_json($payload),
        'totals' => progress_totals($payload), 'updatedAt' => $row['updated_at'] ? gmdate('c', strtotime($row['updated_at'] . ' UTC')) : null];
}

function progress_row(int $user, bool $lock): array {
    // Yalnız etkin hesaba satır açılır: hesap silmeyle yarışan geç bir yazım silinen kaydı geri getirmez
    // (INSERT … SELECT users satırını paylaşımlı kilitler; DELETE /v1/me ile sıralanır).
    if ($lock) db()->prepare("INSERT IGNORE INTO player_progress(user_id,payload) SELECT id,? FROM users WHERE id=? AND status='active'")
        ->execute([json_encode(progress_json(progress_empty())), $user]);
    $q = db()->prepare('SELECT * FROM player_progress WHERE user_id=?' . ($lock ? ' FOR UPDATE' : ''));
    $q->execute([$user]);
    return $q->fetch() ?: ['epoch' => 0, 'revision' => 0, 'payload' => json_encode(progress_empty()), 'updated_at' => null];
}

function progress_store(int $user, array $payload, string $extra = ''): void {
    db()->prepare("UPDATE player_progress SET payload=?,best_score=?,revision=revision+1$extra WHERE user_id=?")
        ->execute([json_encode(progress_json($payload), JSON_UNESCAPED_SLASHES), $payload['best'], $user]);
}

/** Ham istek gövdesinden payload; boyut sınırı ham JSON üzerinden. */
function progress_input(array $data): array {
    if (!array_key_exists('payload', $data) || !is_array($data['payload'])) throw new ProgressError('invalid_progress', 'İlerleme verisi eksik.');
    if (strlen((string) json_encode($data['payload'])) > PROGRESS_MAX_BYTES) throw new ProgressError('progress_too_large', 'İlerleme verisi çok büyük.', 413);
    return progress_normalize($data['payload']);
}

function progress_route(string $method, string $path, array $user): array {
    $uid = (int) $user['id'];
    if ($method === 'GET' && $path === '/v1/progress') {
        return ['ok' => true, 'progress' => progress_view(progress_row($uid, false))];
    }
    if ($method === 'PUT' && $path === '/v1/progress') {
        rate_limit('progress:' . $uid, 120, 60); // kullanıcı başı: CGNAT arkasındaki oyuncular birbirini kısmaz
        $data = body();
        $incoming = progress_input($data);
        $epoch = progress_int($data['epoch'] ?? 0, PHP_INT_MAX);
        db()->beginTransaction();
        $row = progress_row($uid, true);
        if ($epoch !== (int) $row['epoch']) {
            db()->commit();
            throw new ProgressError('progress_reset', 'İlerleme başka bir cihazda sıfırlandı.', 409, ['progress' => progress_view($row)]);
        }
        $stored = progress_normalize(json_decode((string) $row['payload'], true));
        $merged = progress_merge($stored, $incoming);
        if ($merged !== $stored) progress_store($uid, $merged);
        db()->commit();
        return ['ok' => true, 'progress' => progress_view(progress_row($uid, false))];
    }
    if ($method === 'POST' && $path === '/v1/progress/reset') {
        rate_limit('progress_reset:' . $uid, 10, 300);
        db()->beginTransaction();
        $row = progress_row($uid, true);
        progress_store($uid, progress_wiped(json_decode((string) $row['payload'], true)), ',epoch=epoch+1,reset_at=NOW()');
        db()->commit();
        return ['ok' => true, 'progress' => progress_view(progress_row($uid, false))];
    }
    throw new ProgressError('not_found', 'Uç nokta bulunamadı.', 404);
}
