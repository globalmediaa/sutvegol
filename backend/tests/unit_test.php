<?php
declare(strict_types=1);
/*
 * Veritabanısız saf fonksiyon testleri: combo/Kral Modu geçişi, şut saati doğrulaması,
 * CPU koşusu, ghost ilerlemesi, eşleşme bandı ve Glicko-2. Çalıştırma (PHP 8.1+):
 *   php backend/tests/unit_test.php
 */
require dirname(__DIR__) . '/vendor/autoload.php';
require dirname(__DIR__) . '/src/duels.php';
function envv(string $k, ?string $d = null): ?string { return $d; }

$failures = 0; $count = 0;
function check(bool $ok, string $name): void {
    global $failures, $count; $count++;
    if (!$ok) { $failures++; fwrite(STDERR, "FAIL: $name\n"); }
}
function throws(callable $fn, string $code): bool {
    try { $fn(); } catch (DuelError $e) { return $e->kind === $code; }
    return false;
}
/** Sunucu kuralıyla üretilmiş geçerli olay; `rt` (sonuçlanma) varsayılanı t + 1 sn, timeout'ta t. */
function ev(array $s, bool $hit, int $t, int $seq, ?string $path = null, ?int $rt = null): array {
    $rt ??= $path === 'timeout' ? $t : $t + 1000;
    $c = duel_candidates($s, $hit, $rt);
    $n = (count($c) > 1 && $rt >= $s['fever_t'] + DUEL_FEVER_MS) ? $c[1] : $c[0];
    return ['v'=>2,'seq'=>$seq,'t'=>$t,'rt'=>$rt,'stage'=>duel_stage_for((int)$s['score']),'view'=>'wide','target'=>[660,1350],
        'chord'=>[0,-500],'dev'=>0,'tMax'=>.5,'power'=>.5,'keeper'=>[null,null],'path'=>$path ?? ($hit ? 'net' : 'out'),'hit'=>$hit,
        'end'=>[660,1350],'drop'=>null,'score'=>$n['score'],'streak'=>$n['streak'],'fever'=>(bool)$n['fever'],'feverLeft'=>0,
        'shots'=>$n['shots'],'hits'=>$n['hits'],'misses'=>$n['misses'],'feverHits'=>$n['fever_hits'],'maxStreak'=>$n['max_streak'],'mult'=>$n['mult']];
}
function player(array $s, int $last, ?int $lastRt = null, ?string $path = null, ?string $stage = null): array {
    return $s + ['last_shot_ms'=>$last, 'last_rt_ms'=>$lastRt ?? $last, 'last_path'=>$path, 'last_stage'=>$stage];
}
/** Olayları sırayla doğrular (her olay sonuçlanmadan 500 ms sonra ulaşır); son durumu ya da ilk hatayı döner. */
function chain(array $events, ?array $p = null): array|string {
    $p ??= player(duel_initial_state(), 0);
    foreach ($events as $e) {
        try { $p = duel_validate_event($e, $p, max($e["t"], $e["rt"] ?? 0) + 500); }
        catch (DuelError $err) { return $err->kind . '@' . $e['seq']; }
    }
    return $p;
}

// Combo çarpanı: x1 → x2 → x3, tavan 3; ıskalama combo'yu sıfırlar ama maçı bitirmez.
$s = duel_initial_state(); $scores = []; $t = 0;
foreach ([true, true, true, true, false, true] as $i => $hit) {
    $t += 1500; $s = duel_candidates($s, $hit, $t)[0]; $scores[] = $s['score'];
}
check($scores === [30, 90, 180, 270, 270, 300], 'combo x1/x2/x3 ve ıskalamada sıfırlama: ' . json_encode($scores));
check($s['streak'] === 1 && $s['max_streak'] === 4 && $s['misses'] === 1, 'seri sayaçları');

