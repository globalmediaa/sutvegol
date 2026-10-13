<?php
declare(strict_types=1);
/*
 * Bulut ilerlemesi saf fonksiyon testleri (veritabanısız): normalizasyon, birleştirme
 * (değişmeli/birleşmeli/idempotent, "ileride olan kazanır"), sıfırlama ve toplamlar.
 * Çalıştırma (PHP 8.1+): php backend/tests/progress_unit_test.php
 * İstemci karşılığı test/progress_test.dart aynı örnekleri kullanır.
 */
require dirname(__DIR__) . '/src/progress.php';

$failures = 0; $count = 0;
function check(bool $ok, string $name): void {
    global $failures, $count; $count++;
    if (!$ok) { $failures++; fwrite(STDERR, "FAIL: $name\n"); }
}

$a = ['best' => 420, 'maxStreak' => 7, 'tutorialDone' => true,
    'devices' => ['devA1234' => ['runs' => 5, 'shots' => 40, 'hits' => 20, 'feverHits' => 2, 'playMs' => 90000]],
    'settings' => ['sound' => false, 'haptics' => true, 'at' => 1000]];
$b = ['best' => 300, 'maxStreak' => 9,
    'devices' => ['devA1234' => ['runs' => 3, 'shots' => 50, 'hits' => 10, 'feverHits' => 4, 'playMs' => 1000],
                  'devB5678' => ['runs' => 2, 'shots' => 10, 'hits' => 5, 'feverHits' => 0, 'playMs' => 5000]],
    'settings' => ['sound' => true, 'haptics' => false, 'at' => 2000]];
$c = ['best' => 900, 'devices' => ['devC9999' => ['runs' => 1, 'shots' => 3, 'hits' => 3, 'feverHits' => 0, 'playMs' => 700]]];

$m = progress_merge($a, $b);
check($m['best'] === 420 && $m['maxStreak'] === 9, 'rekor ve en uzun seri en büyük');
check($m['devices']['devA1234'] === ['runs' => 5, 'shots' => 50, 'hits' => 20, 'feverHits' => 4, 'playMs' => 90000], 'aynı cihaz sayaçları alan alan en büyük');
check(isset($m['devices']['devB5678']), 'farklı cihaz eklenir');
check(progress_totals($m) === ['runs' => 7, 'shots' => 60, 'hits' => 25, 'feverHits' => 4, 'playMs' => 95000], 'toplam = cihazların toplamı');
check($m['settings'] === ['sound' => true, 'haptics' => false, 'at' => 2000], 'ayarlar son yazan');
check($m['tutorialDone'] === true, 'rehber durumu VEYA');

check(progress_merge($a, $b) === progress_merge($b, $a), 'değişmeli');
check(progress_merge(progress_merge($a, $b), $c) === progress_merge($a, progress_merge($b, $c)), 'birleşmeli');
check(progress_merge($m, $m) === $m && progress_merge($m, $b) === $m, 'idempotent (aynı yazım ikinci kez değiştirmez)');

// Eşit zaman damgasında ayar seçimi deterministik.
$s1 = ['settings' => ['sound' => true, 'haptics' => false, 'at' => 5]];
$s2 = ['settings' => ['sound' => false, 'haptics' => true, 'at' => 5]];
check(progress_merge($s1, $s2)['settings'] === progress_merge($s2, $s1)['settings'], 'eşit at deterministik');
check(progress_merge(['settings' => null], $s2)['settings'] === $s2['settings'], 'ayarı olmayan taraf kaybeder');

// Yeni kurulum: boş yerel + bulut = bulut (soru yok, kayıp yok).
$fresh = progress_merge(progress_empty(), $m);
check($fresh === $m, 'yeni kurulumda bulut olduğu gibi geri gelir');

// Normalizasyon: güvenilmeyen girdi.
$n = progress_normalize(['best' => -5, 'maxStreak' => '12', 'tutorialDone' => 'yes', 'extra' => 1,
    'devices' => ['kısa' => ['runs' => 1], 'ok_device_1' => ['runs' => 'x', 'shots' => 1e20], 'bad<>id!!' => []],
    'settings' => ['sound' => 'on', 'haptics' => true]]);
check($n['best'] === 0 && $n['maxStreak'] === 12 && $n['tutorialDone'] === false, 'sayılar sınırlanır, bool katı');
check(array_keys($n['devices']) === ['ok_device_1'] && $n['devices']['ok_device_1']['runs'] === 0
    && $n['devices']['ok_device_1']['shots'] === PROGRESS_COUNTER_MAX, 'geçersiz cihaz kimliği atılır, sayaç tavanı');
check($n['settings'] === null && !isset($n['extra']), 'geçersiz ayar ve bilinmeyen alan atılır');
check(progress_normalize('çöp') === progress_empty() && progress_normalize(null) === progress_empty(), 'dizi olmayan girdi boş');
$many = ['devices' => []];
for ($i = 0; $i < 60; $i++) $many['devices'][sprintf('device%03d', $i)] = ['runs' => $i];
$capped = progress_normalize($many);
check(count($capped['devices']) === PROGRESS_MAX_DEVICES && isset($capped['devices']['device059']) && !isset($capped['devices']['device000']), 'cihaz sınırı en çok oynananları tutar');

// Sıfırlama: rekor/istatistik gider, ayar ve rehber kalır.
$w = progress_wiped($m);
check($w['best'] === 0 && $w['maxStreak'] === 0 && $w['devices'] === [] && $w['settings'] === $m['settings'] && $w['tutorialDone'], 'sıfırlama rekor ve istatistiği siler, tercihleri korur');

// JSON çıktısı: boş eşlemler nesne.
check(json_encode(progress_json(progress_empty())) === '{"v":1,"best":0,"maxStreak":0,"tutorialDone":false,"devices":{},"settings":null}', 'boş devices nesne olarak');

echo "$count progress kontrolü, $failures hata\n";
exit($failures ? 1 : 0);
