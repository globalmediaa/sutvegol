<?php
declare(strict_types=1);
/*
 * Oyuncu güvenliği (App Store Guideline 1.2, kullanıcı içeriği): kullanıcı adları başka
 * oyunculara görünür (düello rakibi, kayıtlı rakip, sıralama). Bu dosya dört korumayı toplar:
 *   1) Kullanıcı adı filtresi (kayıt, ad seçimi, /v1/username/check aynı kuralı kullanır).
 *   2) Şikâyet: POST /v1/report; aynı ad için 3 farklı kişiden açık "username" şikâyeti gelince
 *      ad, yönetici incelemesine kadar başkalarına "Oyuncu#XXXX" görünür.
 *   3) Engelleme: /v1/blocks; eşleşme iki yönlü engeli dikkate alır, sıralamada engelleyene
 *      "Engellenen oyuncu" görünür.
 *   4) Yönetici: reddet / zorla yeniden adlandır (eski ad name_bans'a) / askıya al
 *      (backend/admin/index.php).
 *
 * Filtre kuralı (kısa masum kelimeleri yakalamamak için):
 *   - Ad küçük harfe çevrilir, Türkçe harfler katlanır (ı/İ→i, ş→s, ğ→g, ü→u, ö→o, ç→c),
 *     @→a $→s !→i. Harf olmayan her şey (alt çizgi, rakam) parça ayırıcıdır.
 *   - Dört biçim denenir: düz (rakamlar ayıklanmış), leet (0→o 1→i 3→e 4→a 5→s 7→t),
 *     leet 1→l ve uçtaki rakamları atılmış leet. Leet yalnız harf içeren parçaya uygulanır;
 *     "455", "1515" gibi saf sayılar kelimeye dönüşmez.
 *   - MOD_EXACT (kısa ya da başka anlamı olan kelimeler) yalnız bütün bir parça, tek harflerin
 *     birleşimi ("s_i_k") ya da adın tamamı olarak eşleşir: "isik", "sikke", "seksen", "nazim",
 *     "cocktail", "essex" geçer.
 *   - MOD_CONTAINS (masum anlamı olmayan kelimeler) parça içinde aranır; 6+ harfli olanlar alt
 *     çizgisiz adın tamamında da ("oros_pu"). Kısa olanlar parça sınırını aşmaz: "konyaspor_nihat"
 *     içindeki "porn", "yeni_gg" içindeki "nigg" eşleşmez.
 *   - Taklit: MOD_RESERVED parça içinde, MOD_RESERVED_FLAT alt çizgisiz adda, MOD_RESERVED_EXACT
 *     bütün parça olarak. MOD_ALLOW'daki masum sözcükler (badminton, pineapple) önce çıkarılır.
 *   - Harf tekrarı hoş görülür ("siiiktir"); çift harfli kelimede en az o kadar harf gerekir
 *     ("ass" için "as" eşleşmez). Bütün parça kelimelerinde (MOD_EXACT) tekrar ancak belirgin
 *     uzatmaysa (en az iki fazla harf) sayılır: "book"/"mood"/"seeks" geçer, "siiik" eşleşir.
 * İstemci listeyi taşımaz; tek doğruluk kaynağı sunucudur (backend/tests/moderation_unit_test.php).
 */

const TERMS_VERSION = 1;
const MOD_REPORT_REASONS = ['username', 'cheating', 'other'];
const MOD_REPORT_CONTEXTS = ['duel', 'ghost', 'leaderboard'];
/** Aynı (mevcut) ada farklı kişiden gelen açık "username" şikâyeti: ad gizlenir. */
const MOD_HIDE_THRESHOLD = 3;
/** Kişi başı 24 saatte açılabilen yeni şikâyet (aynı hedefe tekrar sayılmaz). */
const MOD_REPORTS_PER_DAY = 20;
const MOD_NOTE_MAX = 200;
const MOD_BLOCK_LIMIT = 500;
const MOD_BLOCKED_LABEL = 'Engellenen oyuncu';
const USERNAME_INVALID = '3–20 karakter; yalnızca harf, rakam ve alt çizgi kullan.';
const USERNAME_NOT_ALLOWED = 'Bu kullanıcı adı uygun değil. Küfür, hakaret, cinsel içerik, nefret söylemi ya da resmî hesap taklidi içeremez.';