// Kral Modu: 5. golde başlar (x3), sonra x2 sabit; süre dolunca seri sıfırdan.
$s = duel_initial_state(); $t = 0;
for ($i = 0; $i < 5; $i++) { $t += 1000; $s = duel_candidates($s, true, $t)[0]; }
check((bool)$s['fever'] && $s['fever_t'] === 5000 && $s['score'] === 30 + 60 + 90 + 90 + 90, 'Kral Modu 5. golde başlar');
$in = duel_candidates($s, true, 7000);
check(count($in) === 1 && $in[0]['mult'] === 2 && $in[0]['fever_hits'] === 1, 'Kral Modu içinde x2');
$edge = duel_candidates($s, true, 15000);
check(count($edge) === 2 && $edge[0]['mult'] === 2 && $edge[1]['mult'] === 1 && $edge[1]['streak'] === 1, 'Kral Modu sınırında iki geçerli sonuç');
$late = duel_candidates($s, true, 15101);
check(count($late) === 1 && $late[0]['mult'] === 1 && !$late[0]['fever'], 'Kral Modu süresi kesin dolmuş (rt, 100 ms pay)');
$still = duel_candidates($s, true, 14899);
check(count($still) === 1 && $still[0]['mult'] === 2, 'Kral Modu son anı x2 (rt)');

// Kral Modu kök neden: istemci sonucu topun düştüğü anda (rt) işler. 5. gol direkten sekip
// 3 sn'de sayıldı; sonraki gol vuruştan 12,1 sn sonra atıldı ama 9,9 sn sonra sayıldı → x2.
// Eski t tabanlı kural (±2 sn) bunu score_math ile reddediyordu.
$s5 = duel_initial_state(); $evs = []; $t = 0;
for ($i = 1; $i <= 5; $i++) { $t += 1500; $rt = $i === 5 ? $t + 3000 : $t + 1000; $evs[] = $e = ev($s5, true, $t, $i, $i === 5 ? 'post' : null, $rt); $s5 = duel_candidates($s5, true, $rt)[0]; }
$t5 = $t; $rt5 = $t + 3000;
$six = ev($s5, true, $t5 + 12100, 6, null, $t5 + 12900);
check($six['mult'] === 2 && $six['fever'] && is_array(chain([...$evs, $six])), 'uzun sonuçlanan 5. golden sonra Kral Modu x2 kabul');
$sixLate = ev($s5, true, $t5 + 12100, 6, null, $rt5 + 10300);
check($sixLate['mult'] === 1 && $sixLate['streak'] === 1 && is_array(chain([...$evs, $sixLate])), 'süresi sonuçlanmada dolan Kral Modu x1 kabul');
$wrong = $sixLate; $wrong['mult'] = 2; $wrong['score'] = $six['score']; $wrong['fever'] = true; $wrong['streak'] = 6; $wrong['maxStreak'] = 6; $wrong['feverHits'] = 1;
check(chain([...$evs, $wrong]) === 'score_math@6', 'Kral Modu bittikten sonra x2 reddi');

