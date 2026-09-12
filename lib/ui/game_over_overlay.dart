import 'dart:math';

import 'package:flutter/material.dart';

import '../game/sut_ve_gol_game.dart';
import '../game/sfx.dart';
import 'leaderboard_screen.dart';
import 'led_painter.dart';
import 'theme.dart';
import 'widgets.dart';

/// Oyun sonu perdesi: bulanık karartma, üstte çıkış, cam kart (sayaçla artan
/// skor, rekor, sahne), sıra paneli ve "TEKRAR OYNA" hap butonu.
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({super.key, required this.game});
  final SutVeGolGame game;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
  )..forward();
  late final AnimationController _count = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  );
  bool _rankReady = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _count.forward();
    });
    Future.delayed(const Duration(milliseconds: 1400), Sfx.countEnd);
    Future.delayed(const Duration(milliseconds: 1700), () {
      if (mounted) setState(() => _rankReady = true);
    });
  }

  @override
  void dispose() {
    _fade.dispose();
    _count.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final rank = game.best;
    final isRecord = game.score > 0 && game.score >= game.best;
    return LayoutBuilder(
      builder: (context, c) {
        final s = min(c.maxWidth / 440, c.maxHeight / 760).clamp(0.0, 1.0);
        final top = MediaQuery.paddingOf(context).top;
        return FadeTransition(
          opacity: _fade,
          child: Stack(
            children: [
              const DimBackdrop(),
              Positioned(
                left: 18 * s,
                top: top + 12 * s,
                child: RoundButton(
                  icon: Icons.logout_rounded,
                  size: 50 * s,
                  onTap: () => game.onExit?.call(),
                ),
              ),
              Positioned(
                left: 24 * s,
                right: 24 * s,
                top: 250 * s,
                child: ScaleTransition(
                  scale: CurvedAnimation(
                    parent: _fade,
                    curve: Curves.easeOutBack,
                  ),
                  child: _card(s, game, rank, isRecord),
                ),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 560 * s,
                child: Center(
                  child: PillButton(
                    label: 'TEKRAR OYNA',
                    icon: Icons.replay_rounded,
                    onTap: game.restart,
                    height: 60 * s,
                    fontSize: 19 * s,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _card(double s, SutVeGolGame game, int rank, bool isRecord) {
    return GlassCard(
      radius: 26 * s,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            height: 46 * s,
            decoration: BoxDecoration(
              gradient: FK.fire,
              borderRadius: BorderRadius.vertical(top: Radius.circular(26 * s)),
            ),
            alignment: Alignment.center,
            child: Text(
              'OYUN BİTTİ',
              style: FK.t(size: 20 * s, w: FontWeight.w700, spacing: 3 * s),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(20 * s, 18 * s, 16 * s, 22 * s),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: AnimatedBuilder(
                    animation: _count,
                    builder: (_, child) {
                      final k = Curves.easeOutCubic.transform(_count.value);
                      final sc = (game.score * k).round();
                      final bs = max(sc, (game.best * k).round());
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'SKOR',
                            style: FK.t(
                              size: 12 * s,
                              w: FontWeight.w600,
                              color: FK.muted,
                              spacing: 2 * s,
                            ),
                          ),
                          SizedBox(height: 4 * s),
                          LedDigits(
                            value: sc,
                            height: 36 * s,
                            width: 190 * s,
                            color: Colors.white,
                          ),
                          SizedBox(height: 14 * s),
                          Row(
                            children: [
                              Icon(
                                Icons.emoji_events_rounded,
                                color: FK.gold,
                                size: 16 * s,
                              ),
                              SizedBox(width: 6 * s),
                              Text(
                                'REKOR',
                                style: FK.t(
                                  size: 12 * s,
                                  w: FontWeight.w600,
                                  color: FK.muted,
                                  spacing: 2 * s,
                                ),
                              ),
                              if (isRecord && _rankReady) ...[
                                SizedBox(width: 8 * s),
                                Chip2(
                                  'YENİ!',
                                  color: FK.green,
                                  fontSize: 10 * s,
                                ),
                              ],
                            ],
                          ),
                          SizedBox(height: 4 * s),
                          LedDigits(
                            value: bs,
                            height: 26 * s,
                            width: 140 * s,
                            color: FK.gold,
                          ),
                          SizedBox(height: 12 * s),
                          Row(
                            children: [
                              Container(
                                width: 8 * s,
                                height: 8 * s,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  color: game.stage.accent,
                                ),
                              ),
                              SizedBox(width: 6 * s),
                              Text(
                                game.stage.label,
                                style: FK.t(
                                  size: 12 * s,
                                  w: FontWeight.w700,
                                  color: game.stage.accent,
                                  spacing: 2 * s,
                                ),
                              ),
                            ],
                          ),
                        ],
                      );
                    },
                  ),
                ),
                _rankPanel(s, game, rank),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rankPanel(double s, SutVeGolGame game, int rank) => GestureDetector(
    onTap: () => Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => LeaderboardScreen(myScore: game.score)),
    ),
    child: Container(
      width: 128 * s,
      padding: EdgeInsets.symmetric(vertical: 14 * s),
      decoration: BoxDecoration(
        color: FK.glass,
        borderRadius: BorderRadius.circular(18 * s),
        border: Border.all(color: FK.glassBorder),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AvatarCircle(
            'Oyuncu',
            size: 64 * s,
            ring: FK.orange,
            ringWidth: 3 * s,
          ),
          Transform.translate(
            offset: Offset(0, -10 * s),
            child: Chip2('${_rankReady ? rank : '—'}', fontSize: 11 * s),
          ),
          Text(
            'REKOR',
            style: FK.t(
              size: 10 * s,
              w: FontWeight.w600,
              color: FK.muted,
              spacing: 1.5 * s,
            ),
          ),
          SizedBox(height: 4 * s),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Gör',
                style: FK.t(size: 13 * s, w: FontWeight.w700, color: FK.amber),
              ),
              Icon(Icons.chevron_right_rounded, size: 18 * s, color: FK.amber),
            ],
          ),
        ],
      ),
    ),
  );
}
