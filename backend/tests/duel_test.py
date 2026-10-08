#!/usr/bin/env python3
"""Real concurrent PHP/MySQL integration. Creates its own disposable DB only."""
import copy
import concurrent.futures
import unittest
from harness import Server, reset_schema, mysql


def shot(seq=1, hit=True, hits=None, misses=0):
    hits = seq if hits is None else hits
    return dict(v=1,seq=seq,t=(seq-1)*400,stage='street',view='wide',
      target=[660,1350],chord=[0,-500],dev=0,tMax=.5,power=.5,
      keeper=[None,None],path='net',hit=hit,end=[660,1350],drop=None,
      score=hits*30,lives=3-misses,streak=hits if hit else 0,fever=False,
      feverLeft=0,shots=seq,hits=hits,misses=misses,feverHits=0,maxStreak=hits)


class Duels(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        reset_schema()
        cls.server=Server(); cls.s=cls.server.__enter__()
        cls.a=cls.s.register('duel_alice'); cls.b=cls.s.register('duel_bob')
        cls.c=cls.s.register('duel_carla'); cls.d=cls.s.register('duel_dave')
        cls.e=cls.s.register('duel_emma'); cls.f=cls.s.register('duel_fred')

    @classmethod
    def tearDownClass(cls): cls.server.__exit__()

    def pair(self,a,b):
        self.assertEqual(self.s.post('/v1/duels/queue',{},a['token'])[1]['status'],'waiting')
        s,r=self.s.post('/v1/duels/queue',{},b['token']); self.assertEqual(s,200)
        match=r['duel']; id=match['id']
        ra=self.s.get('/v1/duels/'+id,a['token'])[1]['duel']
        mysql(f"UPDATE duels SET starts_at_ms=UNIX_TIMESTAMP(NOW(3))*1000-2000,ends_at_ms=UNIX_TIMESTAMP(NOW(3))*1000+88000 WHERE id='{id}'")
        return id,ra['nonce'],match['nonce']

    def test_01_event_integrity_and_result(self):
        id,na,nb=self.pair(self.a,self.b); path='/v1/duels/'+id
        self.assertEqual(self.s.get(path,self.c['token'])[0],404)
        self.assertEqual(self.s.post(path+'/events',dict(nonce='bad',events=[shot()]),self.a['token'])[0],403)
        self.assertEqual(self.s.post(path+'/events',dict(nonce=na,events=[shot(2)]),self.a['token'])[1]['error']['code'],'sequence_gap')
        event=shot(); bad=copy.deepcopy(event); bad['score']=999
        self.assertEqual(self.s.post(path+'/events',dict(nonce=na,events=[bad]),self.a['token'])[1]['error']['code'],'score_math')
        s,r=self.s.post(path+'/events',dict(nonce=na,events=[event]),self.a['token']); self.assertEqual(s,200,r)
        self.assertEqual(r['duel']['myAcceptedSeq'],1)
        self.assertEqual(self.s.post(path+'/events',dict(nonce=na,events=[event]),self.a['token'])[0],200)
        changed=copy.deepcopy(event); changed['power']=.7
        self.assertEqual(self.s.post(path+'/events',dict(nonce=na,events=[changed]),self.a['token'])[1]['error']['code'],'event_conflict')
        # One invalid item rolls back the entire batch; no partial score.
        bad3=shot(3); bad3['score']=900
        self.assertEqual(self.s.post(path+'/events',dict(nonce=na,events=[shot(2),bad3]),self.a['token'])[0],422)
        self.assertEqual(self.s.get(path,self.a['token'])[1]['duel']['myAcceptedSeq'],1)
        self.assertEqual(self.s.post(path+'/events',dict(nonce=na,events=[shot(2),shot(3)]),self.a['token'])[0],200)
        events=self.s.get(path+'?since=1',self.b['token'])[1]['duel']['events']
        self.assertEqual([x['seq'] for x in events],[2,3])
        # Client-provided finish score is ignored: persisted events decide.
        self.s.post(path+'/finish',dict(nonce=nb,summary={'score':100000}),self.b['token'])
        s,r=self.s.post(path+'/finish',dict(nonce=na),self.a['token']); self.assertEqual(s,200,r)
        self.assertEqual(r['duel']['status'],'finished')
        self.assertEqual(r['duel']['result']['winnerId'],self.a['user']['id'])
        self.assertEqual(mysql(f"SELECT COUNT(*) FROM duel_events WHERE duel_id='{id}'").strip().splitlines()[-1],'3')

    def test_02_concurrent_queue_forfeit_cancel(self):
        with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
            responses=list(pool.map(lambda u:self.s.post('/v1/duels/queue',{},u['token']),[self.c,self.d]))
        self.assertTrue(all(s==200 for s,_ in responses),responses)
        matches=[r['duel']['id'] for _,r in responses if 'duel' in r]
        self.assertEqual(len(set(matches)),1)
        id=matches[0]; r=self.s.post('/v1/duels/queue',{},self.c['token'])[1]
        self.assertEqual(r['duel']['id'],id)
        s,r=self.s.delete('/v1/duels/queue',token=self.c['token']); self.assertEqual(s,200)
        self.assertEqual(r['duel']['result']['winnerId'],self.d['user']['id'])
        self.assertEqual(mysql(f"SELECT COUNT(*) FROM duel_players WHERE duel_id='{id}'").strip().splitlines()[-1],'2')
        self.assertEqual(self.s.post('/v1/duels/queue',{},self.c['token'])[1]['status'],'waiting')
        self.s.delete('/v1/duels/queue',token=self.c['token'])

    def test_03_lives_timeout_stale_tickets(self):
        self.s.post('/v1/duels/queue',{},self.e['token'])
        mysql("UPDATE duel_queue SET last_seen_ms=0")
        self.assertEqual(self.s.post('/v1/duels/queue',{},self.f['token'])[1]['status'],'waiting')
        self.s.delete('/v1/duels/queue',token=self.f['token'])
        id,ne,nf=self.pair(self.e,self.f)
        path='/v1/duels/'+id
        events=[shot(i,hit=False,hits=0,misses=i) for i in range(1,4)]
        s,r=self.s.post(path+'/events',dict(nonce=ne,events=events),self.e['token']); self.assertEqual(s,200,r)
        self.assertTrue(next(p for p in r['duel']['players'] if p['id']==self.e['user']['id'])['finished'])
        self.assertEqual(self.s.post(path+'/events',dict(nonce=ne,events=[shot(4,hit=False,hits=0,misses=4)]),self.e['token'])[0],409)
        mysql(f"UPDATE duels SET ends_at_ms=0 WHERE id='{id}'")
        r=self.s.get(path,self.f['token'])[1]['duel']
        self.assertEqual(r['status'],'finished'); self.assertTrue(r['result']['draw'])
        self.assertEqual(r['result']['reason'],'time')

    def test_04_account_deletion_and_apple_challenge(self):
        r=self.s.get('/v1/me',self.a['token'])[1]
        self.assertEqual(r['user']['providers'],['email'])
        s,r=self.s.post('/v1/auth/apple/challenge',{})
        self.assertEqual(s,200); self.assertEqual(len(r['nonce']),64)
        stored=mysql(f"SELECT nonce_hash FROM auth_challenges WHERE id='{r['challengeId']}'").strip().splitlines()[-1]
        self.assertNotEqual(stored,r['nonce'])
        self.assertEqual(self.s.post('/v1/auth/apple',{'identityToken':'invalid'},self.a['token'])[0],401)
        self.assertEqual(self.s.delete('/v1/me',token=self.a['token'])[0],200)
        self.assertEqual(self.s.get('/v1/me',self.a['token'])[0],401)
        self.assertEqual(self.s.post('/v1/auth/refresh',{'refreshToken':self.a['refresh']})[0],401)
        row=mysql("SELECT email,username,status FROM users WHERE status='deleted'").splitlines()[-1]
        self.assertEqual(row,'NULL\tNULL\tdeleted')


if __name__=='__main__': unittest.main(verbosity=2)