// Şut saati: ardışık şutlar arası en çok 5 sn + döngü payı; timeout en erken 5 sn'de.
$p = player(duel_initial_state(), 0);
check(throws(fn() => duel_validate_event(ev($p, true, 10001, 1), $p, 20000), 'shot_clock'), 'ilk şut şut saatini aşamaz');
check(is_array(duel_validate_event(ev($p, true, 4000, 1), $p, 5000)), "geçerli ilk şut");
// p2: 4. sn'de vurulan, 5. sn'de sayılan gol sonrası (şut saati sonuçlanmadan ölçülür).
$p2 = player(duel_candidates(duel_initial_state(), true, 5000)[0], 4000, 5000, 'net', 'street');
check(throws(fn() => duel_validate_event(ev($p2, false, 9600, 2, 'timeout'), $p2, 20000), 'shot_clock'), 'erken timeout reddi');
$to = duel_validate_event(ev($p2, false, 9800, 2, 'timeout'), $p2, 20000);
check($to['streak'] === 0 && $to['misses'] === 1 && $to['last_shot_ms'] === 9800 && $to['last_rt_ms'] === 9800, 'timeout = otomatik ıskalama, combo sıfır');
$hitTimeout = ev($p2, false, 9800, 2, 'timeout'); $hitTimeout['hit'] = true;
check(throws(fn() => duel_validate_event($hitTimeout, $p2, 20000), 'shot_clock'), 'timeout gol olamaz');
check(throws(fn() => duel_validate_event(ev($p2, true, 15001, 2), $p2, 20000), 'shot_clock'), 'şutlar arası üst sınır (rt + 10 sn)');
check(is_array(duel_validate_event(ev($p2, true, 15000, 2), $p2, 20000)), 'şutlar arası üst sınır dahil');
check(throws(fn() => duel_validate_event(ev($p2, true, 5300, 2), $p2, 20000), 'invalid_timing'), 'şutlar arası alt sınır (önceki sonuçtan 350 ms)');
// Sahne geçişi (arka plan üretimi + afiş) şut saatine 4 sn ekler; geçiş yoksa ek yok.
$pBeach = player(['score'=>300] + duel_initial_state(), 20000, 21000, 'net', 'street'); $pBeach['shots'] = 10; $pBeach['hits'] = 10;
$afterStage = ev($pBeach, false, 34000, 11);
check($afterStage['stage'] === 'beach' && is_array(duel_validate_event($afterStage, $pBeach, 35000)), 'sahne geçişi sonrası 13 sn boşluk kabul');
$pSame = $pBeach; $pSame['last_stage'] = 'beach';
check(throws(fn() => duel_validate_event($afterStage, $pSame, 35000), 'shot_clock'), 'geçiş yoksa 13 sn boşluk reddi');
// Uzun boşluk (arka plan / yeniden hizalama) sonrası tek timeout kabul; vuruş değil.
check(is_array(duel_validate_event(ev($p2, false, 30000, 2, 'timeout'), $p2, 30500)), 'uzun boşluktan sonra timeout kabul');
check(throws(fn() => duel_validate_event(ev($p2, true, 30000, 2), $p2, 30500), 'shot_clock'), 'uzun boşluktan sonra vuruş reddi');
// Timeout'un hemen ardından vuruş (top zaten hazır) kabul.
$pTo = player($to, 9800, 9800, 'timeout', 'street'); $pTo['shots'] = 2;
check(is_array(duel_validate_event(ev($pTo, true, 9900, 3), $pTo, 11000)), 'timeout ardından hemen vuruş');
// rt sınırları.
$r1 = ev($p, true, 4000, 1); $r1['rt'] = 3999;
check(throws(fn() => duel_validate_event($r1, $p, 20000), 'invalid_event'), 'rt < t reddi');
$r1['rt'] = 9001;
check(throws(fn() => duel_validate_event($r1, $p, 20000), 'invalid_event'), 'rt > t + 5 sn reddi');
$r1 = ev($p, true, 4000, 1); unset($r1['rt']);
check(throws(fn() => duel_validate_event($r1, $p, 20000), 'invalid_event'), 'rt zorunlu');
// Alt sınır: şut sunucuya en geç 12 sn eski t ile ulaşır.
check(is_array(duel_validate_event(ev($p, true, 4000, 1), $p, 16000)), '12 sn gecikme kabul');
check(throws(fn() => duel_validate_event(ev($p, true, 4000, 1), $p, 16001), 'invalid_timing'), '12 sn üstü gecikme reddi');
// Makullük tavanı: n. şut t ≥ (n-1) × 1,5 sn.
$fast = [ev(duel_initial_state(), true, 600, 1, null, 1400)];
$fs = duel_candidates(duel_initial_state(), true, 1400)[0];
$fast[] = ev($fs, true, 2000, 2, null, 2500); $fs = duel_candidates($fs, true, 2500)[0];
$fast[] = ev($fs, true, 2950, 3, null, 3700);
check(chain($fast) === 'invalid_timing@3', '3. şut 3 sn dolmadan reddi');
// Dürüst en hızlı tempo (aut: uçuş 0,44 + 0,3 + 0,4 + yeni top 0,55 = 1,69 sn) 90 sn boyunca kabul.
$hs = duel_initial_state(); $honest = []; $t = 550; $n = 0;
while ($t < 89000) { $honest[] = $e = ev($hs, false, $t, ++$n, null, $t + 1040); $hs = duel_candidates($hs, false, $t + 1040)[0]; $t += 1690; }
check(is_array(chain($honest)) && $n > 50, "dürüst en hızlı tempo kabul ($n şut)");
check(throws(fn() => duel_validate_event(ev($p, true, 4000, 1), $p, 2000), 'invalid_timing'), 'gelecekten şut');
$bad = ev($p, true, 4000, 1); $bad['mult'] = 2;
check(throws(fn() => duel_validate_event($bad, $p, 5000), 'score_math'), 'yanlış çarpan');
$bad = ev($p, true, 4000, 1); $bad['score'] = 60;
check(throws(fn() => duel_validate_event($bad, $p, 5000), 'score_math'), 'yanlış skor');
$v1 = ev($p, true, 4000, 1); $v1['v'] = 1;
check(throws(fn() => duel_validate_event($v1, $p, 5000), 'update_required'), 'v1 olay reddi');