const MOD_FOLD = [
    'ı' => 'i', 'ş' => 's', 'ğ' => 'g', 'ü' => 'u', 'ö' => 'o', 'ç' => 'c', 'â' => 'a', 'î' => 'i', 'û' => 'u',
    'é' => 'e', 'è' => 'e', 'ê' => 'e', 'ë' => 'e', 'á' => 'a', 'à' => 'a', 'ä' => 'a', 'ã' => 'a', 'å' => 'a',
    'ó' => 'o', 'ò' => 'o', 'ô' => 'o', 'õ' => 'o', 'ú' => 'u', 'ù' => 'u', 'í' => 'i', 'ì' => 'i', 'ï' => 'i',
    'ñ' => 'n', 'ß' => 'ss', '@' => 'a', '$' => 's', '!' => 'i', '€' => 'e', '|' => 'i',
];
const MOD_LEET = ['0' => 'o', '1' => 'i', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't'];
const MOD_LEET_L = ['0' => 'o', '1' => 'l', '3' => 'e', '4' => 'a', '5' => 's', '7' => 't'];

/** Bütün parça olarak eşleşen küfür / cinsel / nefret kelimeleri (TR + EN). */
const MOD_EXACT = [
    // TR
    'aq', 'amk', 'amq', 'amina', 'anani', 'got', 'gotu', 'gotos', 'sik', 'sikim', 'sikis', 'sktr', 'sktir', 'pic',
    'oc', 'ibne', 'ipne',
    'pust', 'pezo', 'yarak', 'tasak', 'bok', 'salak', 'aptal', 'ahmak', 'gavur', 'sapik', 'seks', 'seksi',
    // EN
    'fuk', 'fck', 'fuq', 'fack', 'shit', 'shits', 'shitty', 'ass', 'arse', 'dick', 'cock', 'cunt', 'pussy', 'pussies', 'slut',
    'twat', 'prick', 'retard', 'retarded', 'wtf', 'sex', 'sexy', 'xxx', 'nude', 'nudes', 'boob', 'boobs', 'tits',
    'penis', 'vagina', 'vajina', 'horny', 'milf', 'rape', 'rapist', 'pedo',
    // nefret / terör
    'fag', 'fags', 'kike', 'spic', 'chink', 'coon', 'tranny', 'nazi', 'heil', 'kkk', 'isis', 'isid', 'pkk', 'feto',
    'daes', 'deas',
];

/** Alt çizgisiz adın içinde aranan, masum anlamı olmayan uzun kelimeler (TR + EN). */
const MOD_CONTAINS = [
    // TR küfür / hakaret
    'orospu', 'orosbu', 'oruspu', 'orusbu', 'orspu', 'orsbu', 'siktir', 'siktim', 'sikerim', 'sikeyim', 'sikiyim',
    'sikicem', 'sikecem', 'sikecegim', 'sikik', 'sikmek', 'amcik', 'amcig', 'aminako', 'aminakoy', 'ananisik',
    'anasinisik', 'bacinisik', 'avradini', 'yarrak', 'yarram', 'yarrag', 'dalyarak', 'tassak', 'pezevenk', 'kahpe',
    'kahbe', 'kaltak',
    'kancik', 'surtuk', 'fahise', 'kerhane', 'gavat', 'yavsak', 'serefsiz', 'namussuz', 'haysiyetsiz', 'gerizekali',
    'dangalak', 'embesil', 'gotveren', 'gotlek', 'ibne', 'pickurusu', 'tecavuz', 'pedofil', 'amkcoc', 'sikiyo',
    'siktig', 'sikkafa', 'sikici', 'pezeveng',
    // EN
    'fuck', 'fcuk', 'fvck', 'phuck', 'bullshit', 'shithead', 'shitface', 'bitch', 'bastard', 'asshole', 'dickhead',
    'cocksucker', 'whore', 'wanker', 'bollocks', 'jerkoff', 'porn', 'titties', 'dildo', 'blowjob', 'handjob',
    'rimjob', 'masturb', 'orgasm', 'orgazm', 'hentai', 'onlyfans', 'pedophil', 'nigg', 'faggot', 'fck', 'nudes',
    'kissmyass', 'dumbass', 'cuntface', 'hitler', 'siegheil', 'neonazi',
];

/** Taklit (resmî hesap izlenimi): parça içinde aranır. */
const MOD_RESERVED = [
    'admin', 'moderator', 'yonetici', 'yetkili', 'official', 'offical', 'apple', 'google', 'gelistirici',
];
/** Taklit: alt çizgisiz adın içinde aranır ("sut_ve_gol", "destek_ekibi"). */
const MOD_RESERVED_FLAT = [
    'sutvegol', 'globalmedia', 'gmgaming', 'appstore', 'playstore', 'destekekibi', 'destekhatti', 'resmihesap',
    'resmidestek', 'supportteam', 'customersupport', 'customerservice', 'musterihizmet',
];
/** Taklit: yalnız bütün parça olarak ("destekci", "model", "resmiye" geçer). */
const MOD_RESERVED_EXACT = [
    'mod', 'destek', 'support', 'resmi', 'staff', 'yonetim', 'cpu', 'developer',
];
/** Bir yasaklı kelimeyi içeren masum sözcükler; aramadan önce çıkarılır. */
const MOD_ALLOW = ['badminton', 'pineapple', 'grapple', 'snapple', 'scrapple', 'dapple', 'spor'];

