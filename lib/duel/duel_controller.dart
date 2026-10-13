import 'dart:async';
import 'dart:math';
import 'package:flutter/foundation.dart';
import '../game/shot_record.dart';
import '../services/api_client.dart';
import 'duel_api.dart';
import 'duel_protocol.dart';

enum DuelPhase {
  idle,
  searching,
  countdown,
  live,
  settling,
  finished,
  left,
  error,
}

/// One serialized network loop, bounded outbox and server clock. It never
/// invents an opponent or calls a failed request a successful result. A
/// recorded opponent (ghost) comes from the server as a real finished run and
/// is played back by match time; the UI labels it as such.
class DuelController extends ChangeNotifier {
  DuelController({
    required this.userId,
    required this.api,
    int Function()? now,
    this.pollInterval = const Duration(milliseconds: 700),
    this.ghostInterval = const Duration(milliseconds: 100),
    this.autoPoll = true,
    this.initialDuelId,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);
  final String userId;
  final DuelApi api;
  final int Function() _now;
  final Duration pollInterval, ghostInterval;
  final bool autoPoll;

  /// Rövanş: kuyruğa girmeden doğrudan bu maça bağlanır.
  final String? initialDuelId;
  DuelPhase phase = DuelPhase.idle;
  DuelSnapshot? snapshot;
  GhostPlayback? ghost;
  String? error;
  bool connected = true, suspended = false, _disposed = false, _busy = false;
  bool _runEnded = false, _finishSent = false, rematchBusy = false;
  bool _rematchPolling = false;
  int _offset = 0, _errors = 0, _epoch = 0, lastReceivedSeq = 0;
  int? _searchStartedAt;
  Timer? _timer, _ghostTimer, _rematchTimer;
  Completer<void>? _syncDone;
  final List<ShotRecord> _outbox = [];
  void Function(ShotRecord)? onRemoteShot;

  /// Sunucu bir şutu reddetti (422): yerel oyun sayaçlarını sunucunun kabul
  /// ettiği duruma döndürür; sonraki şutlar bu durumdan devam eder.
  void Function(DuelSelfState state)? onRealign;

  /// Reddedilen (ve onu izleyen, artık geçersiz zincirdeki) şut sayısı.
  int rejectedShots = 0;
  bool _realignPending = false, _fastRetry = false;
  bool get realigning => _realignPending;
  int get pendingShots => _outbox.length;
  int get serverNow => _now() + _offset;
  int get secondsLeft => snapshot == null
      ? kDuelSeconds
      : min(
          kDuelSeconds,
          max(0, ((snapshot!.endsAt - serverNow) / 1000).ceil()),
        );
  int get countdown => snapshot == null
      ? 0
      : max(0, ((snapshot!.startsAt - serverNow) / 1000).ceil());

  /// Sunucu saatine göre maç başından geçen ms (eşleşme yoksa null).
  int? get matchElapsedMs =>
      snapshot == null ? null : serverNow - snapshot!.startsAt;

  /// Kuyrukta geçen süre (lobi: "15 sn içinde canlı rakip yoksa…").
  int get searchElapsedMs =>
      _searchStartedAt == null ? 0 : max(0, _now() - _searchStartedAt!);
  bool get terminal => [DuelPhase.finished, DuelPhase.left].contains(phase);

  /// Rakibin ekranda gösterilecek hali: ghost'ta oynatılan son olaya göre.
  DuelPlayer? get opponentView {
    final s = snapshot;
    if (s == null) return null;
    final o = s.opponent(userId);
    final g = ghost;
    return s.isGhost && g != null && !s.finished ? g.apply(o) : o;
  }

  bool get rematchOpen {
    final s = snapshot, r = snapshot?.rematch;
    return s != null &&
        s.finished &&
        !s.isGhost &&
        r != null &&
        r.duelId == null &&
        serverNow < r.expiresAt;
  }

  int get rematchSecondsLeft {
    final r = snapshot?.rematch;
    return r == null ? 0 : max(0, ((r.expiresAt - serverNow) / 1000).ceil());
  }

  Future<void> start() async {
    if (_disposed ||
        _busy ||
        ![DuelPhase.idle, DuelPhase.error].contains(phase)) {
      return;
    }
    phase = DuelPhase.searching;
    _searchStartedAt = _now();
    error = null;
    connected = true;
    _notify();
    await synchronize();
  }

  void addShot(ShotRecord shot) {
    if (_disposed ||
        terminal ||
        // Ret sonrası yeniden hizalanana dek gelen şutlar eski (reddedilmiş)
        // zincirin devamıdır; sunucu durumundan yeniden numaralanacak.
        _realignPending ||
        _outbox.any((s) => s.seq == shot.seq) ||
        shot.seq <= (snapshot?.acceptedSeq ?? 0)) {
      return;
    }
    if (_outbox.length >= 300) {
      error = 'Bağlantı uzun süredir kesik. Şutlar gönderilemiyor.';
      _notify();
      return;
    }
    _outbox.add(shot);
    _outbox.sort((a, b) => a.seq.compareTo(b.seq));
  }

  void endRun() {
    _runEnded = true;
    _notify();
  }

  void suspend() {
    suspended = true;
    _timer?.cancel();
    _timer = null;
    _ghostTimer?.cancel();
    _ghostTimer = null;
    _notify();
  }

  Future<void> resume() async {
    if (_disposed || terminal) return;
    suspended = false;
    _startGhostTimer();
    await synchronize();
  }

  void _accept(DuelSnapshot s, int started, int ended) {
    if (_disposed) return;
    if (snapshot != null && snapshot!.id != s.id) {
      throw const FormatException('Duel changed');
    }
    s.player(userId); // Reject snapshots which do not belong to this player.
    _offset = s.serverNow - ((started + ended) ~/ 2);
    snapshot = s;
    if (s.isGhost && ghost == null && s.ghostEvents != null) {
      ghost = GhostPlayback(s.ghostEvents!);
      _startGhostTimer();
    }
    _outbox.removeWhere((e) => e.seq <= s.acceptedSeq);
    if (_realignPending) {
      _realignPending = false;
      final me = s.me;
      if (me != null) onRealign?.call(me);
    }
    for (final e in s.events) {
      if (e.seq <= lastReceivedSeq) continue;
      onRemoteShot?.call(e);
      lastReceivedSeq = e.seq;
    }
    _refreshPhase();
  }

  void _startGhostTimer() {
    if (!autoPoll || ghost == null || _ghostTimer != null || terminal) return;
    _ghostTimer = Timer.periodic(ghostInterval, (_) => advanceGhost());
  }

  /// Kayıtlı koşunun sırası gelen şutlarını (t ≤ maç saati) rakip sahasına verir.
  void advanceGhost() {
    final g = ghost, s = snapshot;
    if (_disposed || suspended || g == null || s == null) return;
    final elapsed = serverNow - s.startsAt;
    if (elapsed < 0) return;
    final due = g.due(min(elapsed, kDuelSeconds * 1000));
    for (final e in due) {
      onRemoteShot?.call(e);
    }
    if (due.isNotEmpty) _notify();
  }

  void _refreshPhase() {
    final s = snapshot;
    if (s == null || terminal) return;
    if (s.finished) {
      phase = DuelPhase.finished;
      _timer?.cancel();
      _timer = null;
      _ghostTimer?.cancel();
      _ghostTimer = null;
      if (autoPoll && !s.isGhost && s.rematch != null) {
        _rematchTimer ??= Timer.periodic(pollInterval, (_) => pollRematch());
      }
    } else if (serverNow < s.startsAt) {
      phase = DuelPhase.countdown;
    } else if (serverNow >= s.endsAt) {
      phase = DuelPhase.settling;
      _runEnded = true;
    } else {
      phase = DuelPhase.live;
    }
  }

  /// Called by the UI's once-per-second clock, never by a per-frame rebuild.
  void tick() {
    if (_disposed || suspended) return;
    if (!terminal) {
      advanceGhost();
      _refreshPhase();
    }
    _notify();
  }

  Future<void> synchronize() async {
    if (_disposed ||
        suspended ||
        _busy ||
        terminal ||
        phase == DuelPhase.idle) {
      return;
    }
    _timer?.cancel();
    _timer = null;
    _busy = true;
    _syncDone = Completer<void>();
    final epoch = _epoch;
    var sending = false;
    try {
      final began = _now();
      final s = snapshot;
      DuelSnapshot? next;
      if (s == null) {
        next = initialDuelId != null
            ? await api.poll(initialDuelId!, 0, withGhost: true)
            : await api.queue();
      } else if (_outbox.isNotEmpty) {
        sending = true;
        next = await api.send(
          s.id,
          s.nonce,
          _outbox.take(30).toList(),
          lastReceivedSeq,
        );
      } else if (_runEnded && !_finishSent) {
        next = await api.finish(s.id, s.nonce, lastReceivedSeq);
        _finishSent = true;
      } else {
        next = await api.poll(
          s.id,
          lastReceivedSeq,
          withGhost: s.isGhost && ghost == null,
        );
      }
      if (_disposed || epoch != _epoch) return;
      if (next != null) _accept(next, began, _now());
      _errors = 0;
      connected = true;
      error = null;
    } catch (e) {
      if (_disposed || epoch != _epoch) return;
      if (sending &&
          e is ApiException &&
          (e.status == 422 ||
              ['sequence_gap', 'event_conflict'].contains(e.code))) {
        // Sunucu bir şutu reddetti (shot_clock, score_math, invalid_timing…).
        // Önündeki geçerli şutlar kaydedildi; reddedilen ve sonrakiler eski
        // zincirde kaldı. Paketi tekrar göndermek sonsuza dek aynı reddi
        // alır: düşür, hemen yokla, gelen `me` durumuyla yerel oyunu hizala.
        rejectedShots += _outbox.length;
        _outbox.clear();
        _realignPending = true;
        _fastRetry = true;
        connected = true;
        _errors = 0;
        error = null;
        return;
      }
      connected = false;
      _errors++;
      error = e is ApiException
          ? e.message
          : 'Bağlantı kesildi. Yeniden bağlanılıyor.';
      if (snapshot == null &&
          e is ApiException &&
          [
            'not_configured',
            'unauthorized',
            'username_required',
            'update_required',
            'not_found',
          ].contains(e.code)) {
        phase = DuelPhase.error;
      }
      // An expired match has an authoritative persisted result: get it even
      // if stale buffered events can no longer be accepted.
      if (snapshot != null &&
          e is ApiException &&
          ['match_expired', 'already_finished'].contains(e.code)) {
        _outbox.clear();
        _runEnded = true;
        _finishSent = true;
      }
    } finally {
      _busy = false;
      _syncDone?.complete();
      _syncDone = null;
      if (!_disposed && epoch == _epoch) {
        _refreshPhase();
        _notify();
        final fast = _fastRetry;
        _fastRetry = false;
        if (autoPoll && !suspended && !terminal && phase != DuelPhase.error) {
          final delay = fast
              ? Duration.zero
              : _errors == 0
              ? pollInterval
              : Duration(seconds: min(8, 1 << min(_errors, 3)));
          _timer = Timer(delay, synchronize);
        }
      }
    }
  }

  /// Sonuç ekranında 10 sn: iki taraf da basarsa sunucu aynı rakiple yeni
  /// düello açar ve `snapshot.rematch.duelId` gelir.
  Future<void> requestRematch() async {
    final s = snapshot;
    if (_disposed || s == null || rematchBusy || !rematchOpen) return;
    rematchBusy = true;
    _notify();
    try {
      final began = _now();
      final next = await api.rematch(s.id);
      if (!_disposed && next.id == s.id) {
        _offset = next.serverNow - ((began + _now()) ~/ 2);
        snapshot = next;
      }
      error = null;
    } catch (e) {
      error = e is ApiException ? e.message : 'Rövanş isteği gönderilemedi.';
    } finally {
      rematchBusy = false;
      _notify();
    }
  }

  /// Bitmiş canlı maçın rövanş durumunu (rakip bastı mı, yeni maç açıldı mı)
  /// rövanş süresi boyunca izler.
  Future<void> pollRematch() async {
    final s = snapshot, r = snapshot?.rematch;
    if (_disposed || s == null || _rematchPolling) return;
    if (r == null || r.duelId != null || serverNow > r.expiresAt + 1000) {
      _rematchTimer?.cancel();
      _rematchTimer = null;
      _notify();
      return;
    }
    _rematchPolling = true;
    try {
      final next = await api.poll(s.id, lastReceivedSeq);
      if (!_disposed && next.id == s.id) snapshot = next;
    } catch (_) {
      // Bir sonraki yoklamada yeniden denenir; sonuç zaten kesin.
    } finally {
      _rematchPolling = false;
      _notify();
    }
  }

  Future<bool> leave() async {
    if (_disposed || terminal) return true;
    // Invalidate the in-flight queue response before cancellation. DELETE
    // also handles a match created concurrently on the server.
    _epoch++;
    _timer?.cancel();
    _timer = null;
    try {
      // Wait until an in-flight join has reached the server; cancellation
      // must be the last operation even on a slow/reordered connection.
      await _syncDone?.future;
      final s = snapshot;
      if (s == null) {
        await api.cancelQueue();
      } else {
        await api.forfeit(s.id);
      }
      phase = DuelPhase.left;
      _ghostTimer?.cancel();
      _ghostTimer = null;
      error = null;
      _notify();
      return true;
    } catch (e) {
      error = 'Çıkış sunucuya iletilemedi. Yeniden dene.';
      connected = false;
      if (!_disposed && autoPoll && !suspended && !terminal) {
        _timer = Timer(const Duration(seconds: 2), synchronize);
      }
      _notify();
      return false;
    }
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    _timer?.cancel();
    _timer = null;
    _ghostTimer?.cancel();
    _ghostTimer = null;
    _rematchTimer?.cancel();
    _rematchTimer = null;
    onRemoteShot = null;
    _outbox.clear();
    super.dispose();
  }
}
