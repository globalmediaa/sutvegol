#!/usr/bin/env python3
"""Düello v2 (hibrit) gerçek PHP/MySQL testleri. Kendi tek kullanımlık test DB'sini oluşturur.

Kapsam: v1 istemci reddi, şut saati + combo doğrulaması, sonuç + Glicko rating, rövanş,
kopma rozeti / hükmen, ghost seçimi (kendi koşusu değil, CPU yedeği) ve oynatma verisi,
ghost maçının rating'e sayılmaması, eşleşme bandı ve saf PHP unit testleri.
"""
import os
import subprocess
import unittest
from pathlib import Path

from harness import PHP, Server, V2Run, mysql, reset_schema

Q = {'duelVersion': 2}
NOW = "UNIX_TIMESTAMP(NOW(3))*1000"


def last(sql):
    return mysql(sql).strip().splitlines()[-1]


class DuelV2(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        reset_schema()
        cls.server = Server(); cls.s = cls.server.__enter__()
        cls.u = {n: cls.s.register('v2_' + n) for n in
                 ['ana', 'bek', 'cem', 'dua', 'ece', 'fat', 'gul', 'han', 'ilk', 'jale']}

    @classmethod
    def tearDownClass(cls): cls.server.__exit__()

    # ----------------------------------------------------------- yardımcılar
    def queue(self, who, body=Q):
        return self.s.post('/v1/duels/queue', body, self.u[who]['token'])

    def pair(self, a, b):
        self.assertEqual(self.queue(a)[1]['status'], 'waiting')
        s, r = self.queue(b); self.assertEqual(s, 200, r)
        id = r['duel']['id']
        mysql(f"UPDATE duels SET starts_at_ms={NOW}-30000,ends_at_ms={NOW}+60000 WHERE id='{id}'")
        na = self.s.get('/v1/duels/' + id, self.u[a]['token'])[1]['duel']['nonce']
        return id, na, r['duel']['nonce']

    def send(self, who, id, nonce, events):
        return self.s.post(f'/v1/duels/{id}/events', dict(nonce=nonce, events=events), self.u[who]['token'])

    def end(self, id):
        mysql(f"UPDATE duels SET ends_at_ms={NOW}-9000 WHERE id='{id}'")

    def me(self, snap, who):
        return next(p for p in snap['players'] if p['id'] == self.u[who]['user']['id'])

    def ghost_duel(self, who):
        self.assertEqual(self.queue(who)[1]['status'], 'waiting')
        mysql(f"UPDATE duel_queue SET joined_ms={NOW}-16000 WHERE user_id=(SELECT id FROM users WHERE username='v2_{who}')")
        s, r = self.queue(who); self.assertEqual(s, 200, r)
        self.assertEqual(r['duel']['kind'], 'ghost')
        return r

    # ----------------------------------------------------------- testler
    def test_00_php_unit(self):
        out = subprocess.run([PHP, str(Path(__file__).with_name('unit_test.php'))], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)

    def test_01_cpu_ghost_when_pool_empty(self):
        # İlk günler: hiç bitmiş koşu yok → açıkça etiketli CPU koşusu.
        r = self.ghost_duel('jale')
        g = r['duel']['ghost']
        self.assertEqual(g['source'], 'cpu')
        ghost = next(p for p in r['duel']['players'] if p['ghost'])
        self.assertEqual((ghost['id'], ghost['username']), ('ghost', 'CPU'))
        ts = [e['t'] for e in g['events']]
        self.assertEqual(ts, sorted(ts)); self.assertGreater(len(ts), 15)
        self.s.post(f"/v1/duels/{r['duel']['id']}/forfeit", {}, self.u['jale']['token'])

    def test_02_v1_client_rejected(self):
        for body in ({}, {'duelVersion': 1}):
            s, r = self.queue('ana', body)
            self.assertEqual((s, r['error']['code']), (426, 'update_required'))
        self.assertEqual(self.s.get('/v1/duels/queue', self.u['ana']['token'])[0], 426)
        self.assertEqual(self.s.get('/v1/duels/queue?duelVersion=2', self.u['ana']['token'])[1]['status'], 'waiting')
        self.s.delete('/v1/duels/queue', token=self.u['ana']['token'])
        # Canlı tek kişilik uçlar etkilenmez.
        self.assertEqual(self.s.get('/v1/leaderboard?period=all')[0], 200)
        self.assertEqual(self.s.get('/health')[1]['duelVersion'], 2)

    def test_03_shot_clock_combo_result_rating(self):
        id, na, nb = self.pair('ana', 'bek')
        a, b = V2Run(), V2Run()
        e1, e2, e3 = a.event(), a.event(), a.event()
        self.assertEqual([e1['score'], e2['score'], e3['score']], [30, 90, 180])
        bad = dict(e1, mult=2, score=60)
        self.assertEqual(self.send('ana', id, na, [bad])[1]['error']['code'], 'score_math')
        s, r = self.send('ana', id, na, [e1, e2, e3]); self.assertEqual(s, 200, r)
        self.assertEqual(self.me(r['duel'], 'ana')['combo'], 3)
        # Şut saati: 5 sn + döngü payını aşan boşluk reddedilir; erken timeout reddedilir.
        late = V2Run(); late.__dict__.update(a.__dict__); slow = late.event(dt=10500)
        self.assertEqual(self.send('ana', id, na, [slow])[1]['error']['code'], 'shot_clock')
        early = V2Run(); early.__dict__.update(a.__dict__); eto = early.event(timeout=True, dt=3000)
        self.assertEqual(self.send('ana', id, na, [eto])[1]['error']['code'], 'shot_clock')
        to = a.event(timeout=True, dt=5200)
        s, r = self.send('ana', id, na, [to]); self.assertEqual(s, 200, r)
        mine = self.me(r['duel'], 'ana')
        self.assertEqual((mine['combo'], mine['maxStreak'], mine['finished']), (0, 3, False))
        # Kral Modu: 5 gol → sonraki gol x2.
        evs = [a.event() for _ in range(6)]
        self.assertTrue(evs[4]['fever']); self.assertEqual(evs[5]['mult'], 2)
        self.assertEqual(self.send('ana', id, na, evs)[0], 200)
        self.assertEqual(self.send('bek', id, nb, [b.event(), b.event(hit=False), b.event()])[0], 200)
        # Rakibin olayları sırayla gelir.
        got = self.s.get(f'/v1/duels/{id}?since=0', self.u['bek']['token'])[1]['duel']['events']
        self.assertEqual([e['seq'] for e in got], list(range(1, 11)))
        self.s.post(f'/v1/duels/{id}/finish', dict(nonce=na), self.u['ana']['token'])
        s, r = self.s.post(f'/v1/duels/{id}/finish', dict(nonce=nb), self.u['bek']['token'])
        res = r['duel']['result']
        self.assertEqual((res['winnerId'], res['reason'], res['ratingCounted']), (self.u['ana']['user']['id'], 'completed', True))
        self.assertLess(res['ratingAfter'], res['ratingBefore'])
        self.assertEqual(res['xp'], 10 + 2 * 2)
        stats = self.s.get('/v1/duels/stats', self.u['ana']['token'])[1]['stats']
        self.assertEqual((stats['games'], stats['wins'], stats['calibrating']), (1, 1, True))
        self.assertGreater(stats['rating'], 1500); self.assertEqual(stats['xp'], 10 + 2 * a.hits + 25)
        self.__class__.live_id = id

    def test_04_rematch(self):
        id = self.live_id
        r = self.s.post(f'/v1/duels/{id}/rematch', {}, self.u['ana']['token'])[1]['duel']['rematch']
        self.assertEqual((r['mine'], r['theirs'], r['duelId']), (True, False, None))
        theirs = self.s.get(f'/v1/duels/{id}', self.u['bek']['token'])[1]['duel']['rematch']
        self.assertTrue(theirs['theirs'])
        r = self.s.post(f'/v1/duels/{id}/rematch', {}, self.u['bek']['token'])[1]['duel']['rematch']
        new = r['duelId']; self.assertTrue(new)
        # İkinci basış/eşzamanlı istek ikinci maç üretmez.
        self.assertEqual(self.s.post(f'/v1/duels/{id}/rematch', {}, self.u['ana']['token'])[1]['duel']['rematch']['duelId'], new)
        self.assertEqual(last(f"SELECT COUNT(*) FROM duels WHERE rematch_of='{id}'"), '1')
        snap = self.s.get(f'/v1/duels/{new}', self.u['ana']['token'])[1]['duel']
        self.assertEqual(sorted(p['id'] for p in snap['players']), sorted([self.u['ana']['user']['id'], self.u['bek']['user']['id']]))
        self.assertEqual(self.queue('bek')[1]['duel']['id'], new)  # aktif rövanşa döner
        self.s.post(f'/v1/duels/{new}/forfeit', {}, self.u['bek']['token'])
        # 10 sn sonra rövanş yok.
        mysql(f"UPDATE duels SET finished_at_ms={NOW}-12000 WHERE id='{new}'")
        s, r = self.s.post(f'/v1/duels/{new}/rematch', {}, self.u['ana']['token'])
        self.assertEqual((s, r['error']['code']), (409, 'rematch_expired'))

    def test_05_disconnect_badge_and_forfeit(self):
        id, nc, nd = self.pair('cem', 'dua')
        uid = self.u['dua']['user']['id']
        mysql(f"UPDATE duel_players SET last_seen_ms={NOW}-16000 WHERE duel_id='{id}' AND user_id=(SELECT id FROM users WHERE public_id='{uid}')")
        snap = self.s.get(f'/v1/duels/{id}', self.u['cem']['token'])[1]['duel']
        opp = self.me(snap, 'dua')
        self.assertEqual((snap['status'], opp['connected']), ('live', False))
        self.assertGreaterEqual(opp['silentMs'], 16000)
        mysql(f"UPDATE duel_players SET last_seen_ms={NOW}-31000 WHERE duel_id='{id}' AND user_id=(SELECT id FROM users WHERE public_id='{uid}')")
        snap = self.s.get(f'/v1/duels/{id}', self.u['cem']['token'])[1]['duel']
        self.assertEqual(snap['status'], 'finished')
        self.assertEqual((snap['result']['winnerId'], snap['result']['reason']), (self.u['cem']['user']['id'], 'disconnect'))
        self.assertEqual(self.s.get(f'/v1/duels/{id}', self.u['dua']['token'])[1]['duel']['result']['xp'], 0)

    def test_06_ghost_selection_playback_and_no_rating(self):
        # Havuzda ana/bek/cem koşuları var; ece'nin kendi koşusu da olsun, asla seçilmesin.
        id, ne, nf = self.pair('ece', 'fat')
        run = V2Run()
        self.assertEqual(self.send('ece', id, ne, [run.event() for _ in range(5)])[0], 200)
        self.end(id); self.s.get(f'/v1/duels/{id}', self.u['ece']['token'])
        before = self.s.get('/v1/duels/stats', self.u['ece']['token'])[1]['stats']
        sources = set()
        for i in range(4):
            r = self.ghost_duel('ece')
            d = r['duel']; g = d['ghost']
            self.assertEqual(g['source'], 'recorded')
            ghost = next(p for p in d['players'] if p['ghost'])
            self.assertNotEqual(ghost['username'], 'v2_ece')
            sources.add(ghost['username'])
            ts = [e['t'] for e in g['events']]
            self.assertEqual(ts, sorted(ts))
            self.assertTrue(all(e['v'] == 2 for e in g['events']))
            # Oynatma verisi: sunucunun ghost skoru t anındaki olayla aynı.
            mysql(f"UPDATE duels SET starts_at_ms={NOW}-{ts[1] + 1},ends_at_ms={NOW}+80000 WHERE id='{d['id']}'")
            snap = self.s.get(f"/v1/duels/{d['id']}?ghost=1", self.u['ece']['token'])[1]['duel']
            gp = next(p for p in snap['players'] if p['ghost'])
            self.assertIn(gp['shots'], (2, 3))
            self.assertEqual(gp['score'], g['events'][gp['shots'] - 1]['score'])
            self.assertEqual(len(snap['ghost']['events']), g['eventCount'])
            nonce = snap['nonce']
            if i == 0:
                # İnsan gibi ghost'u yenerse kazanır; rating değişmez, XP gelir.
                mysql(f"UPDATE duels SET starts_at_ms={NOW}-60000 WHERE id='{d['id']}'")
                mine = V2Run(); evs = [mine.event(dt=1200) for _ in range(30)]
                self.assertEqual(self.send('ece', d['id'], nonce, evs)[0], 200)
                self.end(d['id'])
                res = self.s.get(f"/v1/duels/{d['id']}", self.u['ece']['token'])[1]['duel']['result']
                ghost_final = g['events'][-1]['score']
                exp = self.u['ece']['user']['id'] if mine.score > ghost_final else 'ghost'
                self.assertEqual(res['winnerId'], exp)
                self.assertFalse(res['ratingCounted']); self.assertIsNone(res['ratingAfter'])
                self.assertGreater(res['xp'], 0)
            elif i == 1:
                self.s.post(f"/v1/duels/{d['id']}/forfeit", {}, self.u['ece']['token'])
                res = self.s.get(f"/v1/duels/{d['id']}", self.u['ece']['token'])[1]['duel']['result']
                self.assertEqual((res['winnerId'], res['reason']), ('ghost', 'forfeit'))
            else:
                self.s.post(f"/v1/duels/{d['id']}/forfeit", {}, self.u['ece']['token'])
        after = self.s.get('/v1/duels/stats', self.u['ece']['token'])[1]['stats']
        self.assertEqual((after['games'], after['rating']), (before['games'], before['rating']))
        self.assertGreater(after['xp'], before['xp'])
        # Ghost maçında rövanş yok.
        self.assertEqual(self.s.post(f"/v1/duels/{d['id']}/rematch", {}, self.u['ece']['token'])[0], 409)

    def test_07_rating_band(self):
        g, h = self.u['gul']['user']['id'], self.u['han']['user']['id']
        mysql(f"INSERT INTO duel_ratings(user_id,rating) SELECT id,2100 FROM users WHERE public_id='{g}'")
        self.assertEqual(self.queue('gul')[1]['status'], 'waiting')
        self.assertEqual(self.queue('han')[1]['status'], 'waiting')  # 600 fark, havuz küçük: bant 400
        mysql(f"UPDATE duel_queue SET joined_ms={NOW}-11000")  # 10 sn sonra bant sınırsız
        s, r = self.queue('han'); self.assertEqual(r['duel']['kind'], 'live')
        self.assertEqual(sorted(p['id'] for p in r['duel']['players']), sorted([g, h]))
        self.s.delete('/v1/duels/queue', token=self.u['han']['token'])


if __name__ == '__main__':
    unittest.main(verbosity=2)
