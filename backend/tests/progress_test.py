#!/usr/bin/env python3
"""Bulut ilerlemesi gerçek PHP/MySQL testleri. Kendi tek kullanımlık test DB'sini oluşturur.

Kapsam: oturum zorunluluğu, boş başlangıç, PUT birleştirme ("ileride olan kazanır"),
idempotent yazım (revision artmaz), iki cihazın toplamı, yeni kurulum geri yükleme, epoch
sıfırlamanın diğer cihaza 409 ile yayılması, sıfırlamanın tercihleri koruması, boyut sınırı,
kullanıcılar arası yalıtım, DELETE /v1/me ile ilerleme + düello puanının silinmesi,
migration'ın ikinci kez uygulanabilmesi ve saf PHP birleştirme testleri.
Çalıştırma: SV_PHP=/usr/local/opt/php@8.4/bin/php python3 backend/tests/progress_test.py
"""
import subprocess
import unittest
from pathlib import Path

from harness import PHP, ROOT, Server, mysql, reset_schema


def dev(runs, shots=0, hits=0, fever=0, ms=0):
    return dict(runs=runs, shots=shots, hits=hits, feverHits=fever, playMs=ms)


class Progress(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        reset_schema()
        cls.server = Server(); cls.s = cls.server.__enter__()
        cls.u = {n: cls.s.register('pr_' + n) for n in ['ana', 'bek', 'cem', 'dua', 'ece']}

    @classmethod
    def tearDownClass(cls): cls.server.__exit__()

    def get(self, who):
        s, r = self.s.get('/v1/progress', self.u[who]['token']); self.assertEqual(s, 200, r)
        return r['progress']

    def put(self, who, payload, epoch=0, ok=200):
        s, r = self.s.put('/v1/progress', dict(epoch=epoch, payload=payload), self.u[who]['token'])
        self.assertEqual(s, ok, r)
        mysql("DELETE FROM api_rate_limits")
        return r

    def test_00_php_unit(self):
        out = subprocess.run([PHP, str(Path(__file__).with_name('progress_unit_test.php'))], capture_output=True, text=True)
        self.assertEqual(out.returncode, 0, out.stdout + out.stderr)

    def test_01_auth_required_and_empty(self):
        self.assertEqual(self.s.get('/v1/progress')[0], 401)
        self.assertEqual(self.s.put('/v1/progress', dict(epoch=0, payload={}))[0], 401)
        p = self.get('ana')
        self.assertEqual((p['epoch'], p['revision'], p['payload']['best']), (0, 0, 0))
        self.assertEqual(p['payload']['devices'], {})

    def test_02_merge_and_idempotent(self):
        r = self.put('bek', dict(best=420, maxStreak=6, tutorialDone=True, devices={'phoneAAAA1': dev(3, 30, 12, 1, 60000)},
                                 settings=dict(sound=False, haptics=True, at=1000)))['progress']
        self.assertEqual((r['revision'], r['payload']['best']), (1, 420))
        # Eski veriyle gelen yazım (düşük skor, eski ayar) ilerlemeyi geri almaz.
        r = self.put('bek', dict(best=90, maxStreak=9, devices={'phoneAAAA1': dev(2, 10, 5)},
                                 settings=dict(sound=True, haptics=True, at=500)))['progress']
        self.assertEqual(r['payload']['best'], 420)
        self.assertEqual(r['payload']['maxStreak'], 9)
        self.assertEqual(r['payload']['devices']['phoneAAAA1'], dev(3, 30, 12, 1, 60000))
        self.assertEqual(r['payload']['settings'], dict(sound=False, haptics=True, at=1000))
        self.assertEqual(r['revision'], 2)
        # Aynı yazım tekrar: değişiklik yok, revision artmaz.
        again = self.put('bek', r['payload'])['progress']
        self.assertEqual(again['revision'], 2)
        self.assertEqual(int(mysql("SELECT best_score FROM player_progress p JOIN users u ON u.id=p.user_id WHERE u.username='pr_bek'").split()[-1]), 420)

    def test_03_two_devices_and_fresh_install_restore(self):
        self.put('cem', dict(best=300, devices={'ipadBBBB22': dev(4, 40, 20, 2, 1000)}))
        self.put('cem', dict(best=510, devices={'phoneCCCC3': dev(1, 9, 9, 0, 500)}, settings=dict(sound=True, haptics=False, at=9)))
        # Yeni kurulum: yerel boş; GET ilerlemeyi olduğu gibi verir (soru yok).
        p = self.get('cem')
        self.assertEqual(p['payload']['best'], 510)
        self.assertEqual(p['totals'], dict(runs=5, shots=49, hits=29, feverHits=2, playMs=1500))
        self.assertEqual(p['payload']['settings']['haptics'], False)
        # Yeni cihaz ilk yazımı yalnız kendi sayacını ekler, öncekileri silmez.
        r = self.put('cem', dict(devices={'newDDDDD44': dev(1, 2, 1)}), epoch=p['epoch'])['progress']
        self.assertEqual(r['totals']['runs'], 6)
        self.assertEqual(r['payload']['best'], 510)

    def test_04_reset_propagates_by_epoch(self):
        self.put('dua', dict(best=1200, maxStreak=12, tutorialDone=True, devices={'phoneEEEE5': dev(9, 90, 50)},
                             settings=dict(sound=False, haptics=False, at=77)))
        s, r = self.s.post('/v1/progress/reset', {}, self.u['dua']['token']); self.assertEqual(s, 200, r)
        p = r['progress']
        self.assertEqual(p['epoch'], 1)
        self.assertEqual((p['payload']['best'], p['payload']['maxStreak'], p['payload']['devices']), (0, 0, {}))
        # Ayar ve rehber tercihtir, sıfırlamada kalır.
        self.assertEqual(p['payload']['settings'], dict(sound=False, haptics=False, at=77))
        self.assertTrue(p['payload']['tutorialDone'])
        # Diğer cihaz eski epoch'la eski rekoru yazmaya çalışır → 409 + güncel durum; veri geri gelmez.
        r = self.put('dua', dict(best=1200, devices={'tabletFFF6': dev(5)}), epoch=0, ok=409)
        self.assertEqual(r['error']['code'], 'progress_reset')
        self.assertEqual(r['error']['progress']['epoch'], 1)
        self.assertEqual(self.get('dua')['payload']['best'], 0)
        # Yeni epoch ile oyun devam eder.
        r = self.put('dua', dict(best=60, devices={'tabletFFF6': dev(1, 3, 2)}), epoch=1)['progress']
        self.assertEqual((r['epoch'], r['payload']['best']), (1, 60))
        # Gelecekteki epoch da reddedilir (istemci sunucuyu benimser).
        self.assertEqual(self.put('dua', dict(best=1), epoch=7, ok=409)['error']['code'], 'progress_reset')

    def test_05_validation_and_isolation(self):
        s, r = self.s.put('/v1/progress', dict(epoch=0), self.u['ece']['token'])
        self.assertEqual((s, r['error']['code']), (422, 'invalid_progress'))
        big = {'devices': {f'device{i:05d}': dev(i, i, i, i, i) for i in range(400)}}
        s, r = self.s.put('/v1/progress', dict(epoch=0, payload=big), self.u['ece']['token'])
        self.assertEqual((s, r['error']['code']), (413, 'progress_too_large'))
        self.put('ece', dict(best=30, devices={'x' * 3: dev(1), 'okDevice77': dev(2)}))
        p = self.get('ece')
        self.assertEqual(list(p['payload']['devices']), ['okDevice77'])
        self.assertEqual(self.get('ana')['payload']['best'], 0)  # başka kullanıcıya sızmaz

    def test_06_account_deletion_removes_cloud_progress(self):
        u = self.s.register('pr_silinen')
        uid = mysql("SELECT id FROM users WHERE username='pr_silinen'").split()[-1]
        s, r = self.s.put('/v1/progress', dict(epoch=0, payload=dict(best=777, devices={'phoneZZZZ9': dev(3)})), u['token'])
        self.assertEqual(s, 200, r)
        mysql(f"INSERT INTO duel_ratings(user_id,xp) VALUES({uid},120)")
        s, r = self.s.delete('/v1/me', {}, u['token']); self.assertEqual(s, 200, r)
        self.assertEqual(mysql(f"SELECT COUNT(*) FROM player_progress WHERE user_id={uid}").split()[-1], '0')
        self.assertEqual(mysql(f"SELECT COUNT(*) FROM duel_ratings WHERE user_id={uid}").split()[-1], '0')
        self.assertEqual(self.s.get('/v1/progress', u['token'])[0], 401)

    def test_07_migration_is_idempotent(self):
        mysql((ROOT / 'database/migrations/20261013_progress.sql').read_text())
        self.assertGreaterEqual(int(mysql("SELECT COUNT(*) FROM player_progress").split()[-1]), 3)


if __name__ == '__main__':
    unittest.main(verbosity=2)
