import 'api_client.dart';

class LeaderboardEntry {
  const LeaderboardEntry({
    required this.id,
    required this.username,
    required this.score,
    required this.games,
  });
  factory LeaderboardEntry.fromJson(Map<String, dynamic> json) =>
      LeaderboardEntry(
        id: json['id'] as String,
        username: json['username'] as String,
        score: int.parse('${json['score']}'),
        games: int.parse('${json['games']}'),
      );
  final String id;
  final String username;
  final int score;
  final int games;
}

class GameSessionService {
  final api = ApiClient.instance;
  String? id;
  String? nonce;
  Future<void> start() async {
    try {
      final r = await api.post('/v1/games', data: {'version': '1.0.0'});
      id = r['sessionId'] as String;
      nonce = r['nonce'] as String;
    } catch (_) {
      id = null;
      nonce = null;
    }
  }

  Future<void> finish({
    required int score,
    required int shots,
    required int hits,
    required int misses,
    required int feverHits,
    required int maxStreak,
    required int durationMs,
    required String stage,
  }) async {
    final current = id, proof = nonce;
    if (current == null || proof == null) return;
    id = null;
    nonce = null;
    try {
      await api.post(
        '/v1/games/$current/finish',
        data: {
          'nonce': proof,
          'score': score,
          'shots': shots,
          'hits': hits,
          'misses': misses,
          'feverHits': feverHits,
          'maxStreak': maxStreak,
          'durationMs': durationMs,
          'stage': stage,
        },
      );
    } catch (_) {}
  }

  Future<List<LeaderboardEntry>> leaderboard(String period) async {
    final r = await api.get('/v1/leaderboard?period=$period');
    return (r['entries'] as List)
        .map((e) => LeaderboardEntry.fromJson(e as Map<String, dynamic>))
        .toList();
  }
}
