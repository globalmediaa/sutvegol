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
/** Sunucu kuralıyla üretilmiş geçerli olay. */
function ev(array $s, bool $hit, int $t, int $seq, ?string $path = null): array {
    $c = duel_candidates($s, $hit, $t);
    $n = (count($c) > 1 && $t >= $s['fever_t'] + DUEL_FEVER_MS) ? $c[1] : $c[0];
    return ['v'=>2,'seq'=>$seq,'t'=>$t,'stage'=>duel_stage_for((int)$s['score']),'view'=>'wide','target'=>[660,1350],
        'chord'=>[0,-500],'dev'=>0,'tMax'=>.5,'power'=>.5,'keeper'=>[null,null],'path'=>$path ?? ($hit ? 'net' : 'out'),'hit'=>$hit,
        'end'=>[660,1350],'drop'=>null,'score'=>$n['score'],'streak'=>$n['streak'],'fever'=>(bool)$n['fever'],'feverLeft'=>0,
        'shots'=>$n['shots'],'hits'=>$n['hits'],'misses'=>$n['misses'],'feverHits'=>$n['fever_hits'],'maxStreak'=>$n['max_streak'],'mult'=>$n['mult']];
}
function player(array $s, int $last): array { return $s + ['last_shot_ms'=>$last]; }

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
$late = duel_candidates($s, true, 17500);
check(count($late) === 1 && $late[0]['mult'] === 1 && !$late[0]['fever'], 'Kral Modu süresi kesin dolmuş');

// Şut saati: ardışık şutlar arası en çok 5 sn + döngü payı; timeout en erken 5 sn'de.
$p = player(duel_initial_state(), 0);
check(throws(fn() => duel_validate_event(ev($p, true, 10001, 1), $p, 20000), 'shot_clock'), 'ilk şut şut saatini aşamaz');
check(is_array(duel_validate_event(ev($p, true, 4000, 1), $p, 20000)), 'geçerli ilk şut');
$p2 = player(duel_candidates(duel_initial_state(), true, 4000)[0], 4000);
check(throws(fn() => duel_validate_event(ev($p2, false, 7000, 2, 'timeout'), $p2, 20000), 'shot_clock'), 'erken timeout reddi');
$to = duel_validate_event(ev($p2, false, 9200, 2, 'timeout'), $p2, 20000);
check($to['streak'] === 0 && $to['misses'] === 1 && $to['last_shot_ms'] === 9200, 'timeout = otomatik ıskalama, combo sıfır');
$hitTimeout = ev($p2, false, 9200, 2, 'timeout'); $hitTimeout['hit'] = true;
check(throws(fn() => duel_validate_event($hitTimeout, $p2, 20000), 'shot_clock'), 'timeout gol olamaz');
check(throws(fn() => duel_validate_event(ev($p2, true, 14001 + 1000, 2), $p2, 20000), 'shot_clock'), 'şutlar arası üst sınır');
check(throws(fn() => duel_validate_event(ev($p2, true, 4200, 2), $p2, 20000), 'invalid_timing'), 'şutlar arası alt sınır');
check(throws(fn() => duel_validate_event(ev($p, true, 4000, 1), $p, 2000), 'invalid_timing'), 'gelecekten şut');
$bad = ev($p, true, 4000, 1); $bad['mult'] = 2;
check(throws(fn() => duel_validate_event($bad, $p, 20000), 'score_math'), 'yanlış çarpan');
$bad = ev($p, true, 4000, 1); $bad['score'] = 60;
check(throws(fn() => duel_validate_event($bad, $p, 20000), 'score_math'), 'yanlış skor');
$v1 = ev($p, true, 4000, 1); $v1['v'] = 1;
check(throws(fn() => duel_validate_event($v1, $p, 20000), 'update_required'), 'v1 olay reddi');

// CPU koşusu: deterministik ve sunucu doğrulamasından baştan sona geçer.
$run = duel_cpu_run(42);
check($run === duel_cpu_run(42) && $run !== duel_cpu_run(43) && count($run) > 15, 'CPU koşusu deterministik');
$p = player(duel_initial_state(), 0); $ok = true;
foreach ($run as $e) {
    try { $n = duel_validate_event($e, $p, 90000); $p = $n; }
    catch (DuelError $err) { $ok = false; fwrite(STDERR, "CPU olayı reddedildi: {$err->kind} seq={$e['seq']}\n"); break; }
}
check($ok && $p['score'] === end($run)['score'], 'CPU koşusu doğrulamadan geçer');
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
