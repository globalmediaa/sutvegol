<?php
declare(strict_types=1);
/*
 * Kullanıcı adı filtresi ve moderasyon saf fonksiyonları (veritabanısız).
 * Çalıştırma (PHP 8.1+):  php backend/tests/moderation_unit_test.php [--table]
 * --table: her ad için sonucu (yanlış pozitif / yanlış negatif tablosu) yazdırır.
 */
require dirname(__DIR__) . '/src/moderation.php';
function valid_username(string $v): bool { return (bool) preg_match('/^[a-zA-Z0-9_]{3,20}$/', $v); }
function username_key(string $v): string { return mb_strtolower(trim($v), 'UTF-8'); }

$failures = 0; $count = 0;
function check(bool $ok, string $name): void {
    global $failures, $count; $count++;
    if (!$ok) { $failures++; fwrite(STDERR, "FAIL: $name\n"); }
}
$table = in_array('--table', $argv, true);

// Engellenmesi gerekenler: kategori => adlar (kaçış yolları dahil).
$blocked = [
    'profanity' => [
        // TR küfür / hakaret
        'orospu', '0r0spu', 'oRoSpU_cocugu', 'o_r_o_s_p_u', 'orooospu', 'orsbu_ali', 'siktir', 's1kt1r', 'siiiktir_git',
        'sik_tir', 'siktirgit', 'sik', 's_i_k', 'sik123', 's1k', 'SIK_kafa', 'ali_sik', 'sikis', 'sikerim', 'sikeyim',
        'amk', '4mk', 'a_m_k', 'amk_cocugu', 'aq', 'a_q', 'aq_ali', 'amq', 'amina_koyim', 'aminakoyim', 'amcik',
        'yarrak', 'yarrrak', 'y4rr4k', 'dalyarak', 'yarak', 'pic', 'pic_kurusu', 'p1c', 'oc', 'o_c_ali', 'ibne', '1bne',
        'ipne', 'gotveren', 'g0t', 'got_lale', 'pezevenk', 'pezo', 'kahpe', 'kaltak', 'ka1tak', 'surtuk', 'fahise',
        'serefsiz', 'yavsak', 'gerizekali', 'salak', 'aptal_ali', 'gavat', 'ananisik', 'pust', 'tassak', 'bok_kafa',
        'yarragim', 'kahbe', 'gotu_buyuk', 'sktr', 'siktim', 'amcigi', 'amkcocugu', 'sikiyorum', 'siktiginin',
        'sikkafa', 'sikici_degil', 'pezevengi', 'ibneyim', 'oros_pu', 'siiik', 'boook_kafa',
        // EN
        'fuck', 'fuk_you', 'f_u_c_k', 'fck', 'FuCkYou', 'shit', 'bullshit', 'shithead', 'bitch', 'b1tch', 'asshole',
        'a55hole', 'ass', 'dick', 'd1ck', 'cock', 'cunt', 'pussy', 'whore', 'slut', 's1ut', 'wanker', 'motherfucker',
        'retard', 'twat', 'fuuuck', 'fvck', '5h1t', 'fckyou', 'kissmyass', 'dumbass', 'cuntface', 'assss',
        // cinsel
        'porn', 'p0rn', 'pornstar', 'xxx', 'xxx_ali', 'sex', 's3x', 'sexy_girl', 'seks', 'seksi_kiz', 'nude', 'boobs',
        'penis', 'dildo', 'blowjob', 'masturbasyon', 'horny', 'milf', 'onlyfans', 'hentai', 'rape', 'pedo', 'pedofil',
        'tecavuz', 'sendnudes',
        // nefret / terör
        'nigga', 'n1gger', 'nigger', 'faggot', 'fag', 'hitler', 'h1tl3r', 'adolf_hitler', 'nazi', 'kkk', 'isis', 'pkk',
        'feto', 'siegheil', 'chink', 'neonazi',
    ],
    'impersonation' => [
        'admin', '4dm1n', 'adm1n', 'the_admin', 'admin_tr', 'sysadmin', 'Administrator', 'adminali', 'moderator',
        'm0derat0r', 'mod', 'm0d', 'mod_ali', 'apple', 'apple_destek', 'appl3', 'applesupport', 'google', 'g00gle',
        'googlesupport', 'sutvegol', 'sut_ve_gol', '5utv3g0l', 'SutVeGol_Destek', 'sutvegol123', 'destek', 'destek_ekibi',
        'destekekibi', 'destek1', 'resmi', 'resmi_hesap', 'resmihesap', 'official', 'sutvegol_official', 'unofficial',
        'yonetici', 'yetkili', 'support', 'cpu', 'globalmedia', 'gmgaming', 'app_store', 'staff', 'ad_min',
        'musteri_hizmetleri',
    ],
];

