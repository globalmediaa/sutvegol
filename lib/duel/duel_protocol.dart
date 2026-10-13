import '../game/shot_record.dart';

/// Sunucu `backend/src/duels.php` ile aynı sabitler.
const kDuelSeconds = 90;
const kDuelVersion = 2;
const kShotClockMs = 5000;
const kGhostAfterMs = 15000;
const kRematchMs = 10000;
const kForfeitSilentMs = 30000;

/// Rakip kimliği: canlı oyuncu ya da kayıtlı koşu (ghost / CPU).
enum OpponentKind { live, recorded, cpu }

class DuelPlayer {
  const DuelPlayer({
    required this.id,
    required this.name,
    required this.score,
    required this.shots,
    required this.hits,
    required this.finished,
    required this.connected,
    this.combo = 0,
    this.maxStreak = 0,
    this.silentMs = 0,
    this.ghost = false,
    this.rating,
    this.calibrating = false,
    this.ownerId,
    this.blocked = false,
  });
  factory DuelPlayer.fromJson(Map<String, dynamic> j) => DuelPlayer(
    id: j['id'] as String,
    name: j['username'] as String,
    score: (j['score'] as num).toInt(),
    shots: (j['shots'] as num).toInt(),
    hits: (j['hits'] as num).toInt(),
    finished: j['finished'] == true,
    connected: j['connected'] == true,
    combo: (j['combo'] as num?)?.toInt() ?? 0,
    maxStreak: (j['maxStreak'] as num?)?.toInt() ?? 0,
    silentMs: (j['silentMs'] as num?)?.toInt() ?? 0,
    ghost: j['ghost'] == true,
    rating: (j['rating'] as num?)?.toInt(),
    calibrating: j['calibrating'] == true,
    ownerId: j['ownerId'] as String?,
    blocked: j['blocked'] == true,
  );
  final String id, name;
  final int score, shots, hits, combo, maxStreak, silentMs;
  final bool finished, connected, ghost, calibrating;
  final int? rating;

  /// Kayıtlı rakipte koşunun gerçek sahibi (şikâyet/engel hedefi); CPU'da null.
  final String? ownerId;

  /// İzleyici bu oyuncuyu (ghost'ta koşunun sahibini) engellemiş mi?
  final bool blocked;

  DuelPlayer copyWith({
    int? score,
    int? shots,
    int? hits,
    int? combo,
    int? maxStreak,
    bool? finished,
  }) => DuelPlayer(
    id: id,
    name: name,
    score: score ?? this.score,
    shots: shots ?? this.shots,
    hits: hits ?? this.hits,
    finished: finished ?? this.finished,
    connected: connected,
    combo: combo ?? this.combo,
    maxStreak: maxStreak ?? this.maxStreak,
    silentMs: silentMs,
    ghost: ghost,
    rating: rating,
    calibrating: calibrating,
    ownerId: ownerId,
    blocked: blocked,
  );
}

/// Sunucunun bu oyuncu için kabul ettiği son durum (`duel.me`). Bir şut
/// reddedilince yerel oyun sayaçlarını buna göre yeniden hizalar.
class DuelSelfState {
  const DuelSelfState({
    required this.score,
    required this.shots,
    required this.hits,
    required this.misses,
    required this.streak,
    required this.maxStreak,
    required this.feverHits,
    required this.fever,
    required this.feverT,
    required this.lastT,
    required this.lastRt,
    required this.lastStage,
  });
  factory DuelSelfState.fromJson(Map<String, dynamic> j) {
    int n(String k) => (j[k] as num?)?.toInt() ?? 0;
    return DuelSelfState(
      score: n('score'),
      shots: n('shots'),
      hits: n('hits'),
      misses: n('misses'),
      streak: n('streak'),
      maxStreak: n('maxStreak'),
      feverHits: n('feverHits'),
      fever: j['fever'] == true,
      feverT: n('feverT'),
      lastT: n('lastT'),
      lastRt: n('lastRt'),
      lastStage: (j['lastStage'] as String?) ?? 'street',
    );
  }
  final int score, shots, hits, misses, streak, maxStreak, feverHits;
  final bool fever;

  /// Kral Modu'nun başladığı `rt` (ms); son olayın vuruş ve sonuçlanma anları.
  final int feverT, lastT, lastRt;
  final String lastStage;
}

