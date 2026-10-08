import '../game/shot_record.dart';

const kDuelSeconds = 90;

class DuelPlayer {
  const DuelPlayer({
    required this.id,
    required this.name,
    required this.score,
    required this.lives,
    required this.shots,
    required this.hits,
    required this.finished,
    required this.connected,
  });
  factory DuelPlayer.fromJson(Map<String, dynamic> j) => DuelPlayer(
    id: j['id'] as String,
    name: j['username'] as String,
    score: (j['score'] as num).toInt(),
    lives: (j['lives'] as num).toInt(),
    shots: (j['shots'] as num).toInt(),
    hits: (j['hits'] as num).toInt(),
    finished: j['finished'] == true,
    connected: j['connected'] == true,
  );
  final String id, name;
  final int score, lives, shots, hits;
  final bool finished, connected;
}

class DuelSnapshot {
  const DuelSnapshot({
    required this.id,
    required this.seed,
    required this.nonce,
    required this.status,
    required this.startsAt,
    required this.endsAt,
    required this.serverNow,
    required this.acceptedSeq,
    required this.players,
    required this.events,
    this.winnerId,
    this.reason,
    this.draw = false,
  });
  factory DuelSnapshot.fromResponse(Map<String, dynamic> response) {
    final j = response['duel'] as Map<String, dynamic>;
    final players = (j['players'] as List)
        .map((p) => DuelPlayer.fromJson(p as Map<String, dynamic>))
        .toList();
    if (players.length != 2 ||
        players[0].id == players[1].id ||
        !['countdown', 'live', 'finished'].contains(j['status'])) {
      throw const FormatException('Invalid duel snapshot');
    }
    final result = j['result'] as Map<String, dynamic>?;
    return DuelSnapshot(
      id: j['id'] as String,
      seed: (j['seed'] as num).toInt(),
      nonce: j['nonce'] as String,
      status: j['status'] as String,
      startsAt: (j['startsAtMs'] as num).toInt(),
      endsAt: (j['endsAtMs'] as num).toInt(),
      serverNow: (response['serverNowMs'] as num).toInt(),
      acceptedSeq: (j['myAcceptedSeq'] as num).toInt(),
      players: players,
      events: (j['events'] as List)
          .map((e) => ShotRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      winnerId: result?['winnerId'] as String?,
      reason: result?['reason'] as String?,
      draw: result?['draw'] == true,
    );
  }
  final String id, nonce, status;
  final int seed, startsAt, endsAt, serverNow, acceptedSeq;
  final List<DuelPlayer> players;
  final List<ShotRecord> events;
  final String? winnerId, reason;
  final bool draw;
  bool get finished => status == 'finished';
  DuelPlayer player(String id) => players.singleWhere((p) => p.id == id);
  DuelPlayer opponent(String id) => players.singleWhere((p) => p.id != id);
}
