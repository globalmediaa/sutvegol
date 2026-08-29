import 'dart:math';

import 'package:flutter/material.dart';

import '../game/kick_legend_game.dart';
import 'leaderboard_screen.dart';
import 'led_painter.dart';
import 'mock_data.dart';
import 'theme.dart';

/// Oyun sonu perdesi: karartma, sol üst çıkış, beyaz kart (sayaçla artan skor),
/// rozet/sıra paneli ve turuncu tekrar butonu. Ölçüler 440 pt referans genişliğe göre.
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({super.key, required this.game});
  final KickLegendGame game;

  @override
  State<GameOverOverlay> createState() => _GameOverOverlayState();
}

class _GameOverOverlayState extends State<GameOverOverlay> with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 300))..forward();
  late final AnimationController _count = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100));
  bool _rankReady = false;

  @override
  void initState() {
    super.initState();
    Future.delayed(const Duration(milliseconds: 250), () {
      if (mounted) _count.forward();
    });
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
    final rank = rankFor(lbEntries(LbTab.season), game.score);
    return LayoutBuilder(builder: (context, c) {
      final s = c.maxWidth / 440;
      return FadeTransition(
        opacity: _fade,
        child: Stack(
          children: [
            Positioned.fill(child: ColoredBox(color: KL.dim.withValues(alpha: 0.72))),
            // Sol üst çıkış.
            Positioned(
              left: 18 * s,
              top: 47 * s,
              child: GestureDetector(
                onTap: () => game.onExit?.call(),
                child: Image.asset('assets/images/btn_exit.png', width: 94 * s),
              ),
            ),
            // Kart.
            Positioned(
              left: 30 * s,
              top: 297 * s,
              width: 380 * s,
              height: 287 * s,
              child: _card(s, game, rank),
            ),
            // Tekrar butonu (kartın alt kenarına biner).
            Positioned(
              left: 220 * s - 47 * s,
              top: 587 * s - 47 * s,
              child: GestureDetector(
                onTap: game.restart,
                child: Container(
                  width: 95 * s,
                  height: 95 * s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12 * s, offset: Offset(0, 6 * s))],
                  ),
                  child: Image.asset('assets/images/btn_replay.png'),
                ),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _card(double s, KickLegendGame game, int rank) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(14 * s),
      child: Container(
        color: Colors.white,
        child: Column(
          children: [
            Container(
              height: 37 * s,
              color: const Color(0xFFCFCFCF),
              alignment: Alignment.center,
              child: Text(
                'GAME OVER',
                style: KL.t(size: 22 * s, w: FontWeight.w700, color: Colors.white, spacing: 1.5 * s).copyWith(
                  shadows: [Shadow(color: Colors.black26, offset: Offset(0, 1 * s), blurRadius: 2 * s)],
                ),
              ),
            ),
            Expanded(
              child: Row(
                children: [
                  Expanded(
                    child: AnimatedBuilder(
                      animation: _count,
                      builder: (_, __) {
                        final k = Curves.easeOutCubic.transform(_count.value);
                        final sc = (game.score * k).round();
                        final bs = max(sc, (game.best * k).round());
                        return Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            _ledRow(s, 'ico_ball.png', sc),
                            SizedBox(height: 14 * s),
                            _ledRow(s, 'ico_trophy.png', bs),
                            SizedBox(height: 40 * s),
                          ],
                        );
                      },
                    ),
                  ),
                  // Sağ panel: avatar, sıra, puan, chevron.
                  GestureDetector(
                    onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => LeaderboardScreen(myScore: game.score)),
                    ),
                    child: Container(
                      width: 125 * s,
                      color: KL.cardGray,
                      child: Stack(
                        children: [
                          Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              SizedBox(height: 18 * s),
                              Container(
                                width: 74 * s,
                                height: 74 * s,
                                decoration: BoxDecoration(
                                  shape: BoxShape.circle,
                                  border: Border.all(color: Colors.white, width: 3 * s),
                                  image: const DecorationImage(image: AssetImage('assets/images/avatar_you.png'), fit: BoxFit.cover),
                                ),
                              ),
                              Transform.translate(
                                offset: Offset(0, -8 * s),
                                child: Container(
                                  padding: EdgeInsets.symmetric(horizontal: 8 * s, vertical: 1 * s),
                                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10 * s)),
                                  child: Text('#${_rankReady ? rank : 0}', style: KL.t(size: 11 * s, w: FontWeight.w600, color: const Color(0xFF333333))),
                                ),
                              ),
                              LedDigits(value: _rankReady ? game.score : 0, height: 13 * s, width: 44 * s),
                            ],
                          ),
                          Positioned(
                            right: 8 * s,
                            bottom: 8 * s,
                            child: Icon(Icons.chevron_right, size: 16 * s, color: const Color(0xFF555555)),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _ledRow(double s, String icon, int value) => Padding(
        padding: EdgeInsets.only(left: 16 * s),
        child: Row(
          children: [
            Image.asset('assets/images/$icon', width: 30 * s, height: 30 * s),
            SizedBox(width: 16 * s),
            LedDigits(value: value, height: 32 * s, width: 160 * s),
          ],
        ),
      );
}
