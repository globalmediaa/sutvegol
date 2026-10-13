#!/usr/bin/env python3
"""Oyuncu güvenliği (build 13, App Store 1.2) gerçek PHP/MySQL testleri.

Kendi tek kullanımlık test DB'sini canlıdaki gibi utf8mb4_0900_ai_ci varsayılanıyla açar
(users.username ile karşılaştırılan sütunlarda harmanlama karışımı burada patlar), API için
`php -S backend/public`, yönetim paneli için ikinci bir `php -S backend/admin` başlatır.
Kapsam: kullanıcı adı filtresi (kayıt, /v1/username/check, sosyal ad seçimi) + koşul sürümü,
şikâyet doğrulaması / idempotentlik / günlük sınır / 410, 3 şikâyette "Oyuncu#XXXX" gizleme
(sıralama + canlı düello), eski uygunsuz adın maskelenmesi, engelleme (liste, sıralama etiketi,
iki yönlü eşleşme, rövanş, kayıtlı rakip havuzu), ghost sahibine şikâyet bağlamı, yönetici
CSRF + reddet / zorla yeniden adlandır (name_bans) / askıya al / askıyı kaldır, hesap silmede
şikâyet/engel temizliği ve migration'ın yeniden uygulanabilmesi. Canlı sunucuya bağlanmaz.
Çalıştırma: SV_PHP=/usr/local/opt/php@8.4/bin/php python3 backend/tests/moderation_test.py
"""
import http.cookiejar
import re
import subprocess
import unittest
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

from harness import PHP, ROOT, Server, V2Run, mysql, reset_schema

Q = {'duelVersion': 2}
NOW = "UNIX_TIMESTAMP(NOW(3))*1000"
ADMIN_EMAIL = 'moderator@test.local'
ADMIN_PASS = 'admin-pass-123'


def last(sql):
    out = mysql(sql).strip().splitlines()
    return out[-1] if out else ''


class Admin:
    """Yönetim paneli istemcisi: oturum çerezi + sayfadan okunan CSRF anahtarı."""

    def __init__(self, base):
        self.base, self.token = base, None
        self.opener = urllib.request.build_opener(urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar()))

    def request(self, data=None):
        body = None if data is None else urllib.parse.urlencode(data).encode()
        req = urllib.request.Request(self.base + '/', data=body, method='GET' if data is None else 'POST')
        try:
            with self.opener.open(req, timeout=15) as r:
                status, html = r.status, r.read().decode()
        except urllib.error.HTTPError as e:
            status, html = e.code, e.read().decode(errors='replace')
            e.close()
        m = re.search(r'name="csrf" value="([0-9a-f]{64})"', html)
        if m:
            self.token = m.group(1)
        return status, html

    def login(self, csrf=True):
        self.request()
        data = {'email': ADMIN_EMAIL, 'password': ADMIN_PASS}
        if csrf:
            data['csrf'] = self.token
        return self.request(data)

    def act(self, action, target, csrf=True):
        data = {'action': action, 'target': target}
        if csrf:
            data['csrf'] = self.token
        return self.request(data)


