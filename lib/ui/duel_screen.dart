import 'dart:async';
import 'dart:math';
import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import '../duel/duel_api.dart';
import '../duel/duel_controller.dart';
import '../duel/duel_protocol.dart';
import '../game/sut_ve_gol_game.dart';
import '../game/sfx.dart';
import '../services/auth_service.dart';
import 'theme.dart';
import 'widgets.dart';

class DuelScreen extends StatefulWidget {
  const DuelScreen({
    super.key,
    this.controller,
    this.renderGames = true,
    this.initialDuelId,
  });
  final DuelController? controller;
  final bool renderGames;

  /// Rövanş: kuyruğa girmeden bu maça bağlanır.
  final String? initialDuelId;
  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> with WidgetsBindingObserver {
  late final DuelController _c =
      widget.controller ??
      DuelController(
        userId: AuthService.instance.user!.id,
        api: HttpDuelApi(),
        initialDuelId: widget.initialDuelId,
      );
  SutVeGolGame? _mine, _replica;
  bool _loaded = false, _started = false, _closing = false, _rematched = false;
  Timer? _clock;
  final List<ShotRecord> _pending = [];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _c.addListener(_changed);
    _c.onRemoteShot = (e) {
      if (_loaded && _started) {
        _replica?.applyRemoteShot(e);
      } else {
        _pending.add(e);
      }
    };
    _clock = Timer.periodic(const Duration(seconds: 1), (_) => _c.tick());
    scheduleMicrotask(() {
      if (mounted) _c.start();
    });
  }

