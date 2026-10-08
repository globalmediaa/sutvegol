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
/// invents an opponent or calls a failed request a successful result.
class DuelController extends ChangeNotifier {
  DuelController({
    required this.userId,
    required this.api,
    int Function()? now,
    this.pollInterval = const Duration(milliseconds: 700),
    this.autoPoll = true,
  }) : _now = now ?? (() => DateTime.now().millisecondsSinceEpoch);
  final String userId;
  final DuelApi api;
  final int Function() _now;
  final Duration pollInterval;
  final bool autoPoll;
  DuelPhase phase = DuelPhase.idle;
  DuelSnapshot? snapshot;
  String? error;
  bool connected = true, suspended = false, _disposed = false, _busy = false;
  bool _runEnded = false, _finishSent = false;
  int _offset = 0, _errors = 0, _epoch = 0, lastReceivedSeq = 0;
  Timer? _timer;
  Completer<void>? _syncDone;
  final List<ShotRecord> _outbox = [];
  void Function(ShotRecord)? onRemoteShot;
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
  bool get terminal => [DuelPhase.finished, DuelPhase.left].contains(phase);

  Future<void> start() async {
    if (_disposed ||
        _busy ||
        ![DuelPhase.idle, DuelPhase.error].contains(phase)) {
      return;
    }
    phase = DuelPhase.searching;
    error = null;
    connected = true;
    _notify();
    await synchronize();
  }

  void addShot(ShotRecord shot) {
    if (_disposed ||
        terminal ||
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
    _notify();
  }

  Future<void> resume() async {
    if (_disposed || terminal) return;
    suspended = false;
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
    _outbox.removeWhere((e) => e.seq <= s.acceptedSeq);
    for (final e in s.events) {
      if (e.seq <= lastReceivedSeq) continue;
      onRemoteShot?.call(e);
      lastReceivedSeq = e.seq;
    }
    _refreshPhase();
  }

  void _refreshPhase() {
    final s = snapshot;
    if (s == null || terminal) return;
    if (s.finished) {
      phase = DuelPhase.finished;
      _timer?.cancel();
      _timer = null;
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
    if (_disposed || suspended || terminal) return;
    _refreshPhase();
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
    try {
      final began = _now();
      final s = snapshot;
      DuelSnapshot? next;
      if (s == null) {
        next = await api.queue();
      } else if (_outbox.isNotEmpty) {
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
        next = await api.poll(s.id, lastReceivedSeq);
      }
      if (_disposed || epoch != _epoch) return;
      if (next != null) _accept(next, began, _now());
      _errors = 0;
      connected = true;
      error = null;
    } catch (e) {
      if (_disposed || epoch != _epoch) return;
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
        if (autoPoll && !suspended && !terminal && phase != DuelPhase.error) {
          final delay = _errors == 0
              ? pollInterval
              : Duration(seconds: min(8, 1 << min(_errors, 3)));
          _timer = Timer(delay, synchronize);
        }
      }
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
    onRemoteShot = null;
    _outbox.clear();
    super.dispose();
  }
}