class Moderation(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        reset_schema('utf8mb4_0900_ai_ci')
        pw = subprocess.run([PHP, '-r', 'echo password_hash($argv[1], PASSWORD_DEFAULT);', '--', ADMIN_PASS],
                            capture_output=True, text=True, check=True).stdout.strip()
        cls.server = Server(); cls.s = cls.server.__enter__()
        cls.admin_server = Server(docroot='admin', env={'ADMIN_EMAIL': ADMIN_EMAIL, 'ADMIN_PASSWORD_HASH': pw})
        cls.admin_server.__enter__()
        cls.u = {n: cls.s.register('mo_' + n) for n in
                 ['ana', 'bek', 'cem', 'dua', 'ece', 'fat', 'gul', 'han', 'hedef', 'gizli', 'spam', 'sahip',
                  'seyirci', 'rakip', 'rezil', 'cezali', 'silinen', 'x1', 'kuk1', 'kuk2', 'kuk3']}

    @classmethod
    def tearDownClass(cls):
        cls.admin_server.__exit__()
        cls.server.__exit__()

    def setUp(self):
        # Testler IP başı sınırlara ve birbirlerinin kuyruğuna takılmasın.
        mysql("DELETE FROM api_rate_limits; DELETE FROM duel_queue;")

    # ----------------------------------------------------------- yardımcılar
    def tok(self, who):
        return self.u[who]['token']

    def pid(self, who):
        return self.u[who]['user']['id']

    def uid(self, who):
        return last(f"SELECT id FROM users WHERE public_id='{self.pid(who)}'")

    def register(self, name, **extra):
        mysql("DELETE FROM api_rate_limits")
        return self.s.post('/v1/auth/register', dict(email=f'{name.lower()}@x.local', password='password1', username=name, **extra))

    def report(self, who, target, reason='username', context='leaderboard', **extra):
        mysql("DELETE FROM api_rate_limits")
        return self.s.post('/v1/report', dict(target_user_id=target, reason=reason, context=context, **extra), self.tok(who))

    def board(self, who=None):
        s, r = self.s.get('/v1/leaderboard?period=all', self.tok(who) if who else None)
        self.assertEqual(s, 200, r)
        return {e['id']: e for e in r['entries']}

    def play(self, who, hits=2):
        s, g = self.s.post('/v1/games', {'version': '1.0.0'}, self.tok(who)); self.assertEqual(s, 201, g)
        s, r = self.s.post(f"/v1/games/{g['sessionId']}/finish", dict(
            nonce=g['nonce'], score=30 * hits, shots=hits, hits=hits, misses=0, feverHits=0, maxStreak=hits,
            durationMs=6000, stage='street'), self.tok(who))
        self.assertTrue(r.get('accepted'), r)

    def queue(self, who):
        return self.s.post('/v1/duels/queue', Q, self.tok(who))

    def pair(self, a, b):
        self.assertEqual(self.queue(a)[1]['status'], 'waiting')
        s, r = self.queue(b); self.assertEqual(s, 200, r)
        self.assertIn('duel', r, r)
        return r['duel']

    def forfeit(self, who, duel_id):
        self.s.post(f'/v1/duels/{duel_id}/forfeit', {}, self.tok(who))

    def recorded_run(self, owner, opponent, shots=4):
        """`owner` için kayıtlı rakip havuzuna girecek bitmiş, tam süreli v2 koşusu."""
        d = self.pair(owner, opponent)
        id = d['id']
        nonce = self.s.get(f'/v1/duels/{id}', self.tok(owner))[1]['duel']['nonce']
        run = V2Run()
        events = [run.event() for _ in range(shots)]
        at = max(e['rt'] for e in events) + 300
        mysql(f"UPDATE duels SET starts_at_ms={NOW}-{at},ends_at_ms={NOW}+{90000 - at} WHERE id='{id}'")
        s, r = self.s.post(f'/v1/duels/{id}/events', dict(nonce=nonce, events=events), self.tok(owner))
        self.assertEqual(s, 200, r)
        mysql(f"UPDATE duels SET ends_at_ms={NOW}-9000 WHERE id='{id}'")
        snap = self.s.get(f'/v1/duels/{id}', self.tok(owner))[1]['duel']
        self.assertEqual((snap['status'], snap['result']['reason']), ('finished', 'time'))
        return id

    def ghost_duel(self, who):
        self.assertEqual(self.queue(who)[1]['status'], 'waiting')
        mysql(f"UPDATE duel_queue SET joined_ms={NOW}-16000 WHERE user_id={self.uid(who)}")
        s, r = self.queue(who); self.assertEqual(s, 200, r)
        self.assertEqual(r['duel']['kind'], 'ghost')
        return r['duel']

    # ----------------------------------------------------------- testler
    def test_00_php_unit(self):
        out = subprocess.run([PHP, str(Path(__file__).with_name('moderation_unit_test.php'))], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)

    def test_01_username_filter_register_and_check(self):
        for bad in ['orospu_cocugu', 's1kt1r', 'sutvegol_destek', 'Admin', 'mod']:
            s, r = self.register(bad)
            self.assertEqual((s, r['error']['code']), (422, 'username_not_allowed'), bad)
            self.assertIn('uygun değil', r['error']['message'])
        s, r = self.register('ab')
        self.assertEqual((s, r['error']['code']), (422, 'invalid_username'))
        s, r = self.s.get('/v1/username/check?username=s1kt1r')
        self.assertEqual((r['valid'], r['allowed'], r['available'], r['code']), (True, False, False, 'username_not_allowed'))
        s, r = self.s.get('/v1/username/check?username=temiz_ad')
        self.assertEqual((r['valid'], r['allowed'], r['available']), (True, True, True))
        self.assertNotIn('code', r)
        s, r = self.s.get('/v1/username/check?username=MO_ANA')
        self.assertEqual((r['allowed'], r['available']), (True, False))
        # Koşul sürümü sunucuda saklanır; bilinmeyen sürüm saklanmaz.
        s, r = self.register('mo_onayli', termsVersion=1)
        self.assertEqual((s, r['user']['termsVersion']), (200, 1), r)
        self.assertNotEqual(last("SELECT terms_accepted_at FROM users WHERE username='mo_onayli'"), 'NULL')
        s, r = self.register('mo_eski', termsVersion=99)
        self.assertEqual((s, r['user']['termsVersion']), (200, 0), r)
        self.assertEqual(self.s.get('/v1/me', r['accessToken'])[1]['user']['termsVersion'], 0)

    def test_02_choose_username_social_flow(self):
        u = self.s.register('mo_sosyal')
        mysql("UPDATE users SET username=NULL,username_key=NULL WHERE username='mo_sosyal'")
        for bad in ['admin_tr', 'ibne', 'g00gle']:
            s, r = self.s.put('/v1/me/username', dict(username=bad), u['token'])
            self.assertEqual((s, r['error']['code']), (422, 'username_not_allowed'), bad)
        s, r = self.s.put('/v1/me/username', dict(username='temiz_sosyal', termsVersion=1), u['token'])
        self.assertEqual((s, r['user']['username'], r['user']['termsVersion']), (200, 'temiz_sosyal', 1), r)

    def test_03_report_validation_idempotency_and_gone(self):
        target = self.pid('hedef')
        self.assertEqual(self.s.post('/v1/report', dict(target_user_id=target, reason='username', context='duel'))[0], 401)
        for body, code in [(dict(target_user_id='nope', reason='username', context='duel'), 'invalid_target'),
                           (dict(target_user_id=target, reason='spam', context='duel'), 'invalid_reason'),
                           (dict(target_user_id=target, reason='username', context='chat'), 'invalid_context'),
                           (dict(target_user_id=target, reason='other', context='duel', note=5), 'invalid_note'),
                           (dict(target_user_id=target, reason='other', context='duel', duel_id='x' * 32), 'invalid_duel'),
                           (dict(target_user_id=target, reason='other', context='duel', duel_id='a' * 32), 'invalid_duel'),
                           (dict(target_user_id=self.pid('ana'), reason='other', context='duel'), 'cannot_report_self')]:
            mysql("DELETE FROM api_rate_limits")
            s, r = self.s.post('/v1/report', body, self.tok('ana'))
            self.assertEqual((s, r['error']['code']), (422, code), body)
        note = '  hile\x00 yapıyor  ' + 'ş' * 400
        s, r = self.report('ana', target, 'username', 'leaderboard', note=note)
        self.assertEqual((s, r['reported']), (200, True), r)
        s, r = self.report('ana', target.lower(), 'cheating', 'duel')  # küçük harf kimlik de kabul
        self.assertEqual(s, 200, r)
        row = mysql(f"SELECT reason,context,reported_name,status,CHAR_LENGTH(COALESCE(note,'')) FROM user_reports WHERE target_id={self.uid('hedef')}").strip().splitlines()
        self.assertEqual(len(row), 2)  # başlık + tek satır (idempotent)
        self.assertEqual(row[1].split('\t'), ['cheating', 'duel', 'mo_hedef', 'open', '0'])
        s, r = self.report('ana', target, 'other', 'leaderboard', note=note)
        self.assertEqual(int(last(f"SELECT CHAR_LENGTH(note) FROM user_reports WHERE target_id={self.uid('hedef')}")), 200)
        self.assertTrue(last(f"SELECT note FROM user_reports WHERE target_id={self.uid('hedef')}").startswith('hile yapıyor ş'))
        # Hedef hesabını sildiyse 410 (istemci "artık yok" der).
        gone = self.s.register('mo_gidici')
        self.assertEqual(self.s.delete('/v1/me', {}, gone['token'])[0], 200)
        s, r = self.report('bek', gone['user']['id'])
        self.assertEqual((s, r['error']['code']), (410, 'player_gone'))
        s, r = self.s.post('/v1/blocks', dict(user_id=gone['user']['id']), self.tok('bek'))
        self.assertEqual((s, r['error']['code']), (410, 'player_gone'))

    def test_04_report_daily_limit(self):
        targets = [self.s.register(f'mo_t{i:02d}')['user']['id'] for i in range(21)]
        for t in targets[:20]:
            self.assertEqual(self.report('spam', t)[0], 200)
        s, r = self.report('spam', targets[20])
        self.assertEqual((s, r['error']['code']), (429, 'report_limit'))
        self.assertEqual(self.report('spam', targets[3], 'cheating')[0], 200)  # aynı hedef sayılmaz
        self.assertEqual(last(f"SELECT COUNT(*) FROM user_reports WHERE reporter_id={self.uid('spam')}"), '20')
        # Reddedilmiş kaydı sebep değiştirerek yeniden açmak yeni şikâyet sayılır (sınırda 429).
        mysql(f"UPDATE user_reports SET status='dismissed' WHERE reporter_id={self.uid('spam')} AND target_id=(SELECT id FROM users WHERE public_id='{targets[5]}')")
        s, r = self.report('spam', targets[5], 'other')
        self.assertEqual((s, r['error']['code']), (429, 'report_limit'))
        mysql(f"UPDATE user_reports SET created_at=DATE_SUB(NOW(),INTERVAL 2 DAY) WHERE reporter_id={self.uid('spam')}")
        self.assertEqual(self.report('spam', targets[5], 'other')[0], 200)
        self.assertEqual(last(f"SELECT CONCAT(status,'|',created_at>DATE_SUB(NOW(),INTERVAL 1 HOUR)) FROM user_reports WHERE reporter_id={self.uid('spam')} AND target_id=(SELECT id FROM users WHERE public_id='{targets[5]}')"), 'open|1')

    def test_05_three_username_reports_hide_name(self):
        self.play('gizli'); self.play('rakip')
        target = self.pid('gizli'); label = 'Oyuncu#' + target[:4]
        self.assertEqual(self.board()[target]['username'], 'mo_gizli')
        self.report('ana', target); self.report('bek', target); self.report('cem', target, 'cheating')
        self.assertEqual(self.board()[target]['username'], 'mo_gizli')  # 2 ad şikâyeti + 1 hile: görünür
        self.report('dua', target)
        self.assertEqual(self.board()[target]['username'], label)        # misafir
        self.assertEqual(self.board('ana')[target]['username'], label)   # şikâyet eden
        self.assertEqual(self.board('gizli')[target]['username'], 'mo_gizli')  # kendisi
        # Canlı düello rakip bilgisi de gizli ad gösterir; oyuncu kendi adını görür.
        d = self.pair('gizli', 'rakip')
        names = {p['id']: p['username'] for p in d['players']}
        self.assertEqual(names[target], label)
        mine = {p['id']: p['username'] for p in self.s.get(f"/v1/duels/{d['id']}", self.tok('gizli'))[1]['duel']['players']}
        self.assertEqual(mine[target], 'mo_gizli')
        self.forfeit('rakip', d['id'])
        # Yönetici reddederse ad geri gelir; aynı kişi aynı ad + sebeple yeniden açamaz.
        admin = Admin(self.admin_server.base); admin.login()
        status, html = admin.act('dismiss', target)
        self.assertEqual(status, 200); self.assertIn('şikâyet reddedildi', html)
        self.assertEqual(self.board()[target]['username'], 'mo_gizli')
        self.report('ana', target)
        self.assertEqual(last(f"SELECT status FROM user_reports WHERE reporter_id={self.uid('ana')} AND target_id={self.uid('gizli')}"), 'dismissed')
        # Onaylanan ad: sebep değiştirip geri dönmek ya da 3 yeni (sahte) hesap adı yeniden gizleyemez.
        self.report('ana', target, 'other'); self.report('ana', target, 'username')
        for who in ['kuk1', 'kuk2', 'kuk3']:
            self.report(who, target)
        self.assertEqual(self.board()[target]['username'], 'mo_gizli')
        status, html = admin.request()
        self.assertIn('Ad onaylandı', html.split('@mo_gizli')[1][:200])
        # Ad değişince onay düşer: yeni ad yine 3 şikâyetle gizlenebilir.
        mysql(f"UPDATE users SET username='mo_gizli2',username_key='mo_gizli2' WHERE public_id='{target}'")
        for who in ['kuk1', 'kuk2', 'kuk3']:
            self.report(who, target)
        self.assertEqual(self.board()[target]['username'], label)
        mysql(f"UPDATE users SET username='mo_gizli',username_key='mo_gizli' WHERE public_id='{target}'")

    def test_05b_leaderboard_ignores_stale_tokens_and_terms_endpoint(self):
        # Bozuk ya da silinmiş hesabın anahtarı sıralamayı kırmaz (anonim görünüm).
        s, r = self.s.get('/v1/leaderboard?period=all', 'bozuk.anahtar.degeri')
        self.assertEqual(s, 200, r)
        gone = self.s.register('mo_eski_oturum')
        self.s.delete('/v1/me', {}, gone['token'])
        self.assertEqual(self.s.get('/v1/leaderboard?period=all', gone['token'])[0], 200)
        self.assertEqual(self.s.get('/v1/me', gone['token'])[0], 401)  # korumalı uçlar yine 401
        # Mevcut hesap koşulları uygulamada bir kez onaylar: POST /v1/me/terms.
        self.assertEqual(self.s.get('/v1/me', self.tok('han'))[1]['user']['termsVersion'], 0)
        s, r = self.s.post('/v1/me/terms', dict(termsVersion=7), self.tok('han'))
        self.assertEqual((s, r['error']['code']), (422, 'invalid_terms'))
        s, r = self.s.post('/v1/me/terms', dict(termsVersion=1), self.tok('han'))
        self.assertEqual((s, r['termsVersion']), (200, 1), r)
        self.assertEqual(self.s.get('/v1/me', self.tok('han'))[1]['user']['termsVersion'], 1)
        self.assertEqual(self.s.post('/v1/me/terms', dict(termsVersion=1))[0], 401)

    def test_06_legacy_offensive_name_is_masked(self):
        # Filtreden önce alınmış uygunsuz ad: başkalarına "Oyuncu#XXXX", sahibine kendi adı.
        legacy = self.s.register('mo_legacy')
        mysql("UPDATE users SET username='siktir_lan',username_key='siktir_lan' WHERE username='mo_legacy'")
        s, g = self.s.post('/v1/games', {'version': '1.0.0'}, legacy['token'])
        self.s.post(f"/v1/games/{g['sessionId']}/finish", dict(nonce=g['nonce'], score=30, shots=1, hits=1, misses=0,
                    feverHits=0, maxStreak=1, durationMs=4000, stage='street'), legacy['token'])
        pid = legacy['user']['id']
        self.assertEqual(self.board()[pid]['username'], 'Oyuncu#' + pid[:4])
        self.assertEqual(self.board('ana')[pid]['username'], 'Oyuncu#' + pid[:4])
        own = {e['id']: e for e in self.s.get('/v1/leaderboard?period=all', legacy['token'])[1]['entries']}
        self.assertEqual(own[pid]['username'], 'siktir_lan')

    def test_07_blocks_leaderboard_and_matchmaking(self):
        self.play('bek'); self.play('ece')
        bek = self.pid('bek')
        self.assertEqual(self.s.post('/v1/blocks', dict(user_id=bek))[0], 401)
        s, r = self.s.post('/v1/blocks', dict(user_id=self.pid('ana')), self.tok('ana'))
        self.assertEqual((s, r['error']['code']), (422, 'cannot_block_self'))
        s, r = self.s.post('/v1/blocks', dict(user_id='123'), self.tok('ana'))
        self.assertEqual((s, r['error']['code']), (422, 'invalid_target'))
        for _ in range(2):  # idempotent
            s, r = self.s.post('/v1/blocks', dict(user_id=bek), self.tok('ana')); self.assertEqual((s, r['blocked']), (200, True))
        s, r = self.s.get('/v1/blocks', self.tok('ana'))
        self.assertEqual([(b['id'], b['name']) for b in r['blocks']], [(bek, 'mo_bek')])
        self.assertRegex(r['blocks'][0]['blockedAt'], r'^\d{4}-\d\d-\d\dT')
        self.assertEqual((self.board('ana')[bek]['username'], self.board('ana')[bek]['blocked']), ('Engellenen oyuncu', True))
        self.assertEqual((self.board('cem')[bek]['username'], self.board('cem')[bek]['blocked']), ('mo_bek', False))
        self.assertEqual(self.board()[bek]['username'], 'mo_bek')
        # Eşleşme iki yönlü: ana ↔ bek eşleşmez; cem gelince bekleyen ana ile eşleşir.
        self.assertEqual(self.queue('ana')[1]['status'], 'waiting')
        self.assertEqual(self.queue('bek')[1]['status'], 'waiting')
        s, r = self.queue('cem'); self.assertIn('duel', r, r)
        ids = sorted(p['id'] for p in r['duel']['players'])
        self.assertEqual(ids, sorted([self.pid('ana'), self.pid('cem')]))
        self.forfeit('cem', r['duel']['id'])
        mysql("DELETE FROM duel_queue")
        # Engellenen taraf engelleyeni de bulamaz (dua → ece engeli, ece kuyruğa önce girer).
        self.assertEqual(self.s.post('/v1/blocks', dict(user_id=self.pid('ece')), self.tok('dua'))[0], 200)
        self.assertEqual(self.queue('ece')[1]['status'], 'waiting')
        self.assertEqual(self.queue('dua')[1]['status'], 'waiting')
        mysql("DELETE FROM duel_queue")
        # Engel kalkınca eşleşirler ve ad geri gelir.
        s, r = self.s.delete(f'/v1/blocks/{bek}', {}, self.tok('ana')); self.assertEqual((s, r['blocked']), (200, False))
        self.assertEqual(self.s.delete(f'/v1/blocks/{bek}', {}, self.tok('ana'))[0], 200)  # idempotent
        self.assertEqual(self.s.get('/v1/blocks', self.tok('ana'))[1]['blocks'], [])
        self.assertEqual(self.board('ana')[bek]['username'], 'mo_bek')
        d = self.pair('ana', 'bek')
        # Maç bitince engel: rövanş kapanır.
        self.forfeit('bek', d['id'])
        self.assertIsNotNone(self.s.get(f"/v1/duels/{d['id']}", self.tok('ana'))[1]['duel']['rematch'])
        self.s.post('/v1/blocks', dict(user_id=bek), self.tok('ana'))
        self.assertIsNone(self.s.get(f"/v1/duels/{d['id']}", self.tok('bek'))[1]['duel']['rematch'])
        s, r = self.s.post(f"/v1/duels/{d['id']}/rematch", {}, self.tok('bek'))
        self.assertEqual((s, r['error']['code']), (409, 'rematch_unavailable'))
        self.s.delete(f'/v1/blocks/{bek}', {}, self.tok('ana'))
        self.s.delete(f"/v1/blocks/{self.pid('ece')}", {}, self.tok('dua'))

    def test_08_ghost_owner_report_and_block(self):
        mysql("UPDATE duels SET created_at=DATE_SUB(NOW(),INTERVAL 40 DAY) WHERE status='finished'")
        run_id = self.recorded_run('sahip', 'fat')
        g = self.ghost_duel('seyirci')
        ghost = next(p for p in g['players'] if p['ghost'])
        self.assertEqual((g['ghost']['source'], ghost['username'], ghost['ownerId']), ('recorded', 'mo_sahip', self.pid('sahip')))
        s, r = self.report('seyirci', ghost['ownerId'], 'cheating', 'ghost', duel_id=g['id'])
        self.assertEqual(s, 200, r)
        s, r = self.report('seyirci', self.pid('fat'), 'cheating', 'ghost', duel_id=g['id'])
        self.assertEqual((s, r['error']['code']), (422, 'invalid_duel'))
        # Canlı düello bağlamı: hedef o maçın rakibi olmalı.
        s, r = self.report('fat', self.pid('sahip'), 'other', 'duel', duel_id=run_id); self.assertEqual(s, 200, r)
        s, r = self.report('fat', self.pid('cem'), 'other', 'duel', duel_id=run_id)
        self.assertEqual((s, r['error']['code']), (422, 'invalid_duel'))
        # Maç sırasında engel: ad "Engellenen oyuncu"; sonraki kayıtlı rakip o oyuncunun koşusu olmaz.
        self.s.post('/v1/blocks', dict(user_id=self.pid('sahip')), self.tok('seyirci'))
        snap = self.s.get(f"/v1/duels/{g['id']}", self.tok('seyirci'))[1]['duel']
        ghost = next(p for p in snap['players'] if p['ghost'])
        self.assertEqual((ghost['username'], ghost['blocked']), ('Engellenen oyuncu', True))
        self.forfeit('seyirci', g['id'])
        g2 = self.ghost_duel('seyirci')
        self.assertEqual(g2['ghost']['source'], 'cpu')
        self.assertIsNone(next(p for p in g2['players'] if p['ghost'])['ownerId'])
        self.forfeit('seyirci', g2['id'])
        # Engellenen taraf da engelleyenin koşusunu görmez (iki yönlü).
        self.recorded_run('seyirci', 'gul')
        g3 = self.ghost_duel('sahip')
        owner = next(p for p in g3['players'] if p['ghost'])['ownerId']
        self.assertNotEqual(owner, self.pid('seyirci'))
        self.forfeit('sahip', g3['id'])
        self.s.delete(f"/v1/blocks/{self.pid('sahip')}", {}, self.tok('seyirci'))

    def test_09_admin_csrf_rename_and_suspend(self):
        admin = Admin(self.admin_server.base)
        status, _ = admin.login(csrf=False)
        self.assertEqual(status, 403)
        status, html = admin.login()
        self.assertEqual(status, 200); self.assertIn('Açık şikâyetler', html)
        rezil = self.pid('rezil')
        for who in ['ana', 'bek', 'cem']:
            self.report(who, rezil)
        status, html = admin.request()
        self.assertIn('@mo_rezil', html); self.assertIn('Ad gizli', html)
        status, _ = admin.act('rename', rezil, csrf=False)
        self.assertEqual(status, 403)
        self.assertEqual(last(f"SELECT username FROM users WHERE public_id='{rezil}'"), 'mo_rezil')
        status, html = admin.act('rename', rezil)
        self.assertEqual(status, 200); self.assertIn('→ @oyuncu_', html)
        new = last(f"SELECT username FROM users WHERE public_id='{rezil}'")
        self.assertRegex(new, r'^oyuncu_\d{4}$')
        self.assertEqual(last("SELECT CONCAT(name_key,'|',name_norm) FROM name_bans WHERE name_key='mo_rezil'"), 'mo_rezil|morezil')
        self.assertEqual(last(f"SELECT GROUP_CONCAT(DISTINCT status) FROM user_reports WHERE target_id={self.uid('rezil')}"), 'actioned')
        # Yasaklı ad ve varyantları alınamaz.
        for variant in ['mo_rezil', 'MO_REZIL99', 'm0_r3zil', 'morezil']:
            s, r = self.register(variant)
            self.assertEqual((s, r['error']['code']), (422, 'username_not_allowed'), variant)
        self.assertFalse(self.s.get('/v1/username/check?username=mo_rezil')[1]['allowed'])
        # Kısa kök ("mo_x1" → "mox") yalnız tam adıyla yasaklanır; benzer masum adlar alınabilir.
        status, html = admin.act('rename', self.pid('x1'))
        self.assertIn('→ @oyuncu_', html)
        self.assertEqual(last("SELECT CONCAT(name_key,'|',name_norm,'|') FROM name_bans WHERE name_key='mo_x1'"), 'mo_x1||')
        self.assertEqual(self.register('mo_x1')[1]['error']['code'], 'username_not_allowed')
        self.assertEqual(self.register('mo_x2')[0], 200)
        # Askıya alma: giriş, oturum, yenileme ve eşleşme kapanır; sıralamadan çıkar.
        self.play('cezali')
        cezali = self.pid('cezali')
        status, html = admin.act('suspend', cezali)
        self.assertIn('askıya alındı', html)
        s, r = self.s.post('/v1/auth/login', dict(email='mo_cezali@test.local', password='password1'))
        self.assertEqual((s, r['error']['code']), (403, 'account_suspended'))
        self.assertIn('askıya alındı', r['error']['message'])
        self.assertIn('hesap silme', r['error']['message'])
        s, r = self.s.post('/v1/auth/login', dict(email='mo_cezali@test.local', password='wrong-pass'))
        self.assertEqual((s, r['error']['code']), (401, 'bad_credentials'))  # parola bilinmeden durum sızmaz
        self.assertEqual(self.s.get('/v1/me', self.tok('cezali'))[1]['error']['code'], 'account_suspended')
        s, r = self.s.post('/v1/auth/refresh', dict(refreshToken=self.u['cezali']['refresh']))
        self.assertEqual(s, 401)  # askıya almada oturumlar düşer
        self.assertEqual(self.queue('cezali')[0], 403)
        self.assertNotIn(cezali, self.board())
        self.assertIn('@mo_cezali', admin.request()[1].split('Askıdaki hesaplar')[1])
        status, html = admin.act('unsuspend', cezali)
        self.assertIn('yeniden etkin', html)
        s, r = self.s.post('/v1/auth/login', dict(email='mo_cezali@test.local', password='password1'))
        self.assertEqual(s, 200, r)
        self.u['cezali']['token'] = r['accessToken']
        self.assertIn(cezali, self.board())

    def test_10_account_deletion_cleans_reports_and_blocks(self):
        gone = self.u['silinen']; uid = self.uid('silinen')
        self.s.post('/v1/blocks', dict(user_id=self.pid('han')), gone['token'])
        self.s.post('/v1/blocks', dict(user_id=gone['user']['id']), self.tok('han'))
        self.report('silinen', self.pid('han'))
        for who in ['ana', 'bek', 'cem']:  # adı gizlenmiş: silinince ad yasak listesine kişisiz girer
            self.report(who, gone['user']['id'])
        mysql(f"INSERT INTO name_bans(name_key,name_norm,user_id) VALUES('mo_eskiad','moeskiad',{uid})")
        s, r = self.s.delete('/v1/me', {}, gone['token']); self.assertEqual(s, 200, r)
        self.assertEqual(last(f"SELECT COUNT(*) FROM user_blocks WHERE blocker_id={uid} OR blocked_id={uid}"), '0')
        self.assertEqual(last(f"SELECT COUNT(*) FROM user_reports WHERE reporter_id={uid} OR target_id={uid}"), '0')
        self.assertEqual(last("SELECT COALESCE(user_id,'NULL') FROM name_bans WHERE name_key='mo_eskiad'"), 'NULL')
        self.assertEqual(last("SELECT COALESCE(user_id,'NULL') FROM name_bans WHERE name_key='mo_silinen'"), 'NULL')
        s, r = self.register('mo_silinen')
        self.assertEqual((s, r['error']['code']), (422, 'username_not_allowed'))

    def test_11_migration_is_idempotent(self):
        mysql((ROOT / 'database/migrations/20261013_moderation.sql').read_text())
        mysql((ROOT / 'database/migrations/20261013_moderation.sql').read_text())
        cols = last("SELECT COUNT(*) FROM information_schema.COLUMNS WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='users' AND COLUMN_NAME IN ('terms_version','terms_accepted_at','name_cleared_key')")
        self.assertEqual(cols, '3')
        self.assertGreater(int(last("SELECT COUNT(*) FROM user_reports")), 0)
        self.assertEqual(last("SELECT TABLE_COLLATION FROM information_schema.TABLES WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='user_reports'"), 'utf8mb4_unicode_ci')


if __name__ == '__main__':
    unittest.main(verbosity=2)