// ------------------------------------------------------------------ saf filtre fonksiyonları

/** Küçük harf + Türkçe/aksan katlama + @→a $→s !→i. */
function mod_fold(string $value): string {
    $s = strtr($value, ['İ' => 'i', 'I' => 'i']);
    return strtr(mb_strtolower($s, 'UTF-8'), MOD_FOLD);
}

/** Harf tekrarlarını tek harfe indirir ("siiiktir" → "siktir"). */
function mod_squeeze(string $s): string {
    return (string) preg_replace('/(.)\1+/', '$1', $s);
}

/**
 * Adın karşılaştırma biçimleri; her biçim harf parçalarının listesidir.
 * plain: rakamlar ayırıcı · leet / leet_l: rakamlar harfe · edge: uç rakamlar atılır, içtekiler leet.
 * @return array{plain: list<string>, leet: list<string>, leet_l: list<string>, edge: list<string>}
 */
function mod_forms(string $name): array {
    $forms = ['plain' => [], 'leet' => [], 'leet_l' => [], 'edge' => []];
    $split = fn(string $s): array => preg_split('/[^a-z]+/', $s, -1, PREG_SPLIT_NO_EMPTY) ?: [];
    foreach (preg_split('/[^a-z0-9]+/', mod_fold($name), -1, PREG_SPLIT_NO_EMPTY) ?: [] as $segment) {
        array_push($forms['plain'], ...$split($segment));
        // Saf sayı ("1907", "455") kelimeye çevrilmez.
        if (!preg_match('/[a-z]/', $segment)) continue;
        array_push($forms['leet'], ...$split(strtr($segment, MOD_LEET)));
        array_push($forms['leet_l'], ...$split(strtr($segment, MOD_LEET_L)));
        array_push($forms['edge'], ...$split(strtr((string) preg_replace('/^[0-9]+|[0-9]+$/', '', $segment), MOD_LEET)));
    }
    return $forms;
}

/** Ardışık tek harf parçalarını birleştirir: ["a","q","ali"] → ["aq"]. */
function mod_merge_singles(array $tokens): array {
    $out = []; $run = '';
    foreach ($tokens as $t) {
        if (strlen($t) === 1) { $run .= $t; continue; }
        if (strlen($run) > 1) $out[] = $run;
        $run = '';
    }
    if (strlen($run) > 1) $out[] = $run;
    return $out;
}

/** Kelime → harf tekrarına izin veren desen ("yarrak" → y+a+r{2,}a+k+). */
function mod_pattern(string $word): string {
    preg_match_all('/(.)\1*/', $word, $m);
    $out = '';
    foreach ($m[0] as $run) $out .= preg_quote($run[0], '/') . (strlen($run) > 1 ? '{' . strlen($run) . ',}' : '+');
    return $out;
}

/**
 * Bütün parça kelimeleri için: harf grubu ya tam sayıda ya da en az iki fazla ("bok" → "book"
 * eşleşmez, "boook" eşleşir). Kısa kelimede çift ünlü çoğu zaman başka bir kelimedir.
 */
function mod_pattern_strict(string $word): string {
    preg_match_all('/(.)\1*/', $word, $m);
    $out = '';
    foreach ($m[0] as $run) {
        $n = strlen($run); $c = preg_quote($run[0], '/');
        $out .= '(?:' . $c . '{' . $n . '}|' . $c . '{' . ($n + 2) . ',})';
    }
    return $out;
}

function mod_regex(string $list): string {
    static $cache = [];
    if (isset($cache[$list])) return $cache[$list];
    $long = array_values(array_filter(MOD_CONTAINS, fn($w) => strlen($w) >= 6));
    [$words, $whole, $strict] = match ($list) {
        'exact' => [MOD_EXACT, true, true],
        'contains' => [MOD_CONTAINS, false, false],
        'contains_long' => [$long, false, false],
        'reserved' => [MOD_RESERVED, false, false],
        'reserved_whole' => [array_merge(MOD_RESERVED, MOD_RESERVED_FLAT), true, false],
        'reserved_flat' => [MOD_RESERVED_FLAT, false, false],
        'reserved_exact' => [MOD_RESERVED_EXACT, true, true],
    };
    $alt = implode('|', array_map($strict ? 'mod_pattern_strict' : 'mod_pattern', $words));
    return $cache[$list] = $whole ? "/^(?:$alt)$/" : "/(?:$alt)/";
}

