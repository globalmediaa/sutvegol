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
 *     "cocktail", "essex" geçer. Bu "yalnız bütün parça" ilkesi korunur; aşağıdaki her kural onun
 *     içinde, aynı bütün parça birimlerine uygulanır (kısa kelimeyi parça içinde aramaz).
 *   - MOD_CONTAINS (masum anlamı olmayan kelimeler) parça içinde aranır; 6+ harfli olanlar alt
 *     çizgisiz adın tamamında da ("oros_pu"). Kısa olanlar parça sınırını aşmaz: "konyaspor_nihat"
 *     içindeki "porn", "yeni_gg" içindeki "nigg" eşleşmez.
 *   - Taklit: MOD_RESERVED parça içinde, MOD_RESERVED_FLAT alt çizgisiz adda, MOD_RESERVED_EXACT
 *     bütün parça olarak. MOD_ALLOW'daki masum sözcükler (badminton, pineapple) önce çıkarılır.
 *   - Harf tekrarı: MOD_CONTAINS kelimelerinde her tekrar hoş görülür ("siiiktir"). Bütün parça
 *     kelimelerinde (MOD_EXACT) tekrar önce "inceltilir": en az üç harflik yığın tek harfe (dört
 *     ve üzeriyse iki harfe) iner ("siiik" → "sik", "assss" → "ass"), ayrıca SON ünsüz yığını
 *     her uzunlukta kısalır ("sikk", "amkk", "aqqq" → "sik", "amk", "aq"). İçteki çift harf ve
 *     çift ünlü ("sikkim", "mass", "book", "mood", "seeks") ise geçer: tek harfe indirseydik bunlar
 *     "sik", "mas", "bok", "mod", "seks" olurdu. Almanca/İngilizce "gott" yüzünden "got" yalnız
 *     MOD_EXACT_NOSTRETCH ile, son harf uzatması olmadan eşleşir.
 *   - Türkçe kök + ek (MOD_TR_ROOTS × MOD_TR_SUFFIX): çoğul, iyelik/hâl, -lık/-lik/-luk/-lük,
 *     -sın/-sin/-sun/-sün ("salaklar", "sikimi", "gotunu", "bokluk", "aptallik", "yaragim").
 *     Ünlüyle başlayan ek her köke KOŞULSUZ eklenmez: ı/ş katlaması yüzünden "sik" köküne "e/a/i"
 *     eklemek "şike", "şikayet", "sıkı", "sıkıntı" gibi çok yaygın masum sözcükleri yakalardı. Her
 *     kök yalnız güvenli ek kümelerini alır. Yumuşayan köklerde (salak → salağı) ünlüyle başlayan ekte
 *     yumuşak kök kullanılır ("salagim"); yumuşatmasız "salakim" bilerek aranmaz ("salaka" = şaka geçer).
 *     "-cık" küçültmesinde ünlü uyumu ("amcik"/"amcuk") MOD_CONTAINS'e otomatik eklenir.
 *   - Kısaltma: MOD_ABBREV kelimelerinin ilk harften sonraki ünlüleri atılmış biçimleri
 *     ("siktir" → "siktr", "sktir", "sktr"; "bitch" → "btch") yalnız bütün parça olarak eşleşir (parça içinde
 *     "sktir" risktir/asktir/kasktir'i yakalardı); "bi(a)tch" ailesi parça içinde aranır (MOD_CONTAINS_RX).
 *   - Çok anlamlı kelimeler (MOD_HOMONYMS): "got" (göt / İngilizce got), "pic" (piç / picture),
 *     "dick", "isis", "adolf", "kike" gerçek adlarda ya da sıradan İngilizce'de de geçer. Tek başlarına ya da
 *     bilinen masum eşlikçileri olmadan ENGELLENİR; hemen yanında listedeki bir eşlikçi
 *     ("i_got_it", "my_pic", "dick_advocaat", "isis_ay") varsa geçer. Bilinmeyen eşlikçi → engel:
 *     hata yönü güvenli taraf (kullanıcı başka ad seçer); gerçek adlar listeye eklenir.
 *   - Rezerve adlar: uygulamanın kendi etiketleri ("Engellenen oyuncu", "Kayıtlı oyuncu/rakip", "CPU")
 *     ve yöneticinin yeniden adlandırma biçimi "oyuncu_NNNN" (kayıtta "oyuncu_" ile başlayıp rakamla
 *     biten her ad). Etiketler görüntülemede de maskelenir; "oyuncu_NNNN" yalnız kayıtta ayrılır,
 *     yönetici adı verilmiş oyuncular sıralamada adlarıyla görünür ($strict = false).
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

/** Bütün parça olarak eşleşen küfür / cinsel / nefret kelimeleri: önce TR, sonra EN, sonra nefret / terör. */
const MOD_EXACT_TR = [
    'aq', 'amk', 'amq', 'amina', 'anani', 'got', 'gotu', 'gotos', 'sik', 'sikim', 'sikis', 'sktr', 'sktir', 'pic',
    'oc', 'ibne', 'ipne',
    'pust', 'pezo', 'yarak', 'tasak', 'bok', 'salak', 'aptal', 'ahmak', 'gavur', 'sapik', 'seks', 'seksi',
    // yaygın ünlüsüz kısaltmalar: skm = sikim/sikeyim, skrm = sikerim
    'skm', 'skrm',
];
const MOD_EXACT_EN = [
    'fuk', 'fck', 'fuq', 'fack', 'shit', 'shits', 'shitty', 'shitting', 'shitter', 'ass', 'arse', 'dick', 'cock', 'cunt',
    'pussy', 'pussies', 'slut', 'twat', 'prick', 'retard', 'retarded', 'wtf', 'sex', 'sexy', 'xxx', 'nude', 'nudes',
    'boob', 'boobs', 'tits', 'penis', 'vagina', 'vajina', 'horny', 'milf', 'rape', 'rapist', 'pedo',
    // mofo = motherfucker, pron/pr0n = porn, stfu/gtfo kısaltmaları; düzensiz çoğul
    'mofo', 'pron', 'stfu', 'gtfo', 'penises',
];
/** İngilizce küfürlerin düzenli çoğulu (+s): dicks, nazis, mofos… (assess gibi sözcüklere çarpmasın diye liste). */
const MOD_EN_PLURAL = [
    'dick', 'cock', 'cunt', 'slut', 'twat', 'prick', 'retard', 'vagina', 'milf', 'pedo', 'rapist', 'nazi', 'mofo',
    'kike', 'spic', 'chink', 'coon',
];
/** Nefret / terör. */
const MOD_EXACT_HATE = [
    'fag', 'fags', 'kike', 'spic', 'chink', 'coon', 'tranny', 'trannies', 'nazi', 'heil', 'kkk', 'isis', 'isid', 'pkk', 'feto',
    'daes', 'deas', 'adolf',
];
const MOD_EXACT = [...MOD_EXACT_TR, ...MOD_EXACT_EN, ...MOD_EXACT_HATE];
/**
 * Son ünsüzü uzatılınca masum bir sözcüğe dönen kelimeler: "got" → "gott" (Almanca "Tanrı"; "sikk" ile
 * aynı kuralla eşleşse masum "gott" da engellenirdi). Bunlar yalnız kendi biçimleriyle (ve üç+ harf
 * uzatmayla) eşleşir.
 */
const MOD_EXACT_NOSTRETCH = ['got'];

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
/**
 * Ünlüsüz kısaltması da aranan kelimeler: ilk harften sonraki ünlüler isteğe bağlı atılır, en az 4 harf kalır
 * ("siktir" → sktir, siktr, sktr; "bitch" → btch). Kısaltmalar yalnız BÜTÜN PARÇA eşleşir: "sktir" parça içinde
 * aransa risktir, asktir, kasktir ("-tir" ekli yaygın sözcükler) engellenirdi.
 */
const MOD_ABBREV = ['siktir', 'bitch'];
/** Hazır regex aileleri (parça içinde aranır): bitch, biatch, biotch, bytch, biyatch. */
const MOD_CONTAINS_RX = ['b[iy]+[aeoy]{0,2}t+c+h+'];

/**
 * Türkçe küfür kökü + çekim/türetme eki; bütün parça olarak aranır (MOD_EXACT gibi). kök => [yumuşak kök
 * ya da '', ek kümeleri]. Yumuşak kök ünlüyle başlayan eklerde kullanılır (salak → salağı = "salag"+"i").
 * Ek kümeleri MOD_TR_SUFFIX'te; her kök yalnız güvenli kümeleri alır: "sik" köküne çıplak "i/e/a" eklemek
 * şike, şikayet, sıkı, sıkıntı gibi masum sözcükleri yakalardı (ı/ş katlanır), o yüzden "sik" yalnız iyelik+hâl
 * ve çoğul alır; "boku" (Japonca "ben"), "siki" (sıkı), "sikin" (sıkın) geçer.
 */
const MOD_TR_ROOTS = [
    'sik'   => ['', ['pl', 'poss_n']],
    'got'   => ['', ['pl', 'poss']],
    'bok'   => ['', ['pl', 'lik', 'li', 'poss', 'abl']],
    'pic'   => ['', ['pl', 'lik']],
    'pust'  => ['', ['pl', 'lik', 'cop']],
    'gavur' => ['', ['pl', 'lik', 'cop']],
    'pezo'  => ['', ['pl', 'lik', 'cop', 'vf']],
    'ipne'  => ['', ['pl', 'lik', 'cop', 'ca', 'vf']],
    'aptal' => ['', ['pl', 'lik', 'cop', 'ca', 'poss', 'vow']],
    'salak' => ['salag', ['pl', 'lik', 'cop', 'ca', 'poss', 'vow']],
    'ahmak' => ['ahmag', ['pl', 'lik', 'cop', 'ca', 'poss', 'vow']],
    'sapik' => ['sapig', ['pl', 'lik', 'cop', 'ca', 'poss', 'vow']],
    'yarak' => ['yarag', ['pl', 'poss', 'vow']],
    'tasak' => ['tasag', ['pl', 'poss', 'vow']],
];
/**
 * Ek kalıpları: A = a/e, I = i/u (ı ve ü katlandığı için; ünlü uyumu aşırı üretilir, zararsız).
 * pl çoğul(+iyelik/hâl) · lik -lık/-lik/-luk/-lük · li -lı/-li · cop -sın/-sin/-sun/-sün, -dır/-tir (salaksin) ·
 * poss iyelik(+hâl): gotum, gotunu, gotune · poss_n çıplak "-in" hariç · vow çıplak -ı/-a (yalnız yumuşayan
 * köklerde güvenli: "salagi", "sapigi") · abl -tan/-ten (boktan) · ca -ca/-ce (salakca, aptalca) ·
 * vf ünlüyle biten köklerde iyelik/hâl (ipnesi, ipneyim). "ipne" ("ibne" gibi parça içinde aranmaz: peripneumonia gibi
 * tıp terimlerini yakalardı) bu yüzden kök olarak çekimlenir.
 */
const MOD_TR_SUFFIX = [
    'pl'     => ['lAr', 'lArI', 'lArIn', 'lArIm', 'lArInIz', 'lArA', 'lArdA', 'lArdAn', 'lArlA'],
    'lik'    => ['lIk', 'lIgI', 'lIgA', 'lIktAn'],
    'li'     => ['lI'],
    'cop'    => ['sIn', 'sInIz', 'dIr', 'tIr'],
    'poss'   => ['In', 'Im', 'ImI', 'ImA', 'ImdA', 'ImdAn', 'ImlA', 'ImIz', 'InIz', 'InI', 'InA', 'IndA', 'IndAn', 'InlA'],
    'poss_n' => ['Im', 'ImI', 'ImA', 'ImdA', 'ImdAn', 'ImlA', 'ImIz', 'InI', 'InA', 'IndA', 'IndAn', 'InlA'],
    'vow'    => ['I', 'A'],
    'abl'    => ['tAn'],
    'ca'     => ['cA'],
    'vf'     => ['sI', 'yI', 'yA', 'yIm', 'yIz', 'nIn', 'dA', 'dAn', 'lA'],
];

/**
 * Çok anlamlı kelimeler: gerçek adlarda ya da sıradan İngilizce'de de geçer. Yalnız hemen yanındaki parça
 * (önceki ya da sonraki) listedeyse masum sayılır; tek başına ya da başka bir parçayla ENGELLENİR.
 * Hata yönü bilerek güvenli taraf: bilinmeyen eşlikçi → engel, gerçek ad listeye eklenir. İngilizce işlev
 * sözcükleri listesinde Türkçe'de de sözcük olanlar (on, at, in, an, is = iş, be, ya) bilerek yoktur:
 * "on_pic", "at_pic", "ya_got" Türkçe okunabilir.
 */
const MOD_EN_WORDS = [
    'i', 'u', 'you', 'we', 'they', 'he', 'she', 'it', 'who', 'what', 'my', 'your', 'his', 'her', 'our', 'their', 'the',
    'a', 'are', 'was', 'to', 'of', 'for', 'and', 'or', 'not', 'no', 'just', 'this', 'that', 'me', 'us', 'him', 'them',
];
const MOD_HOMONYMS = [
    // "got" göt (TR) / got (EN); "pic" piç (TR) / picture (EN): İngilizce bağlam yanındaki işlev sözcüğüdür
    // ("got" öncesinde özne/yardımcı fiil, sonrasında nesne; "my got" İngilizce değildir).
    'got' => ['i', 'u', 'you', 'we', 'they', 'he', 'she', 'it', 'who', 'what', 'just', 'never', 'not', 'no',
        'have', 'has', 'had', 'me', 'us', 'him', 'her', 'them', 'this', 'that', 'the', 'a', 'milk', 'talent', 'game',
        'skills', 'goals', 'next'],
    'pic' => [...MOD_EN_WORDS, 'profile', 'nice', 'cool', 'best', 'new', 'old', 'good', 'great', 'day', 'selfie'],
    // Gerçek adlar: Dick Advocaat (teknik direktör), Dick van Dyke, Moby Dick…; Isis (ad, tanrıça); Adolf Dassler.
    'dick' => ['advocaat', 'van', 'dyke', 'cheney', 'tracy', 'grayson', 'clark', 'fosbury', 'butkus', 'turpin',
        'whittington', 'dastardly', 'moby', 'cavett', 'jol', 'nanninga', 'schoenaker', 'lukkien', 'kooiman', 'philip'],
    'isis' => ['ay', 'valverde', 'gaston', 'goddess', 'tanrica', 'egypt', 'egyptian', 'misir', 'osiris', 'horus', 'nile'],
    'adolf' => ['dassler', 'hutter'],
    // "Kike" Enrique'nin İspanyolca takma adı (Kike García, Kike Hermoso…).
    'kike' => ['garcia', 'sola', 'salas', 'hermoso', 'perez', 'dominguez', 'vargas', 'setien', 'sanchez', 'mateo'],
];

/** Taklit (resmî hesap izlenimi): parça içinde aranır. */
const MOD_RESERVED = [
    'admin', 'moderator', 'yonetici', 'yetkili', 'official', 'offical', 'apple', 'google', 'gelistirici',
];
/**
 * Taklit: alt çizgisiz adın içinde aranır ("sut_ve_gol", "destek_ekibi"). Son üçü uygulamanın kendi
 * etiketleridir: "Engellenen oyuncu" (engellediğin kişi), "Kayıtlı oyuncu" / "Kayıtlı rakip" (ghost);
 * aynı adı taşıyan gerçek bir oyuncu bu etiketlerle karışırdı.
 */
const MOD_RESERVED_FLAT = [
    'sutvegol', 'globalmedia', 'gmgaming', 'appstore', 'playstore', 'destekekibi', 'destekhatti', 'resmihesap',
    'resmidestek', 'supportteam', 'customersupport', 'customerservice', 'musterihizmet',
    'engellenenoyuncu', 'kayitlioyuncu', 'kayitlirakip',
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
    $contains = mod_contains_words();
    $long = array_values(array_filter($contains, fn($w) => strlen($w) >= 6));
    [$words, $whole, $strict] = match ($list) {
        'contains' => [$contains, false, false],
        'contains_long' => [$long, false, false],
        'reserved' => [MOD_RESERVED, false, false],
        'reserved_whole' => [array_merge(MOD_RESERVED, MOD_RESERVED_FLAT), true, false],
        'reserved_flat' => [MOD_RESERVED_FLAT, false, false],
        'reserved_exact' => [MOD_RESERVED_EXACT, true, true],
    };
    $alt = implode('|', array_map($strict ? 'mod_pattern_strict' : 'mod_pattern', $words));
    // Hazır aileler yalnız parça içinde aranır ("contains_long" adın tamamında parça sınırını aşardı).
    if ($list === 'contains') $alt .= '|' . implode('|', MOD_CONTAINS_RX);
    return $cache[$list] = $whole ? "/^(?:$alt)$/" : "/(?:$alt)/";
}

/** Ünlüsüz kısaltmalar: ilk harften sonraki ünlüler isteğe bağlı atılır ("siktir" → sktir, siktr, sktr). */
function mod_abbrev(string $word): array {
    $vowels = [];
    for ($i = 1; $i < strlen($word); $i++) if (str_contains('aeiou', $word[$i])) $vowels[] = $i;
    $out = [];
    for ($mask = 1; $mask < (1 << count($vowels)); $mask++) {
        $drop = [];
        foreach ($vowels as $k => $pos) if ($mask & (1 << $k)) $drop[$pos] = true;
        $short = '';
        for ($i = 0; $i < strlen($word); $i++) if (!isset($drop[$i])) $short .= $word[$i];
        if (strlen($short) >= 4) $out[] = $short;
    }
    return $out;
}

/** Parça içinde aranan kelimeler: MOD_CONTAINS + "-cık" küçültmesinin ünlü uyumu (amcik → amcuk). */
function mod_contains_words(): array {
    static $words = null;
    if ($words !== null) return $words;
    $words = MOD_CONTAINS;
    foreach (MOD_CONTAINS as $w) {
        if (str_contains($w, 'cik') || str_contains($w, 'cig')) $words[] = strtr($w, ['cik' => 'cuk', 'cig' => 'cug']);
    }
    return $words = array_values(array_unique($words));
}

/** MOD_TR_ROOTS × MOD_TR_SUFFIX: bütün kök+ek biçimleri (A = a/e, I = i/u açılmış). */
function mod_tr_forms(): array {
    static $forms = null;
    if ($forms !== null) return $forms;
    $out = [];
    foreach (MOD_TR_ROOTS as $root => [$soft, $sets]) {
        foreach ($sets as $set) {
            foreach (MOD_TR_SUFFIX[$set] as $suffix) {
                // Ünlüyle başlayan ekte yumuşak kök kullanılır ("salagim"); yumuşatmasız "salaka" (şaka) ve "yaraki"
                // gibi sözcükleri yakalamamak için "salakim" yazımı bilerek aranmaz.
                $stems = [$soft !== '' && str_contains('AIaeiou', $suffix[0]) ? $soft : (string) $root];
                $variants = [''];
                foreach (str_split($suffix) as $ch) {
                    $options = $ch === 'A' ? ['a', 'e'] : ($ch === 'I' ? ['i', 'u'] : [$ch]);
                    $next = [];
                    foreach ($variants as $v) foreach ($options as $o) $next[] = $v . $o;
                    $variants = $next;
                }
                foreach ($stems as $stem) foreach ($variants as $v) $out[$stem . $v] = true;
            }
        }
    }
    return $forms = array_map('strval', array_keys($out));
}

/**
 * Bütün parça eşleşme tabloları: [tüm biçimler, son ünsüzü uzatılabilenler]. Tüm biçimler = MOD_EXACT
 * + ünlüsüz kısaltmalar (MOD_ABBREV) + Türkçe kök×ek biçimleri + MOD_EN_PLURAL çoğulları (dicks, nazis).
 * Çoğullar uzatılamaz: "assess" son ünsüzü kısalınca "asses" olurdu.
 */
function mod_exact_tables(): array {
    static $tables = null;
    if ($tables !== null) return $tables;
    $base = array_fill_keys(MOD_EXACT, true);
    foreach (mod_tr_forms() as $w) $base[$w] = true;
    foreach (MOD_ABBREV as $w) foreach (mod_abbrev($w) as $short) $base[$short] = true;
    $all = $base;
    foreach (MOD_EN_PLURAL as $w) $all[$w . 's'] = true;
    return $tables = [$all, array_diff_key($base, array_fill_keys(MOD_EXACT_NOSTRETCH, true))];
}

/**
 * Bütün parça kelimeleri için tekrar inceltme. Dönüş: [yığınları inceltilmiş biçimler (kendisi dahil),
 * bunların son ünsüz yığını kısaltılmış biçimleri]. En az üç harflik yığın tek harfe (dört ve üzeriyse iki
 * harfe de) iner; iki harflik yığına dokunulmaz ("book", "mass", "sikkim"). Yalnız SON ünsüz yığını her
 * uzunlukta kısalır ("sikk" → "sik"); uç harfi uzatmak yaygın, içteki çift harf ise çoğu zaman bir sözcüktür.
 */
function mod_destretch(string $u): array {
    preg_match_all('/(.)\1*/', $u, $m);
    $bases = [''];
    foreach ($m[0] as $run) {
        $n = strlen($run); $c = $run[0];
        $options = $n >= 4 ? [$run, $c, $c . $c] : ($n === 3 ? [$run, $c] : [$run]);
        $next = [];
        foreach ($bases as $b) foreach ($options as $o) $next[] = $b . $o;
        $bases = $next;
    }
    $finals = [];
    foreach ($bases as $b) {
        if (!preg_match('/([^aeiou])\1+$/', $b, $tail)) continue;
        $stem = substr($b, 0, strlen($b) - strlen($tail[0]));
        for ($k = 1; $k < strlen($tail[0]); $k++) $finals[] = $stem . str_repeat($tail[1], $k);
    }
    return [$bases, $finals];
}

/** Bütün parça eşleşmesi: eşleşen liste kelimesi ya da null. */
function mod_exact_match(string $u): ?string {
    [$all, $stretch] = mod_exact_tables();
    [$bases, $finals] = mod_destretch($u);
    foreach ($bases as $b) if (isset($all[$b])) return (string) $b;
    foreach ($finals as $f) if (isset($stretch[$f])) return (string) $f;
    return null;
}

/** Çok anlamlı kelime ($word) için hemen yanındaki parçalardan biri listedeki masum eşlikçi mi? */
function mod_homonym_ok(array $tokens, int $i, string $word): bool {
    $partners = MOD_HOMONYMS[$word] ?? null;
    return $partners !== null
        && (in_array($tokens[$i - 1] ?? '', $partners, true) || in_array($tokens[$i + 1] ?? '', $partners, true));
}

function mod_strip_allowed(string $s): string {
    return str_replace(MOD_ALLOW, '', $s);
}

/**
 * Adı başka oyunculara gösterilemez kılan sebep: 'profanity' (küfür/hakaret/cinsel/nefret),
 * 'impersonation' (resmî hesap / uygulama etiketi taklidi) ya da uygunsa null.
 * $strict (varsayılan): kayıt kuralı; "oyuncu_" ile başlayıp rakamla biten adlar da rezervedir (yönetici
 * yeniden adlandırması "oyuncu_NNNN" üretir). Görüntüleme maskesi $strict = false ile çağırır: yönetici
 * adı verilmiş oyuncular sıralamada adlarıyla görünür.
 */
function mod_name_reason(string $name, bool $strict = true): ?string {
    if ($strict && preg_match('/^[o0]yuncu_.*[0-9]$/', mod_fold($name))) return 'impersonation';
    foreach (mod_forms($name) as $tokens) {
        if (!$tokens) continue;
        $flat = implode('', $tokens);
        $merged = mod_merge_singles($tokens);
        // Bütün parça birimleri sırayla: parçalar (komşuluk bilgisiyle), birleşen tek harfler, adın tamamı.
        $whole = [];
        foreach ($tokens as $i => $t) $whole[] = [$t, $i];
        foreach ($merged as $t) $whole[] = [$t, null];
        $whole[] = [$flat, null];
        foreach ($whole as [$u, $i]) {
            $word = mod_exact_match($u);
            if ($word !== null && !($i !== null && mod_homonym_ok($tokens, $i, $word))) return 'profanity';
            if (preg_match(mod_regex('reserved_exact'), $u)) return 'impersonation';
        }
        $units = array_values(array_unique(array_merge($tokens, $merged)));
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

/** Kayıt, ad seçimi ve /v1/username/check ortak kuralı: [kod, mesaj] ya da uygunsa null (rezerve adlar dahil, $strict). */
function username_issue(string $name): ?array {
    if (!valid_username($name)) return ['invalid_username', USERNAME_INVALID];
    if (mod_name_reason($name, true) !== null || name_banned($name)) return ['username_not_allowed', USERNAME_NOT_ALLOWED];
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
        $isHidden = ($flags[$id]['hidden'] ?? false) || (!$cleared && $name !== null && mod_name_reason((string) $name, false) !== null);
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