// Geçmesi gerekenler: masum Türkçe/İngilizce adlar, kısa kelimeler, takım/yıl sayıları.
$allowed = [
    // içinde kısa yasaklı kelime geçen masum sözcükler
    'isik_kral', 'sikke', 'sikayet', 'musik', 'seksen', 'nazim', 'nazim_hikmet', 'amasya', 'amca_oglu', 'ananas',
    'kasik', 'sikinti', 'sikistir', 'alisik', 'tasarim', 'kayarak', 'picasso', 'picnic', 'gotik', 'gotham', 'gokhan',
    'kocaeli', 'koc_ali', 'aqua', 'amkara', 'ankara', 'ibn_sina', 'bokser', 'cocktail', 'dickens', 'scunthorpe',
    'arsenal_fan', 'essex', 'sussex', 'therapist', 'classic', 'bassist', 'assassin', 'hassan', 'hasan', 'penisilin',
    'analiz', 'kanal', 'sexton', 'yamashita', 'kinoshita', 'matsushita', 'shitake', 'cumali', 'cumhur', 'pisi',
    'semih', 'grass', 'glass', 'passion', 'titan', 'button', 'pussycat_fan_no', 'basket', 'scrap',
    // taklit sanılabilecek masumlar
    'badminton_kral', 'pineapple', 'destekci', 'resmiye', 'model_ali', 'modern', 'modric', 'supporter',
    'systema', 'rootbeer', 'ahmad_minecraft', 'murad_minik', 'staffan', 'cpucu_ali', 'googly', 'applause',
    'system32', 'root_beer', 'sistemci',
    // tekrar ya da parça sınırı aşan eşleşme olmamalı (inceleme bulguları)
    'book_lover', 'mood_ali', 'seeks', 'gott', 'konyaspor_nihat', 'sivasspor_news', 'spor_nedim', 'spornews',
    'yeni_gg', 'mini_gg', 'musiki_kral', 'mother_fan', 'kayseri_spor', 'b00k_worm',
    // takım / yıl / sayı
    'ahmet1907', 'fb_1907', 'gs1905', 'bjk1903', 'ts_1967', 'kral_455', 'cem_1515', 'ali_7175', 'mert_31',
    'mk_1881', 'atam_1938', 'ali_34', 'kral_007', 'x_1453', 'sinan_1453', 'pr_e2e', 'v2_kaan', 'duel_alice',
    // sıradan oyuncu adları
    'gol_kral', 'sut_ustasi', 'kartal', 'aslan_ali', 'mustafa_kemal', 'ayse_nur', 'zeynep', 'emre', 'samet_ocak',
    'kaleci_deniz', 'frikik_ustasi', 'Kerem_10', 'ali_veli', 'mehmet', 'elif', 'burak', 'cansu', 'irem', 'oguz_can',
    'serkan', 'tolga', 'gamze', 'hakan', 'selin', 'kemal', 'osman', 'ozan', 'ugur', 'yigit', 'baris', 'cagla',
    'dilan', 'ebru', 'fatih', 'gizem', 'halil', 'ilker', 'kaan', 'leyla', 'melis', 'nihat', 'omer', 'pinar',
    'ramazan', 'sibel', 'tugba', 'umut', 'volkan', 'yasin', 'zafer', 'alper', 'bora', 'ceren', 'derya', 'ercan',
    'furkan', 'goksel', 'hilal', 'ismail', 'kubra', 'levent', 'merve', 'necati', 'orhan', 'pelin', 'recep',
    'sukru', 'taner', 'utku', 'vedat', 'yusuf', 'zehra', 'sokak', 'sahil', 'stadyum', 'hali_saha', 'kral_modu',
    'l33t_gamer', 'n00b_master', 'h4ck3r', 'sn1per', 'k1ng_kong', 'b0ss', '4ss4ss1n', '5h00t3r', 'c00l_kid',
    'pr0_player', 'xxxtentacion', 'striker99', 'goalgetter', 'messi10', 'ronaldo7', 'neymar_jr', 'the_kicker', 'curve_master', 'NightOwl',
    'bassline', 'mass_effect', 'assist_king', 'grasshopper', 'Scorpion', 'shooter_x', 'falso_kral', 'aksam',
    'sabah', 'gece', 'yildiz', 'ates', 'buz', 'firtina', 'kasirga', 'yagmur', 'bulut', 'deniz', 'nehir', 'orman',
];

$fn = []; $fp = [];
foreach ($blocked as $category => $names) {
    foreach ($names as $name) {
        $got = mod_name_reason($name);
        if ($got === null) $fn[] = $name;
        check($got === $category, "engellenmeli ($category): $name → " . var_export($got, true));
        if ($table) printf("%-24s %-14s %s\n", $name, $category, $got ?? 'GEÇTİ (yanlış negatif)');
    }
}
foreach ($allowed as $name) {
    $got = mod_name_reason($name);
    if ($got !== null) $fp[] = $name;
    check($got === null, "geçmeli: $name → $got");
    if ($table) printf("%-24s %-14s %s\n", $name, 'uygun', $got === null ? 'geçti' : "ENGELLENDİ ($got, yanlış pozitif)");
}
$totalBlocked = array_sum(array_map('count', $blocked));
printf("Filtre: %d engellenmesi gereken (yanlış negatif %d), %d geçmesi gereken (yanlış pozitif %d)\n",
    $totalBlocked, count($fn), count($allowed), count($fp));