function mod_strip_allowed(string $s): string {
    return str_replace(MOD_ALLOW, '', $s);
}

/**
 * Adı başka oyunculara gösterilemez kılan sebep: 'profanity' (küfür/hakaret/cinsel/nefret),
 * 'impersonation' (resmî hesap taklidi) ya da uygunsa null.
 */
function mod_name_reason(string $name): ?string {
    foreach (mod_forms($name) as $tokens) {
        if (!$tokens) continue;
        $flat = implode('', $tokens);
        $units = array_values(array_unique(array_merge($tokens, mod_merge_singles($tokens))));
        foreach ([...$units, $flat] as $u) {
            if (preg_match(mod_regex('exact'), $u)) return 'profanity';
            if (preg_match(mod_regex('reserved_exact'), $u)) return 'impersonation';
        }
        $clean = mod_strip_allowed($flat);
        foreach ($units as $u) {
            if (preg_match(mod_regex('contains'), mod_strip_allowed($u))) return 'profanity';
        }
        // Uzun kelimeler bölünse de yakalanır ("oros_pu"); kısalar parça sınırını aşmaz.
        if (preg_match(mod_regex('contains_long'), $clean)) return 'profanity';
        if (preg_match(mod_regex('reserved_flat'), $clean) || preg_match(mod_regex('reserved_whole'), $flat)) return 'impersonation';
        foreach ($units as $u) {
            if (preg_match(mod_regex('reserved'), mod_strip_allowed($u))) return 'impersonation';
        }
    }
    return null;
}

/**
 * Yönetici yasağının saklanan normal biçimi: uç rakamsız leet, alt çizgisiz, tekrarsız. Kısa kökler
 * ("ali_34" → "ali") ve sistemin verdiği "oyuncu_NNNN" yalnız tam adıyla yasaklanır (boş norm);
 * aksi halde masum binlerce ad (ali1907, oyuncu_…) reddedilirdi.
 */
function mod_ban_norm(string $name): string {
    $norm = mod_squeeze(implode('', mod_forms($name)['edge']));
    return strlen($norm) >= 5 && $norm !== 'oyuncu' ? $norm : '';
}

/** Aday adın yasak listesiyle karşılaştırılacak normal biçimleri (dört biçimin hepsi). */
function mod_ban_candidates(string $name): array {
    $out = [];
    foreach (mod_forms($name) as $tokens) {
        $key = mod_squeeze(implode('', $tokens));
        if ($key !== '') $out[$key] = true;
    }
    return array_keys($out);
}

/** Şikâyet notu: kontrol karakterleri boşluğa, boşluklar teke, en çok 200 karakter; boşsa null. */
function mod_clean_note(mixed $note): ?string {
    if ($note === null) return null;
    if (!is_string($note)) return null;
    $note = trim((string) preg_replace('/\s+/u', ' ', (string) preg_replace('/[\x00-\x1F\x7F]/u', ' ', $note)));
    return $note === '' ? null : mb_substr($note, 0, MOD_NOTE_MAX, 'UTF-8');
}

/** Gizlenen adın gösterimi: "Oyuncu#" + kalıcı kimliğin ilk 4 karakteri. */
function mod_hidden_label(string $publicId): string {
    return 'Oyuncu#' . strtoupper(substr($publicId, 0, 4));
}

// ------------------------------------------------------------------ veritabanı yardımcıları

function mod_query(string $sql, array $args = []): PDOStatement {
    $q = db()->prepare($sql); $q->execute($args); return $q;
}

function mod_in(array $values): string {
    return implode(',', array_fill(0, max(1, count($values)), '?'));
}

/** Yöneticinin yasakladığı ad mı (tam ya da normal biçim eşleşmesi)? */
function name_banned(string $name): bool {
    $keys = mod_ban_candidates($name);
    $sql = 'SELECT 1 FROM name_bans WHERE name_key=?';
    $args = [username_key($name)];
    if ($keys) { $sql .= ' OR name_norm IN (' . mod_in($keys) . ')'; array_push($args, ...$keys); }
    return (bool) mod_query($sql . ' LIMIT 1', $args)->fetchColumn();
}

/** Kayıt, ad seçimi ve /v1/username/check ortak kuralı: [kod, mesaj] ya da uygunsa null. */
function username_issue(string $name): ?array {
    if (!valid_username($name)) return ['invalid_username', USERNAME_INVALID];
    if (mod_name_reason($name) !== null || name_banned($name)) return ['username_not_allowed', USERNAME_NOT_ALLOWED];
    return null;
}