  void _changed() {
    if (!mounted) return;
    final s = _c.snapshot;
    if (s != null && _mine == null && widget.renderGames) {
      _mine = SutVeGolGame(mode: GameMode.duel, seed: s.seed)
        ..onShotResolved = _c.addShot
        ..onRunFinished = ((_) {
          _c.endRun();
          _mine?.pauseEngine();
        });
      _replica = SutVeGolGame(mode: GameMode.replica, seed: s.seed)
        ..onRunFinished = ((_) => _replica?.pauseEngine());
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await Future.wait([_mine!.loaded, _replica!.loaded]);
          if (!mounted) return;
          _loaded = true;
          _updateGames();
          setState(() {});
        } catch (_) {
          if (mounted) {
            setState(
              () => _c.error =
                  'Saha hazırlanamadı. Düellodan çıkıp yeniden dene.',
            );
          }
        }
      });
    }
    _updateGames();
    final rematchId = s?.rematch?.duelId;
    if (rematchId != null && !_rematched) {
      _rematched = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => DuelScreen(
              initialDuelId: rematchId,
              renderGames: widget.renderGames,
            ),
          ),
        );
      });
    }
    setState(() {});
  }

  void _updateGames() {
    if (!_loaded) return;
    if (!_started && [DuelPhase.live, DuelPhase.settling].contains(_c.phase)) {
      _started = true;
      _mine!.startRun();
      _replica!.startRun();
      for (final e in _pending) {
        _replica!.applyRemoteShot(e);
      }
      _pending.clear();
    }
    if ([
      DuelPhase.settling,
      DuelPhase.finished,
      DuelPhase.left,
    ].contains(_c.phase)) {
      _mine!.finishRun();
      _replica!.finishRun();
      _mine!.pauseEngine();
      _replica!.pauseEngine();
      Sfx.stopFeverLoop();
      Sfx.stopAmbience();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      if (!_c.terminal && _c.phase != DuelPhase.settling) {
        if (_mine?.state != GameState.gameOver) _mine?.resumeEngine();
        if (_replica?.state != GameState.gameOver) _replica?.resumeEngine();
        if (_mine != null && _mine!.state != GameState.gameOver) {
          Sfx.startAmbience(_mine!.stage);
        }
      }
      _c.resume();
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden ||
        state == AppLifecycleState.detached) {
      _mine?.pauseEngine();
      _replica?.pauseEngine();
      _c.suspend();
      Sfx.stopFeverLoop();
      Sfx.stopAmbience();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _clock?.cancel();
    _c.removeListener(_changed);
    _c.onRemoteShot = null;
    if (!_c.terminal) {
      unawaited(_c.leave());
    }
    if (widget.controller == null) _c.dispose();
    _mine?.pauseEngine();
    _replica?.pauseEngine();
    Sfx.stopFeverLoop();
    Sfx.stopAmbience();
    super.dispose();
  }

  Future<void> _leave() async {
    if (_closing) return;
    if (_c.terminal || _c.phase == DuelPhase.error) {
      Navigator.of(context).pop();
      return;
    }
    final inMatch = _c.snapshot != null;
    if (inMatch) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: FK.navy2,
          title: const Text('Düellodan çık?'),
          content: const Text(
            'Çıkarsan bu maçı rakibin kazanır. Maçın süresi durmaz.',
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('OYUNDA KAL'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('ÇIK'),
            ),
          ],
        ),
      );
      if (confirmed != true || !mounted) return;
    }
    setState(() => _closing = true);
    final left = await _c.leave();
    if (!mounted) return;
    setState(() => _closing = false);
    if (left) Navigator.of(context).pop();
  }

  void _again() {
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => const DuelScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = _c.snapshot;
    return PopScope(
      canPop: _c.terminal || _c.phase == DuelPhase.error,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _leave();
      },
      child: Scaffold(
        backgroundColor: FK.navy,
        body: SafeArea(
          child: Stack(
            children: [
              const Positioned.fill(
                child: CustomPaint(painter: _PitchPainter()),
              ),
              Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(left: 16, right: 8),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.sports_soccer_rounded,
                          color: FK.orange,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'ONLINE DÜELLO',
                            style: FK.t(
                              size: 16,
                              w: FontWeight.w700,
                              spacing: 1,
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _closing ? null : _leave,
                          tooltip: 'Düellodan çık',
                          icon: const Icon(Icons.close_rounded),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: s == null
                        ? _lobby()
                        : Stack(
                            children: [
                              Column(
                                children: [
                                  Expanded(
                                    child: _field(
                                      _c.opponentView!,
                                      _replica,
                                      opponent: true,
                                    ),
                                  ),
                                  _versus(s),
                                  Expanded(
                                    child: _field(
                                      s.player(_c.userId),
                                      _mine,
                                      opponent: false,
                                    ),
                                  ),
                                ],
                              ),
                              if (!_loaded &&
                                  widget.renderGames &&
                                  _c.phase != DuelPhase.finished)
                                const Positioned.fill(
                                  child: ColoredBox(
                                    color: Color(0xD90B1226),
                                    child: Center(
                                      child: CircularProgressIndicator(
                                        color: FK.orange,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_c.phase == DuelPhase.countdown &&
                                  (_loaded || !widget.renderGames))
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: Center(
                                      child: AnimatedSwitcher(
                                        duration:
                                            MediaQuery.disableAnimationsOf(
                                              context,
                                            )
                                            ? Duration.zero
                                            : const Duration(milliseconds: 220),
                                        child: Column(
                                          key: ValueKey(_c.countdown),
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${_c.countdown}',
                                              style: FK.t(
                                                size: 100,
                                                w: FontWeight.w700,
                                                color: FK.amber,
                                              ),
                                            ),
                                            if (s.isGhost) _ghostChip(s),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              if (_c.phase == DuelPhase.finished)
                                Positioned.fill(child: _result(s)),
                            ],
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _lobby() => Center(
    child: SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 440),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: FK.navy2,
                border: Border.all(color: FK.orange, width: 2),
              ),
              child: const Icon(
                Icons.sports_soccer_rounded,
                size: 48,
                color: FK.amber,
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _c.phase == DuelPhase.error
                  ? 'Bağlantı kurulamadı'
                  : 'Rakibin kim olacak?',
              textAlign: TextAlign.center,
              style: FK.t(size: 30, w: FontWeight.w700),
            ),
            const SizedBox(height: 12),
            Text(
              '90 saniye ortak süre. Şut başına 5 saniye. '
              'Iskalamak seriyi bozar; üst üste goller x2, x3 puan.',
              textAlign: TextAlign.center,
              style: FK.t(size: 17, color: FK.muted, height: 1.4),
            ),
            const SizedBox(height: 28),
            if (_c.phase != DuelPhase.error) ...[
              const SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(
                  strokeWidth: 3,
                  color: FK.orange,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Canlı rakip aranıyor… ${_c.searchElapsedMs ~/ 1000} sn',
                style: FK.t(size: 17, w: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Text(
                '15 saniyede canlı rakip bulunamazsa gerçek bir oyuncunun '
                'kayıtlı koşusuna karşı oynarsın.',
                textAlign: TextAlign.center,
                style: FK.t(size: 14, color: FK.muted, height: 1.4),
              ),
            ],
            if (_c.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 16),
                child: Text(
                  _c.error!,
                  textAlign: TextAlign.center,
                  style: FK.t(color: FK.muted, height: 1.4),
                ),
              ),
            const SizedBox(height: 28),
            if (_c.phase == DuelPhase.error)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: PillButton(
                  label: 'YENİDEN DENE',
                  icon: Icons.refresh_rounded,
                  onTap: _c.start,
                  height: 52,
                ),
              ),
            PillButton(
              label: _closing ? 'ÇIKILIYOR…' : 'VAZGEÇ',
              icon: Icons.arrow_back_rounded,
              primary: false,
              onTap: _leave,
              enabled: !_closing,
              height: 52,
            ),
          ],
        ),
      ),
    ),
  );

  String _opponentLabel(DuelSnapshot s) => switch (s.opponentKind) {
    OpponentKind.live => 'RAKİBİN',
    OpponentKind.recorded => 'KAYITLI RAKİP',
    OpponentKind.cpu => 'CPU KOŞUSU',
  };

  /// Ghost maçını insan gibi göstermez: kaynağı açıkça yazar.
  Widget _ghostChip(DuelSnapshot s) => Container(
    margin: const EdgeInsets.only(top: 8),
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: FK.navy.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(14),
      border: Border.all(color: FK.cyan.withValues(alpha: .5)),
    ),
    child: Text(
      s.opponentKind == OpponentKind.cpu
          ? 'CPU koşusu · bilgisayar'
          : 'Kayıtlı rakip · ${s.opponent(_c.userId).name}',
      textAlign: TextAlign.center,
      style: FK.t(size: 13, w: FontWeight.w600, color: FK.cyan),
    ),
  );

  Widget _badge(String text, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: FK.navy.withValues(alpha: .9),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(
      text,
      style: FK.t(size: 12, w: FontWeight.w700, color: color),
    ),
  );

  Widget _field(DuelPlayer p, SutVeGolGame? game, {required bool opponent}) {
    final s = _c.snapshot!;
    final lost = opponent && !s.isGhost && !p.connected && !s.finished;
    return ClipRect(
      child: Stack(
        children: [
          if (game != null)
            Positioned.fill(
              child: RepaintBoundary(
                child: IgnorePointer(
                  ignoring: opponent || _c.phase != DuelPhase.live,
                  child: GameWidget<SutVeGolGame>(
                    key: ValueKey(game),
                    game: game,
                  ),
                ),
              ),
            ),
          Positioned(
            left: 12,
            top: 8,
            right: 12,
            child: Row(
              children: [
                _badge(
                  opponent ? _opponentLabel(s) : 'SENİN SAHAN',
                  opponent ? FK.cyan : FK.amber,
                ),
                const Spacer(),
                if (lost)
                  Flexible(
                    child: _badge(
                      'BAĞLANTI KOPTU · '
                      '${max(0, ((kForfeitSilentMs - p.silentMs) / 1000).ceil())} sn',
                      FK.red,
                    ),
                  )
                else if (p.finished)
                  _badge('KOŞU BİTTİ', FK.muted),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _versus(DuelSnapshot s, {bool clock = true}) {
    final me = s.player(_c.userId), them = _c.opponentView!;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: const BoxDecoration(
        gradient: FK.surface,
        border: Border(
          top: BorderSide(color: FK.glassBorder),
          bottom: BorderSide(color: FK.glassBorder),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(child: _playerScore(me, FK.amber)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Column(
                  children: [
                    Text(
                      _c.phase == DuelPhase.settling ? 'SONUÇ' : 'SÜRE',
                      style: FK.t(size: 11, color: FK.muted, spacing: 1),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_c.secondsLeft ~/ 60}:${(_c.secondsLeft % 60).toString().padLeft(2, '0')}',
                      style: FK.t(size: 24, w: FontWeight.w700),
                    ),
                  ],
                ),
              ),
              Expanded(child: _playerScore(them, FK.cyan)),
            ],
          ),
          if (clock) ...[
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: _c.secondsLeft / kDuelSeconds,
              minHeight: 3,
              color: FK.orange,
              backgroundColor: FK.glass,
            ),
          ],
          if (clock && !_c.connected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                'Bağlantı yenileniyor. Şutların saklanıyor.',
                textAlign: TextAlign.center,
                style: FK.t(size: 12, color: FK.amber),
              ),
            ),
        ],
      ),
    );
  }

  Widget _playerScore(DuelPlayer p, Color color) => Column(
    children: [
      Text(
        p.ghost ? '${p.name} (kayıt)' : p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FK.t(size: 14, w: FontWeight.w600),
      ),
      Text(
        '${p.score}',
        style: FK.t(size: 30, w: FontWeight.w700, color: color),
      ),
      Semantics(
        label: 'Combo ${p.combo}',
        child: Text(
          p.combo >= 2 ? 'COMBO x${min(3, p.combo)}' : 'COMBO —',
          style: FK.t(
            size: 12,
            w: FontWeight.w700,
            color: p.combo >= 2 ? FK.gold : FK.muted,
          ),
        ),
      ),
    ],
  );

  String _resultLine(DuelSnapshot s, bool won) {
    switch (s.reason) {
      case 'disconnect':
        return won
            ? 'Rakibin bağlantısı 30 saniye kesik kaldı; hükmen kazandın.'
            : 'Bağlantın 30 saniye kesik kaldı; maç hükmen bitti.';
      case 'forfeit':
        return won
            ? 'Rakibin maçtan ayrıldı.'
            : 'Maçtan ayrıldığın için sonuç hükmen yazıldı.';
    }
    if (s.draw) return 'Aynı skor, aynı isabet.';
    return won
        ? 'Bu sahanın yıldızı sensin.'
        : 'Bir sonraki maç senin olabilir.';
  }

  Widget _statRow(String label, String mine, String theirs) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 4),
    child: Row(
      children: [
        Expanded(
          child: Text(
            mine,
            textAlign: TextAlign.center,
            style: FK.t(size: 18, w: FontWeight.w700, color: FK.amber),
          ),
        ),
        Expanded(
          flex: 2,
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: FK.t(size: 13, color: FK.muted),
          ),
        ),
        Expanded(
          child: Text(
            theirs,
            textAlign: TextAlign.center,
            style: FK.t(size: 18, w: FontWeight.w700, color: FK.cyan),
          ),
        ),
      ],
    ),
  );

  Widget _result(DuelSnapshot s) {
    final won = s.winnerId == _c.userId;
    final me = s.player(_c.userId), them = s.opponent(_c.userId);
    final r = s.rematch;
    final rating =
        s.ratingCounted && s.ratingBefore != null && s.ratingAfter != null
        ? 'Puan ${s.ratingBefore} → ${s.ratingAfter} '
              '(${s.ratingAfter! - s.ratingBefore! >= 0 ? '+' : ''}${s.ratingAfter! - s.ratingBefore!})'
              '${me.calibrating ? ' · kalibrasyon' : ''}'
        : (s.isGhost
              ? 'Kayıtlı rakip maçları sıralamaya sayılmaz.'
              : 'Bu maç sıralamaya sayılmadı.');
    return ColoredBox(
      color: FK.navy.withValues(alpha: .95),
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  s.draw
                      ? Icons.handshake_rounded
                      : (won
                            ? Icons.emoji_events_rounded
                            : Icons.sports_soccer_rounded),
                  color: won ? FK.gold : FK.cyan,
                  size: 56,
                ),
                const SizedBox(height: 12),
                Text(
                  s.draw ? 'BERABERE' : (won ? 'KAZANDIN!' : 'GÜZEL MAÇTI'),
                  textAlign: TextAlign.center,
                  style: FK.t(
                    size: 34,
                    w: FontWeight.w700,
                    color: won ? FK.amber : FK.text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _resultLine(s, won),
                  textAlign: TextAlign.center,
                  style: FK.t(size: 15, color: FK.muted, height: 1.4),
                ),
                const SizedBox(height: 4),
                if (s.isGhost)
                  _ghostChip(s)
                else
                  Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: _badge('CANLI RAKİP · ${them.name}', FK.cyan),
                  ),
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    gradient: FK.surface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: FK.glassBorder),
                  ),
                  child: Column(
                    children: [
                      _statRow('SKOR', '${me.score}', '${them.score}'),
                      _statRow(
                        'İSABET',
                        '${me.hits}/${me.shots}',
                        '${them.hits}/${them.shots}',
                      ),
                      _statRow(
                        'EN UZUN COMBO',
                        '${me.maxStreak}',
                        '${them.maxStreak}',
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _badge('+${s.xp ?? 0} XP', FK.gold),
                    _badge(rating, s.ratingCounted ? FK.text : FK.muted),
                  ],
                ),
                const SizedBox(height: 20),
                if (r != null && (_c.rematchOpen || r.duelId != null)) ...[
                  if (r.theirs && !r.mine)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Text(
                        'Rakibin rövanş istiyor!',
                        style: FK.t(
                          size: 15,
                          w: FontWeight.w700,
                          color: FK.amber,
                        ),
                      ),
                    ),
                  PillButton(
                    label: r.duelId != null
                        ? 'RÖVANŞ BAŞLIYOR…'
                        : (r.mine
                              ? 'RAKİP BEKLENİYOR (${_c.rematchSecondsLeft})'
                              : 'RÖVANŞ (${_c.rematchSecondsLeft})'),
                    icon: Icons.replay_rounded,
                    onTap: _c.requestRematch,
                    enabled: !r.mine && !_c.rematchBusy && r.duelId == null,
                    height: 56,
                    width: double.infinity,
                  ),
                  const SizedBox(height: 12),
                ],
                PillButton(
                  label: 'YENİ RAKİP',
                  icon: Icons.sports_soccer_rounded,
                  onTap: _again,
                  primary: r == null || !_c.rematchOpen,
                  height: 52,
                  width: double.infinity,
                ),
                const SizedBox(height: 12),
                PillButton(
                  label: 'TEK KİŞİLİK OYUNA DÖN',
                  icon: Icons.arrow_back_rounded,
                  primary: false,
                  onTap: () => Navigator.of(context).pop(),
                  height: 48,
                  width: double.infinity,
                  fontSize: 15,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PitchPainter extends CustomPainter {
  const _PitchPainter();
  @override
  void paint(Canvas canvas, Size size) {
    final r = Rect.fromLTWH(
      20,
      60,
      max(0, size.width - 40),
      max(0, size.height - 100),
    );
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1
      ..color = FK.cyan.withValues(alpha: .08);
    canvas.drawRRect(RRect.fromRectAndRadius(r, const Radius.circular(20)), p);
    canvas.drawCircle(r.center, min(size.width * .22, 90), p);
    canvas.drawLine(
      Offset(r.left, r.center.dy),
      Offset(r.right, r.center.dy),
      p,
    );
  }

  @override
  bool shouldRepaint(covariant _PitchPainter oldDelegate) => false;
}