// Türkçe harf katlama (kullanıcı adında yasak ama filtre görünen adlarda da çalışır).
check(mod_name_reason('Piç') === 'profanity' && mod_name_reason('ORUSPU') === 'profanity' && mod_name_reason('Şerefsiz') === 'profanity', 'Türkçe harf katlama');
check(mod_name_reason('Işık') === null && mod_name_reason('Gökhan') === null && mod_name_reason('Şükrü') === null, 'Türkçe masum adlar');
check(mod_name_reason('İbne') === 'profanity' && mod_name_reason('YÖNETİCİ') === 'impersonation', 'büyük İ katlanır');
check(mod_name_reason('@dmin') === 'impersonation' && mod_name_reason('$ik') === 'profanity', '@→a, $→s');

// Biçimler ve yardımcılar.
$f = mod_forms('S1k_7_ali1907');
check($f['plain'] === ['s', 'k', 'ali'] && $f['leet'] === ['sik', 'alii', 'ot'] && $f['leet_l'] === ['slk', 'alil', 'ot']
    && $f['edge'] === ['sik', 'ali'], 'biçimler: ' . json_encode($f));
check(mod_forms('455')['leet'] === [] && mod_forms('455')['plain'] === [], 'saf sayı kelimeye çevrilmez');
check(mod_merge_singles(['a', 'q', 'ali', 's', 'i', 'k', 'x']) === ['aq', 'sikx'], 'tek harf birleştirme');
check(mod_squeeze('siiiktiiir') === 'siktir' && mod_pattern('yarrak') === 'y+a+r{2,}a+k+', 'tekrar ve desen');
check(preg_match('/^' . mod_pattern_strict('bok') . '$/', 'book') === 0 && preg_match('/^' . mod_pattern_strict('bok') . '$/', 'boook') === 1
    && preg_match('/^' . mod_pattern_strict('ass') . '$/', 'as') === 0 && preg_match('/^' . mod_pattern_strict('ass') . '$/', 'assss') === 1,
    'bütün parça kelimesinde yalnız belirgin uzatma');

// Yasaklı ad normal biçimi: büyük/küçük, alt çizgi, uç rakam, leet, tekrar fark etmez.
$ban = mod_ban_norm('Kotu_Ad');
check($ban === 'kotuad', "ban normu: $ban");
foreach (['kotuad', 'KOTU_AD', 'k0tu_ad', 'kotu_ad99', 'kotuuu_ad', '7kotuad', 'k0tu4d'] as $variant) {
    check(in_array($ban, mod_ban_candidates($variant), true), "yasaklı ad varyantı yakalanır: $variant");
}
foreach (['kotu', 'iyi_ad', 'kotuadam'] as $other) {
    check(!in_array($ban, mod_ban_candidates($other), true), "başka ad yasaktan etkilenmez: $other");
}
check(mod_ban_norm('12345') === '' && !in_array('', mod_ban_candidates('12345'), true), 'saf sayı adın normu boş, eşleşmez');
// Kısa kök ve sistemin verdiği ad yalnız tam adıyla yasaklanır (ali1907, oyuncu_… etkilenmez).
check(mod_ban_norm('ali_34') === '' && mod_ban_norm('mehm') === '' && mod_ban_norm('oyuncu_1234') === '' && mod_ban_norm('Oyuncu_99') === '',
    'kısa kök / oyuncu_NNNN normsuz');

// Şikâyet notu.
check(mod_clean_note(null) === null && mod_clean_note('   ') === null && mod_clean_note(42) === null, 'boş not');
check(mod_clean_note("  hile\x00 yapıyor\n\nçok   ") === 'hile yapıyor çok', 'not temizlenir');
check(mb_strlen((string) mod_clean_note(str_repeat('ş', 500))) === MOD_NOTE_MAX, 'not 200 karaktere kırpılır');

// Gizli ad etiketi ve kullanım koşulu sürümü.
check(mod_hidden_label('ab12cd34ef56gh78ij90kl12mn') === 'Oyuncu#AB12', 'gizli ad etiketi');
check(terms_version_from(['termsVersion' => 1]) === 1 && terms_version_from(['termsVersion' => 99]) === null
    && terms_version_from(['termsVersion' => '1']) === null && terms_version_from([]) === null, 'koşul sürümü');

// Ortak kural (veritabanısız kısım): geçersiz biçim ayrı kod.
check(!valid_username('ab') && mod_name_reason('gol_kral') === null, 'biçim');

echo "$count moderasyon kontrolü, $failures hata\n";
exit($failures ? 1 : 0);