// CPU koşusu: deterministik ve sunucu doğrulamasından baştan sona geçer.
$run = duel_cpu_run(42);
check($run === duel_cpu_run(42) && $run !== duel_cpu_run(43) && count($run) > 15, 'CPU koşusu deterministik');
$p = chain($run);
if (!is_array($p)) fwrite(STDERR, "CPU olayı reddedildi: $p\n");
check(is_array($p) && $p['score'] === end($run)['score'], 'CPU koşusu doğrulamadan geçer');
$ts = array_column($run, 't'); $sorted = $ts; sort($sorted);
check($ts === $sorted, 'CPU olayları t sırasında');

// Ghost ilerlemesi t'ye göre.
$prog = duel_ghost_progress($run, $run[2]['t']);
check($prog['shots'] === 3 && $prog['score'] === $run[2]['score'], 'ghost ilerlemesi t anında');
check(duel_ghost_progress($run, 0)['score'] === 0, 'ghost başlangıçta 0');

// Eşleşme bandı.
check(duel_band(0, 10) === 200.0 && duel_band(5000, 10) === 400.0 && duel_band(10000, 10) === INF && duel_band(0, 2) === 400.0, 'eşleşme bandı');

// Glicko-2: eşit oyuncuda kazanan +, kaybeden −, simetrik; RD küçülür; beraberlik değişmez.
[$w] = $win = duel_glicko([1500, 350, .06], [1500, 350, .06], 1.0);
[$l] = $loss = duel_glicko([1500, 350, .06], [1500, 350, .06], 0.0);
check($w > 1600 && $l < 1400 && abs(($w - 1500) + ($l - 1500)) < 0.01, 'Glicko simetrik kazanç/kayıp: ' . round($w) . '/' . round($l));
check($win[1] < 350 && $loss[1] < 350, 'RD küçülür');
check(abs(duel_glicko([1500, 200, .06], [1500, 200, .06], 0.5)[0] - 1500) < 0.01, 'eşit beraberlik değişmez');
$upset = duel_glicko([1400, 80, .06], [1700, 80, .06], 1.0)[0] - 1400;
$fav = duel_glicko([1700, 80, .06], [1400, 80, .06], 1.0)[0] - 1700;
check($upset > $fav && $fav > 0, 'sürpriz galibiyet daha çok puan');
// Glickman (2012) örneği: üç maçlık tek dönemi tek tek değil; yalnız ilk maç beklenen yönde.
check(duel_glicko([1500, 200, .06], [1400, 30, .06], 1.0)[0] > 1500, 'Glickman örneği ilk maç');

echo "$count unit kontrolü, $failures hata\n";
exit($failures ? 1 : 0);