function username_guard(string $name): void {
    if ($issue = username_issue($name)) fail($issue[0], $issue[1]);
}

/** İstemcinin gönderdiği kullanım koşulu sürümü (yalnız bilinen sürüm saklanır). */
function terms_version_from(array $data): ?int {
    $v = $data['termsVersion'] ?? null;
    return is_int($v) && $v >= 1 && $v <= TERMS_VERSION ? $v : null;
}

/**
 * user_id → ['hidden' => mevcut ada en az 3 farklı kişiden açık "username" şikâyeti var ve yönetici
 * bu adı onaylamamış, 'cleared' => yönetici mevcut adı inceleyip reddetmiş (users.name_cleared_key)].
 * Onaylanan ad yeni şikâyetlerle (sahte hesaplar dahil) yeniden gizlenemez; ad değişince onay düşer.
 */
function mod_name_flags(array $userIds): array {
    $ids = array_values(array_unique(array_map('intval', $userIds)));
    if (!$ids) return [];
    $rows = mod_query('SELECT u.id,(u.name_cleared_key IS NOT NULL AND u.name_cleared_key=u.username_key) cleared,
        (SELECT COUNT(DISTINCT r.reporter_id) FROM user_reports r WHERE r.target_id=u.id AND r.status="open" AND r.reason="username" AND r.reported_name=u.username) votes
        FROM users u WHERE u.id IN (' . mod_in($ids) . ')', $ids)->fetchAll();
    $out = [];
    foreach ($rows as $r) {
        $cleared = (bool) (int) $r['cleared'];
        $out[(int) $r['id']] = ['cleared' => $cleared, 'hidden' => !$cleared && (int) $r['votes'] >= MOD_HIDE_THRESHOLD];
    }
    return $out;
}

/** $viewer'ın engellediği kullanıcılar (id → true). */
function mod_blocked_by(int $viewer, array $userIds): array {
    $ids = array_values(array_unique(array_map('intval', $userIds)));
    if (!$ids) return [];
    $rows = mod_query('SELECT blocked_id FROM user_blocks WHERE blocker_id=? AND blocked_id IN (' . mod_in($ids) . ')', [$viewer, ...$ids])->fetchAll(PDO::FETCH_COLUMN);
    return array_fill_keys(array_map('intval', $rows), true);
}

/** İki kullanıcı arasında herhangi bir yönde engel var mı? */
function mod_pair_blocked(int $a, int $b): bool {
    return (bool) mod_query('SELECT 1 FROM user_blocks WHERE (blocker_id=? AND blocked_id=?) OR (blocker_id=? AND blocked_id=?) LIMIT 1', [$a, $b, $b, $a])->fetchColumn();
}

/**
 * Başka oyunculara gösterilecek adlar. $rows: [['id'=>int, 'public_id'=>string, 'username'=>?string], ...].
 * İzleyicinin kendisi → kendi adı; engellediği → "Engellenen oyuncu"; 3 şikâyetle gizlenen ya da filtreye
 * takılan (eski) ad → "Oyuncu#XXXX" (yönetici onayladıysa görünür).
 * Dönüş: id → ['name'=>string, 'blocked'=>bool, 'hidden'=>bool].
 */
function mod_public_names(?int $viewer, array $rows, bool $applyBlocks = true): array {
    $ids = array_map(fn($r) => (int) $r['id'], $rows);
    $flags = mod_name_flags($ids);
    $blocked = $viewer !== null && $applyBlocks ? mod_blocked_by($viewer, $ids) : [];
    $out = [];
    foreach ($rows as $r) {
        $id = (int) $r['id']; $name = $r['username'] ?? null;
        if ($viewer !== null && $id === $viewer) { $out[$id] = ['name' => $name ?? 'Oyuncu', 'blocked' => false, 'hidden' => false]; continue; }
        // Yöneticinin onayladığı ad filtre yanlış pozitifi olsa da görünür.
        $cleared = $flags[$id]['cleared'] ?? false;
        $isHidden = ($flags[$id]['hidden'] ?? false) || (!$cleared && $name !== null && mod_name_reason((string) $name) !== null);
        $label = isset($blocked[$id]) ? MOD_BLOCKED_LABEL : ($name === null ? 'Oyuncu' : ($isHidden ? mod_hidden_label((string) $r['public_id']) : (string) $name));
        $out[$id] = ['name' => $label, 'blocked' => isset($blocked[$id]), 'hidden' => $isHidden];
    }
    return $out;
}

/** Şikâyet/engel hedefi: kalıcı kimlikle bulunur; yoksa ya da silinmişse 410. */
function mod_target(mixed $publicId): array {
    if (!is_string($publicId) || !preg_match('/^[0-9A-Fa-f]{26}$/', $publicId)) fail('invalid_target', 'Oyuncu kimliği geçersiz.');
    $target = mod_query('SELECT id,public_id,username,status FROM users WHERE public_id=?', [strtoupper($publicId)])->fetch();
    // 404 istemciye ucun olmadığını düşündürür; hedef artık yok.
    if (!$target || $target['status'] === 'deleted') fail('player_gone', 'Bu oyuncu artık yok.', 410);
    return $target;
}

// ------------------------------------------------------------------ uçlar

function mod_report(array $user, array $data): array {
    rate_limit('report', 30, 300);
    $reason = $data['reason'] ?? null;
    if (!in_array($reason, MOD_REPORT_REASONS, true)) fail('invalid_reason', 'Şikâyet sebebi geçersiz.');
    $context = $data['context'] ?? null;
    if (!in_array($context, MOD_REPORT_CONTEXTS, true)) fail('invalid_context', 'Şikâyet bağlamı geçersiz.');
    $duelId = $data['duel_id'] ?? null;
    if ($duelId !== null && (!is_string($duelId) || !preg_match('/^[a-f0-9]{32}$/', $duelId))) fail('invalid_duel', 'Düello kimliği geçersiz.');
    if (isset($data['note']) && !is_string($data['note'])) fail('invalid_note', 'Not geçersiz.');
    $note = mod_clean_note($data['note'] ?? null);
    $target = mod_target($data['target_user_id'] ?? null);
    $uid = (int) $user['id']; $tid = (int) $target['id'];
    if ($tid === $uid) fail('cannot_report_self', 'Kendini şikâyet edemezsin.');
    if ($duelId !== null) {
        // Şikâyet eden o düelloda oynamış olmalı; hedef canlı rakip ya da kayıtlı koşunun sahibi.
        $duel = mod_query('SELECT d.kind,d.ghost_user_id FROM duels d JOIN duel_players p ON p.duel_id=d.id AND p.user_id=? WHERE d.id=?', [$uid, $duelId])->fetch();
        $ok = $duel && ($duel['kind'] === 'ghost'
            ? (int) $duel['ghost_user_id'] === $tid
            : (bool) mod_query('SELECT 1 FROM duel_players WHERE duel_id=? AND user_id=?', [$duelId, $tid])->fetchColumn());
        if (!$ok) fail('invalid_duel', 'Bu oyuncu o düelloda yer almadı.');
    }
    $name = $target['username'];
    $find = fn() => mod_query('SELECT id,status,reason,reported_name FROM user_reports WHERE reporter_id=? AND target_id=?', [$uid, $tid])->fetch();
    $existing = $find();
    if (!$existing) {
        $recent = (int) mod_query('SELECT COUNT(*) FROM user_reports WHERE reporter_id=? AND created_at>=DATE_SUB(NOW(),INTERVAL 1 DAY)', [$uid])->fetchColumn();
        if ($recent >= MOD_REPORTS_PER_DAY) fail('report_limit', 'Bugün çok fazla şikâyet gönderdin. Yarın yeniden dene.', 429);
        $insert = db()->prepare('INSERT IGNORE INTO user_reports(reporter_id,target_id,reason,context,duel_id,note,reported_name) VALUES(?,?,?,?,?,?,?)');
        $insert->execute([$uid, $tid, $reason, $context, $duelId, $note, $name]);
        if ($insert->rowCount() === 1) return ['ok' => true, 'reported' => true];
        $existing = $find(); // aynı anda gelen ikinci istek
        if (!$existing) fail('server', 'Şikâyet kaydedilemedi. Yeniden dene.', 503);
    }
    // Aynı kişi → aynı hedef: tek kayıt güncellenir. Reddedilmiş şikâyet aynı ad ve sebeple yeniden açılmaz.
    $same = $existing['status'] === 'dismissed' && $existing['reason'] === $reason
        && username_key((string) $existing['reported_name']) === username_key((string) $name);
    $status = $same ? 'dismissed' : 'open';
    // Kapanmış kaydın yeniden açılması yeni şikâyet sayılır: günlük sınıra girer, 24 saat sayacı baştan.
    $reopen = $status === 'open' && $existing['status'] !== 'open';
    if ($reopen && (int) mod_query('SELECT COUNT(*) FROM user_reports WHERE reporter_id=? AND created_at>=DATE_SUB(NOW(),INTERVAL 1 DAY)', [$uid])->fetchColumn() >= MOD_REPORTS_PER_DAY) {
        fail('report_limit', 'Bugün çok fazla şikâyet gönderdin. Yarın yeniden dene.', 429);
    }
    mod_query('UPDATE user_reports SET status=?,reason=?,context=?,duel_id=?,note=?,reported_name=?,resolved_at=IF(?="open",NULL,resolved_at),created_at=IF(?,NOW(),created_at),updated_at=NOW() WHERE id=?',
        [$status, $reason, $context, $duelId, $note, $name, $status, $reopen ? 1 : 0, $existing['id']]);
    return ['ok' => true, 'reported' => true];
}

function mod_block(array $user, array $data): array {
    rate_limit('block', 60, 300);
    $target = mod_target($data['user_id'] ?? null);
    $uid = (int) $user['id']; $tid = (int) $target['id'];
    if ($tid === $uid) fail('cannot_block_self', 'Kendini engelleyemezsin.');
    $exists = (bool) mod_query('SELECT 1 FROM user_blocks WHERE blocker_id=? AND blocked_id=?', [$uid, $tid])->fetchColumn();
    if (!$exists) {
        $count = (int) mod_query('SELECT COUNT(*) FROM user_blocks WHERE blocker_id=?', [$uid])->fetchColumn();
        if ($count >= MOD_BLOCK_LIMIT) fail('block_limit', 'Engel listen dolu. Önce bir engeli kaldır.');
        mod_query('INSERT IGNORE INTO user_blocks(blocker_id,blocked_id) VALUES(?,?)', [$uid, $tid]);
    }
    return ['ok' => true, 'blocked' => true];
}

function mod_unblock(array $user, string $publicId): array {
    mod_query('DELETE b FROM user_blocks b JOIN users u ON u.id=b.blocked_id WHERE b.blocker_id=? AND u.public_id=?', [(int) $user['id'], strtoupper($publicId)]);
    return ['ok' => true, 'blocked' => false];
}

function mod_blocks(array $user): array {
    $rows = mod_query('SELECT u.id,u.public_id,u.username,UNIX_TIMESTAMP(b.created_at) ts FROM user_blocks b JOIN users u ON u.id=b.blocked_id
        WHERE b.blocker_id=? AND u.status<>"deleted" ORDER BY b.created_at DESC,u.id DESC LIMIT ' . MOD_BLOCK_LIMIT, [(int) $user['id']])->fetchAll();
    // Kendi listesinde de uygunsuz/gizlenmiş ad yeniden gösterilmez.
    $names = mod_public_names(null, $rows);
    return ['ok' => true, 'blocks' => array_map(fn($r) => [
        'id' => $r['public_id'], 'name' => $names[(int) $r['id']]['name'],
        'blockedAt' => gmdate('c', (int) $r['ts']),
    ], $rows)];
}

/** Mevcut hesabın Kullanım Koşulları onayı (kayıttan önce açılmış hesaplar uygulamada bir kez onaylar). */
function mod_accept_terms(array $user, array $data): array {
    $version = terms_version_from($data);
    if ($version === null) fail('invalid_terms', 'Kullanım Koşulları sürümü geçersiz.');
    mod_query('UPDATE users SET terms_version=GREATEST(COALESCE(terms_version,0),?),terms_accepted_at=NOW() WHERE id=?', [$version, (int) $user['id']]);
    return ['ok' => true, 'termsVersion' => max($version, (int) ($user['terms_version'] ?? 0))];
}

function moderation_route(string $method, string $path, array $user): array {
    if ($path === '/v1/me/terms' && $method === 'POST') return mod_accept_terms($user, body());
    if ($path === '/v1/report' && $method === 'POST') return mod_report($user, body());
    if ($path === '/v1/blocks' && $method === 'GET') return mod_blocks($user);
    if ($path === '/v1/blocks' && $method === 'POST') return mod_block($user, body());
    if ($method === 'DELETE' && preg_match('#^/v1/blocks/([0-9A-Fa-f]{26})$#', $path, $m)) return mod_unblock($user, $m[1]);
    fail('not_found', 'Uç nokta bulunamadı.', 404);
}

/**
 * Hesap silme: engeller (iki yön) ve kişinin gönderdiği/aldığı şikâyetler silinir; yasaklı ad
 * listesi kişiyle bağını kaybeder. 3 şikâyetle gizlenmiş ad, silinip yeniden alınamasın diye
 * kişisiz olarak yasak listesine eklenir. Çağıran işlem (transaction) içindedir.
 */
function mod_forget_user(int $userId, ?string $username): void {
    if ($username !== null && (mod_name_flags([$userId])[$userId]['hidden'] ?? false)) {
        mod_query('INSERT IGNORE INTO name_bans(name_key,name_norm,user_id) VALUES(?,?,NULL)', [username_key($username), mod_ban_norm($username)]);
    }
    mod_query('DELETE FROM user_blocks WHERE blocker_id=? OR blocked_id=?', [$userId, $userId]);
    mod_query('DELETE FROM user_reports WHERE reporter_id=? OR target_id=?', [$userId, $userId]);
    mod_query('UPDATE name_bans SET user_id=NULL WHERE user_id=?', [$userId]);
}

// ------------------------------------------------------------------ yönetici eylemleri

/**
 * Açık şikâyetleri reddeder ve mevcut adı onaylanmış işaretler: aynı kişiler aynı ad ve sebeple
 * yeniden açamaz, yeni şikâyetler kuyruğa düşse de ad yeniden gizlenmez (ad değişince onay düşer).
 */
function mod_admin_dismiss(int $targetId): int {
    mod_query('UPDATE users SET name_cleared_key=username_key WHERE id=? AND username_key IS NOT NULL', [$targetId]);
    return mod_query('UPDATE user_reports SET status="dismissed",resolved_at=NOW() WHERE target_id=? AND status="open"', [$targetId])->rowCount();
}

/** Zorla yeniden adlandırır: mevcut ve şikâyet edilen adlar name_bans'a, kullanıcıya "oyuncu_xxxx". */
function mod_admin_rename(int $targetId): ?string {
    db()->beginTransaction();
    try {
        $user = mod_query('SELECT id,username FROM users WHERE id=? AND status<>"deleted" FOR UPDATE', [$targetId])->fetch();
        if (!$user) { db()->rollBack(); return null; }
        // Yasak: mevcut ad + uygunsuz ad olarak şikâyet edilen adlar (hile/diğer şikâyetindeki ad değil).
        $names = mod_query('SELECT DISTINCT reported_name FROM user_reports WHERE target_id=? AND status="open" AND reason="username" AND reported_name IS NOT NULL', [$targetId])->fetchAll(PDO::FETCH_COLUMN);
        if ($user['username'] !== null) $names[] = $user['username'];
        foreach (array_unique(array_map('strval', $names)) as $old) {
            mod_query('INSERT IGNORE INTO name_bans(name_key,name_norm,user_id) VALUES(?,?,?)', [username_key($old), mod_ban_norm($old), $targetId]);
        }
        $new = null;
        for ($i = 0; $i < 20 && $new === null; $i++) {
            // Yalnız rakam: rastgele harfler yeni bir uygunsuz parça ("aq", "kkk") oluşturamaz.
            $candidate = 'oyuncu_' . str_pad((string) random_int(0, $i < 10 ? 9999 : 999999), $i < 10 ? 4 : 6, '0', STR_PAD_LEFT);
            try {
                mod_query('UPDATE users SET username=?,username_key=? WHERE id=?', [$candidate, username_key($candidate), $targetId]);
                $new = $candidate;
            } catch (PDOException $e) {
                if (($e->errorInfo[1] ?? 0) !== 1062) throw $e; // yalnız ad çakışmasında yeniden dene
            }
        }
        if ($new === null) throw new RuntimeException('Yeni kullanıcı adı üretilemedi.');
        mod_query('UPDATE user_reports SET status="actioned",resolved_at=NOW() WHERE target_id=? AND status="open"', [$targetId]);
        db()->commit();
        return $new;
    } catch (Throwable $e) {
        if (db()->inTransaction()) db()->rollBack();
        throw $e;
    }
}

/** Hesabı askıya alır: giriş/eşleşme kapanır, oturumlar düşer, kuyruktan çıkar, şikâyetler kapanır. */
function mod_admin_suspend(int $targetId): bool {
    db()->beginTransaction();
    try {
        $changed = mod_query('UPDATE users SET status="suspended" WHERE id=? AND status="active"', [$targetId])->rowCount() === 1;
        if ($changed) {
            mod_query('UPDATE refresh_tokens SET revoked_at=NOW() WHERE user_id=? AND revoked_at IS NULL', [$targetId]);
            mod_query('DELETE FROM duel_queue WHERE user_id=?', [$targetId]);
            mod_query('UPDATE user_reports SET status="actioned",resolved_at=NOW() WHERE target_id=? AND status="open"', [$targetId]);
        }
        db()->commit();
        return $changed;
    } catch (Throwable $e) {
        if (db()->inTransaction()) db()->rollBack();
        throw $e;
    }
}

function mod_admin_unsuspend(int $targetId): bool {
    return mod_query('UPDATE users SET status="active" WHERE id=? AND status="suspended"', [$targetId])->rowCount() === 1;
}