class DuelRematch {
  const DuelRematch({
    required this.expiresAt,
    required this.mine,
    required this.theirs,
    this.duelId,
  });
  factory DuelRematch.fromJson(Map<String, dynamic> j) => DuelRematch(
    expiresAt: (j['expiresAtMs'] as num).toInt(),
    mine: j['mine'] == true,
    theirs: j['theirs'] == true,
    duelId: j['duelId'] as String?,
  );
  final int expiresAt;
  final bool mine, theirs;
  final String? duelId;
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
    this.kind = 'live',
    this.ghostSource,
    this.ghostEvents,
    this.winnerId,
    this.reason,
    this.draw = false,
    this.xp,
    this.ratingBefore,
    this.ratingAfter,
    this.ratingCounted = false,
    this.rematch,
    this.me,
  });
  factory DuelSnapshot.fromResponse(Map<String, dynamic> response) {
    final j = response['duel'] as Map<String, dynamic>;
    final players = (j['players'] as List)
        .map((p) => DuelPlayer.fromJson(p as Map<String, dynamic>))
        .toList();
    final kind = (j['kind'] as String?) ?? 'live';
    if (players.length != 2 ||
        players[0].id == players[1].id ||
        !['live', 'ghost'].contains(kind) ||
        // Ghost maçında tam olarak bir insan + bir kayıtlı koşu vardır.
        players.where((p) => p.ghost).length != (kind == 'ghost' ? 1 : 0) ||
        !['countdown', 'live', 'finished'].contains(j['status'])) {
      throw const FormatException('Invalid duel snapshot');
    }
    final result = j['result'] as Map<String, dynamic>?;
    final ghost = j['ghost'] as Map<String, dynamic>?;
    final rematch = j['rematch'] as Map<String, dynamic>?;
    final me = j['me'] as Map<String, dynamic>?;
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
      kind: kind,
      ghostSource: ghost?['source'] as String?,
      ghostEvents: (ghost?['events'] as List?)
          ?.map((e) => ShotRecord.fromJson(e as Map<String, dynamic>))
          .toList(),
      winnerId: result?['winnerId'] as String?,
      reason: result?['reason'] as String?,
      draw: result?['draw'] == true,
      xp: (result?['xp'] as num?)?.toInt(),
      ratingBefore: (result?['ratingBefore'] as num?)?.toInt(),
      ratingAfter: (result?['ratingAfter'] as num?)?.toInt(),
      ratingCounted: result?['ratingCounted'] == true,
      rematch: rematch == null ? null : DuelRematch.fromJson(rematch),
      me: me == null ? null : DuelSelfState.fromJson(me),
    );
  }
  final String id, nonce, status, kind;
  final int seed, startsAt, endsAt, serverNow, acceptedSeq;
  final List<DuelPlayer> players;
  final List<ShotRecord> events;
  final String? ghostSource;
  final List<ShotRecord>? ghostEvents;
  final String? winnerId, reason;
  final bool draw, ratingCounted;
  final int? xp, ratingBefore, ratingAfter;
  final DuelRematch? rematch;
  final DuelSelfState? me;
  bool get finished => status == 'finished';
  bool get isGhost => kind == 'ghost';
  OpponentKind get opponentKind => !isGhost
      ? OpponentKind.live
      : (ghostSource == 'cpu' ? OpponentKind.cpu : OpponentKind.recorded);
  DuelPlayer player(String id) => players.singleWhere((p) => p.id == id);
  DuelPlayer opponent(String id) => players.singleWhere((p) => p.id != id);
}

/// Kayıtlı koşuyu (ghost) maç saatine göre oynatır: her olay kendi `t`
/// anında (koşu başından ms) bir kez verilir. Sıra `t`'ye göredir; aynı `t`
/// için `seq`. Geri sarma yoktur.
class GhostPlayback {
  GhostPlayback(List<ShotRecord> events)
    : events = List.unmodifiable(
        [...events]..sort(
          (a, b) => a.t != b.t ? a.t.compareTo(b.t) : a.seq.compareTo(b.seq),
        ),
      );
  final List<ShotRecord> events;
  int _next = 0;

  /// Şimdiye kadar oynatılan son olay (ghost'un güncel skoru/combo'su).
  ShotRecord? get latest => _next == 0 ? null : events[_next - 1];
  bool get done => _next >= events.length;
  int get played => _next;

  /// `elapsedMs` anına kadar sırası gelmiş, henüz verilmemiş olaylar.
  List<ShotRecord> due(int elapsedMs) {
    final out = <ShotRecord>[];
    while (_next < events.length && events[_next].t <= elapsedMs) {
      out.add(events[_next++]);
    }
    return out;
  }

  /// Ghost oyuncusunun `latest` olaya göre güncel görünümü.
  DuelPlayer apply(DuelPlayer base) {
    final e = latest;
    if (e == null) {
      return base.copyWith(score: 0, shots: 0, hits: 0, combo: 0, maxStreak: 0);
    }
    return base.copyWith(
      score: e.score,
      shots: e.shots,
      hits: e.hits,
      combo: e.streak,
      maxStreak: e.maxStreak,
    );
  }
}
