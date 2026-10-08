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
  const DuelScreen({super.key, this.controller, this.renderGames = true});
  final DuelController? controller;
  final bool renderGames;
  @override
  State<DuelScreen> createState() => _DuelScreenState();
}

class _DuelScreenState extends State<DuelScreen> with WidgetsBindingObserver {
  late final DuelController _c =
      widget.controller ??
      DuelController(userId: AuthService.instance.user!.id, api: HttpDuelApi());
  SutVeGolGame? _mine, _replica;
  bool _loaded = false, _started = false, _closing = false;
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
    if (_c.terminal) {
      _clock?.cancel();
      _clock = null;
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
                                      s.opponent(_c.userId),
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
                                        child: Text(
                                          '${_c.countdown}',
                                          key: ValueKey(_c.countdown),
                                          style: FK.t(
                                            size: 100,
                                            w: FontWeight.w700,
                                            color: FK.amber,
                                          ),
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
              '90 saniye. 3 can. En yüksek skor kazanır.',
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
                'Gerçek bir oyuncu aranıyor…',
                style: FK.t(size: 17, w: FontWeight.w600),
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

  Widget _field(DuelPlayer p, SutVeGolGame? game, {required bool opponent}) =>
      ClipRect(
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
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: FK.navy.withValues(alpha: .88),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      opponent ? 'RAKİBİN' : 'SENİN SAHAN',
                      style: FK.t(
                        size: 12,
                        w: FontWeight.w700,
                        color: opponent ? FK.cyan : FK.amber,
                      ),
                    ),
                  ),
                  const Spacer(),
                  if (p.finished)
                    Container(
                      padding: const EdgeInsets.all(6),
                      color: FK.navy,
                      child: Text(
                        'KOŞU BİTTİ',
                        style: FK.t(size: 12, color: FK.muted),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _versus(DuelSnapshot s) {
    final me = s.player(_c.userId), them = s.opponent(_c.userId);
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
          const SizedBox(height: 8),
          LinearProgressIndicator(
            value: _c.secondsLeft / kDuelSeconds,
            minHeight: 3,
            color: FK.orange,
            backgroundColor: FK.glass,
          ),
          if (!_c.connected || !them.connected)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                !_c.connected
                    ? 'Bağlantı yenileniyor. Şutların saklanıyor.'
                    : 'Rakibin bağlantısı yenileniyor.',
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
        p.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: FK.t(size: 14, w: FontWeight.w600),
      ),
      Text(
        '${p.score}',
        style: FK.t(size: 30, w: FontWeight.w700, color: color),
      ),
      Semantics(
        label: '${p.lives} can',
        child: FittedBox(
          fit: BoxFit.scaleDown,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 3; i++)
                Icon(
                  i < p.lives
                      ? Icons.favorite_rounded
                      : Icons.favorite_border_rounded,
                  size: 14,
                  color: i < p.lives ? FK.red : FK.muted,
                ),
            ],
          ),
        ),
      ),
    ],
  );

  Widget _result(DuelSnapshot s) {
    final won = s.winnerId == _c.userId;
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
                  size: 64,
                ),
                const SizedBox(height: 20),
                Text(
                  s.draw ? 'BERABERE' : (won ? 'KAZANDIN!' : 'GÜZEL MAÇTI'),
                  textAlign: TextAlign.center,
                  style: FK.t(
                    size: 36,
                    w: FontWeight.w700,
                    color: won ? FK.amber : FK.text,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  s.reason == 'forfeit'
                      ? 'Düello oyuncunun ayrılmasıyla tamamlandı.'
                      : (won
                            ? 'Bu sahanın yıldızı sensin.'
                            : s.draw
                            ? 'Aynı heyecan, aynı skor.'
                            : 'Bir sonraki maç senin olabilir.'),
                  textAlign: TextAlign.center,
                  style: FK.t(size: 16, color: FK.muted, height: 1.4),
                ),
                const SizedBox(height: 24),
                _versus(s),
                const SizedBox(height: 28),
                PillButton(
                  label: 'YENİ RAKİP',
                  icon: Icons.sports_soccer_rounded,
                  onTap: _again,
                  height: 56,
                  width: double.infinity,
                ),
                const SizedBox(height: 12),
                PillButton(
                  label: 'TEK KİŞİLİK OYUNA DÖN',
                  icon: Icons.arrow_back_rounded,
                  primary: false,
                  onTap: () => Navigator.of(context).pop(),
                  height: 52,
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
