#!/usr/bin/env python3
"""Düello v2 uçtan uca: yerel PHP (php -S) + yeni sutvegol_test_* MySQL DB'si.

Gerçek zamanlı çalışır (zaman kaydırma yok), canlı sunucuya asla bağlanmaz:
  1) İki sentetik oyuncu aynı anda kuyruğa girer, 90 sn canlı düello oynar
     (700 ms yoklama, şut saati ıskası dahil), sonuç + rating + XP doğrulanır.
  2) Rövanş: iki taraf da basar → aynı rakiple yeni maç; biri çekilir (hükmen).
  3) Üçüncü oyuncu 15 sn canlı rakip bulamaz → kayıtlı rakip (ghost) maçı; ghost
     skoru maç saatine göre doğrulanır, rating'e sayılmaz, XP verir.
Kullanım: SV_PHP=/path/php8 python3 backend/tests/e2e_duel.py   (~4 dk)
"""
import json
import random
import sys
import threading
import time

from harness import Server, V2Run, mysql, reset_schema

Q = {'duelVersion': 2}
rng = random.Random(20261013)
log_lock = threading.Lock()


def log(*a):
    with log_lock:
        print(time.strftime('%H:%M:%S'), *a, flush=True)


class Player:
    def __init__(self, s, name):
        self.s, self.name = s, name
        self.acc = s.register(name)
        self.id = self.acc['user']['id']
        self.run = V2Run()
        self.outbox, self.received, self.snap = [], [], None
        self.offset = 0
        self.timeouts = 0

    def call(self, method, path, data=None):
        t0 = time.time() * 1000
        st, r = getattr(self.s, method)(path, data, self.acc['token']) if method != 'get' else self.s.get(path, self.acc['token'])
        if 'serverNowMs' in r:
            self.offset = r['serverNowMs'] - (t0 + time.time() * 1000) / 2
        return st, r

    def server_now(self):
        return time.time() * 1000 + self.offset

    def find_match(self, timeout=40):
        t_end = time.time() + timeout
        while time.time() < t_end:
            st, r = self.call('post', '/v1/duels/queue', Q)
            assert st == 200, r
            if 'duel' in r:
                self.snap = r['duel']
                return r['duel']
            time.sleep(.7)
        raise AssertionError(f'{self.name}: eşleşme yok')

    def play(self, hit_rate=.7):
        """Gerçek istemci gibi: maç saatine göre şut, 700 ms'de bir gönder/yokla."""
        d = self.snap; did = d['id']; nonce = d['nonce']
        starts, ends = d['startsAtMs'], d['endsAtMs']
        while self.server_now() < starts:
            time.sleep(.2)
        def schedule():
            # %8 ihtimalle oyuncu hiç şut atmaz: istemci t = son şut + 5 sn'de otomatik ıskalar.
            if rng.random() < .08:
                return self.run.t + 5050, True
            return self.run.t + rng.uniform(1300, 3000), False
        next_shot, timeout = schedule()
        while True:
            elapsed = self.server_now() - starts
            if self.server_now() >= ends:
                break
            if elapsed >= next_shot and elapsed < 89000:
                if timeout:
                    e = self.run.event(timeout=True, dt=5050)
                    self.timeouts += 1
                else:
                    e = self.run.event(hit=rng.random() < hit_rate, dt=max(400, int(elapsed) - self.run.t))
                self.outbox.append(e)
                next_shot, timeout = schedule()
            since = self.received[-1]['seq'] if self.received else 0
            if self.outbox:
                st, r = self.call('post', f'/v1/duels/{did}/events', dict(nonce=nonce, events=self.outbox[:30], since=since))
                assert st == 200, (self.name, r)
                acc = r['duel']['myAcceptedSeq']
                self.outbox = [x for x in self.outbox if x['seq'] > acc]
            else:
                st, r = self.call('get', f'/v1/duels/{did}?since={since}')
                assert st == 200, r
            self.snap = r['duel']
            self.received += [x for x in r['duel']['events'] if not self.received or x['seq'] > self.received[-1]['seq']]
            if r['duel']['status'] == 'finished':
                return r['duel']
            time.sleep(.7)
        while self.outbox:
            st, r = self.call('post', f'/v1/duels/{did}/events', dict(nonce=nonce, events=self.outbox[:30]))
            assert st == 200, (self.name, r)
            self.outbox = [x for x in self.outbox if x['seq'] > r['duel']['myAcceptedSeq']]
        st, r = self.call('post', f'/v1/duels/{did}/finish', dict(nonce=nonce, since=self.received[-1]['seq'] if self.received else 0))
        for _ in range(30):
            if r['duel']['status'] == 'finished':
                break
            time.sleep(.7)
            st, r = self.call('get', f"/v1/duels/{did}?since={self.received[-1]['seq'] if self.received else 0}")
        self.received += [x for x in r['duel']['events'] if not self.received or x['seq'] > self.received[-1]['seq']]
        self.snap = r['duel']
        return r['duel']


