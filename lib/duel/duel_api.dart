import '../game/shot_record.dart';
import '../services/api_client.dart';
import 'duel_protocol.dart';

abstract class DuelApi {
  Future<DuelSnapshot?> queue();
  Future<void> cancelQueue();
  Future<DuelSnapshot> poll(String id, int since);
  Future<DuelSnapshot> send(
    String id,
    String nonce,
    List<ShotRecord> events,
    int since,
  );
  Future<DuelSnapshot> finish(String id, String nonce, int since);
  Future<void> forfeit(String id);
}

class HttpDuelApi implements DuelApi {
  HttpDuelApi({ApiClient? client}) : api = client ?? ApiClient.instance;
  final ApiClient api;
  @override
  Future<DuelSnapshot?> queue() async {
    final r = await api.post('/v1/duels/queue');
    return r['status'] == 'waiting' ? null : DuelSnapshot.fromResponse(r);
  }

  @override
  Future<void> cancelQueue() async {
    await api.delete('/v1/duels/queue');
  }

  @override
  Future<DuelSnapshot> poll(String id, int since) async =>
      DuelSnapshot.fromResponse(await api.get('/v1/duels/$id?since=$since'));
  @override
  Future<DuelSnapshot> send(
    String id,
    String nonce,
    List<ShotRecord> events,
    int since,
  ) async => DuelSnapshot.fromResponse(
    await api.post(
      '/v1/duels/$id/events',
      data: {
        'nonce': nonce,
        'events': events.map((e) => e.toJson()).toList(),
        'since': since,
      },
    ),
  );
  @override
  Future<DuelSnapshot> finish(String id, String nonce, int since) async =>
      DuelSnapshot.fromResponse(
        await api.post(
          '/v1/duels/$id/finish',
          data: {'nonce': nonce, 'since': since},
        ),
      );
  @override
  Future<void> forfeit(String id) async {
    await api.post('/v1/duels/$id/forfeit');
  }
}