def main():
    reset_schema()
    report = {}
    with Server() as s:
        a, b, c = Player(s, 'e2e_alice'), Player(s, 'e2e_bob'), Player(s, 'e2e_carol')
        assert s.get('/health')[1]['duelVersion'] == 2
        assert s.post('/v1/duels/queue', {}, a.acc['token'])[0] == 426  # eski istemci

        # 1) Canlı düello, iki oyuncu eşzamanlı.
        log('canlı düello: kuyruk')
        res = {}
        def live(p, rate):
            p.find_match(); log(p.name, 'eşleşti', p.snap['id'][:8]); res[p.name] = p.play(rate)
        ts = [threading.Thread(target=live, args=(a, .75)), threading.Thread(target=live, args=(b, .6))]
        [t.start() for t in ts]; [t.join() for t in ts]
        ra, rb = res['e2e_alice'], res['e2e_bob']
        assert ra['id'] == rb['id'] and ra['kind'] == 'live'
        assert ra['result'] == {**ra['result'], 'winnerId': rb['result']['winnerId']}
        pa = next(p for p in ra['players'] if p['id'] == a.id); pb = next(p for p in ra['players'] if p['id'] == b.id)
        assert (pa['score'], pb['score']) == (a.run.score, b.run.score), (pa, pb, a.run.score, b.run.score)
        assert [e['seq'] for e in a.received] == list(range(1, b.run.seq + 1)), 'rakip olayları eksiksiz/sıralı değil'
        assert [e['seq'] for e in b.received] == list(range(1, a.run.seq + 1))
        exp = a.id if (a.run.score, a.run.hits) > (b.run.score, b.run.hits) else b.id if (a.run.score, a.run.hits) < (b.run.score, b.run.hits) else None
        assert ra['result']['winnerId'] == exp and ra['result']['ratingCounted']
        report['live'] = dict(duel=ra['id'][:8], scores={'alice': a.run.score, 'bob': b.run.score},
                              shots={'alice': a.run.shots, 'bob': b.run.shots}, timeouts={'alice': a.timeouts, 'bob': b.timeouts},
                              maxCombo={'alice': a.run.max_streak, 'bob': b.run.max_streak}, winner='alice' if exp == a.id else 'bob' if exp else 'draw',
                              rating={'alice': [ra['result']['ratingBefore'], ra['result']['ratingAfter']], 'bob': [rb['result']['ratingBefore'], rb['result']['ratingAfter']]},
                              xp={'alice': ra['result']['xp'], 'bob': rb['result']['xp']})
        log('canlı sonuç', json.dumps(report['live'], ensure_ascii=False))

        # 2) Rövanş.
        did = ra['id']
        st1, r1 = a.call('post', f'/v1/duels/{did}/rematch', {})
        st2, r2 = b.call('post', f'/v1/duels/{did}/rematch', {})
        new = r2['duel']['rematch']['duelId']
        assert st1 == st2 == 200 and new and a.call('get', f'/v1/duels/{did}')[1]['duel']['rematch']['duelId'] == new
        st, r = a.call('post', f'/v1/duels/{new}/forfeit', {})
        assert r['duel']['result']['winnerId'] == b.id and r['duel']['result']['reason'] == 'forfeit'
        report['rematch'] = dict(newDuel=new[:8], forfeitWinner='bob')
        log('rövanş', report['rematch'])

        # 3) Ghost: canlı rakip yok → 15 sn sonra kayıtlı rakip.
        t0 = time.time()
        d = c.find_match(40)
        waited = time.time() - t0
        assert d['kind'] == 'ghost' and d['ghost']['source'] == 'recorded', d['ghost']
        g = next(p for p in d['players'] if p['ghost'])
        assert g['username'] in ('e2e_alice', 'e2e_bob') and g['username'] != 'e2e_carol'
        events = d['ghost']['events']; ts_ = [e['t'] for e in events]
        assert ts_ == sorted(ts_) and len(events) == d['ghost']['eventCount']
        log(f'ghost maçı {waited:.1f} sn sonra; kaynak {g["username"]}, {len(events)} olay')
        checks = []
        def watch():
            while c.snap['status'] != 'finished':
                snap = c.snap
                elapsed = c.server_now() - snap['startsAtMs']
                gp = next(p for p in snap['players'] if p['ghost'])
                if 0 < elapsed < 89000 and snap['status'] == 'live':
                    done = [e for e in events if e['t'] <= elapsed]
                    exp_lo = done[-2]['score'] if len(done) > 1 else 0
                    checks.append(gp['score'] in (exp_lo, done[-1]['score'] if done else 0))
                time.sleep(2)
        w = threading.Thread(target=watch, daemon=True); w.start()
        rc = c.play(.7)
        final = events[-1]['score']
        mine = next(p for p in rc['players'] if p['id'] == c.id)
        exp = c.id if (c.run.score, c.run.hits) > (final, events[-1]['hits']) else 'ghost' if (c.run.score, c.run.hits) < (final, events[-1]['hits']) else None
        assert mine['score'] == c.run.score and rc['result']['winnerId'] == exp
        assert not rc['result']['ratingCounted'] and rc['result']['xp'] > 0
        assert checks and all(checks), checks
        stats = c.call('get', '/v1/duels/stats')[1]['stats']
        assert stats['games'] == 0 and stats['xp'] == rc['result']['xp']
        report['ghost'] = dict(waitedSec=round(waited, 1), source=g['username'], ghostScore=final, carolScore=c.run.score,
                               winner='carol' if exp == c.id else exp or 'draw', ratingCounted=False, xp=rc['result']['xp'],
                               playbackChecks=len(checks))
        log('ghost sonuç', json.dumps(report['ghost'], ensure_ascii=False))
    print(json.dumps({'ok': True, **report}, ensure_ascii=False))


if __name__ == '__main__':
    try:
        main()
    except AssertionError as e:
        print(json.dumps({'ok': False, 'error': str(e)[:500]}, ensure_ascii=False)); sys.exit(1)
