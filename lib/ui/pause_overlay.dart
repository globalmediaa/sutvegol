import 'package:flutter/material.dart';

import '../game/kick_legend_game.dart';
import 'leaderboard_screen.dart';
import 'led_painter.dart';
import 'mock_data.dart';
import 'theme.dart';

/// Pause perdesi: sol üstte çıkış + yeniden başlat, kartta ses/titreşim
/// toggle'ları, sağda avatar/sıra/puan, altta yeşil Play.
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({super.key, required this.game});
  final KickLegendGame game;

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay> with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(vsync: this, duration: const Duration(milliseconds: 250))..forward();

  @override
  void dispose() {
    _fade.dispose();
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
            Positioned(
              left: 18 * s,
              top: 47 * s,
              child: Row(
                children: [
                  GestureDetector(
                    onTap: () => game.onExit?.call(),
                    child: Image.asset('assets/images/btn_exit.png', width: 94 * s),
                  ),
                  SizedBox(width: 14 * s),
                  GestureDetector(
                    onTap: game.restart,
                    child: Image.asset('assets/images/btn_restart.png', width: 94 * s),
                  ),
                ],
              ),
            ),
            Positioned(
              left: 30 * s,
              top: 333 * s,
              width: 380 * s,
              height: 250 * s,
              child: _card(s, game, rank),
            ),
            Positioned(
              left: 220 * s - 47 * s,
              top: 583 * s - 47 * s,
              child: GestureDetector(
                onTap: game.resume,
                child: Container(
                  width: 95 * s,
                  height: 95 * s,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.35), blurRadius: 12 * s, offset: Offset(0, 6 * s))],
                  ),
                  child: Image.asset('assets/images/btn_play.png'),
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
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  SizedBox(height: 8 * s),
                  _toggle(s, game.soundOn, Icons.volume_up_rounded, Icons.volume_off_rounded, () => setState(() => game.setSound(!game.soundOn))),
                  SizedBox(height: 18 * s),
                  _toggle(s, game.hapticsOn, Icons.vibration_rounded, Icons.vibration_rounded, () => setState(() => game.setHaptics(!game.hapticsOn))),
                  SizedBox(height: 60 * s),
                ],
              ),
            ),
            GestureDetector(
              onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeaderboardScreen(myScore: game.score))),
              child: Container(
                width: 128 * s,
                color: KL.cardGray,
                child: Stack(
                  children: [
                    Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
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
                            child: Text('#$rank', style: KL.t(size: 11 * s, w: FontWeight.w600, color: const Color(0xFF333333))),
                          ),
                        ),
                        LedDigits(value: game.score, height: 13 * s, width: 44 * s),
                        SizedBox(height: 30 * s),
                      ],
                    ),
                    Positioned(right: 8 * s, bottom: 8 * s, child: Icon(Icons.chevron_right, size: 16 * s, color: const Color(0xFF555555))),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _toggle(double s, bool on, IconData onIcon, IconData offIcon, VoidCallback tap) => GestureDetector(
        onTap: tap,
        child: Container(
          width: 96 * s,
          height: 58 * s,
          decoration: BoxDecoration(
            color: on ? const Color(0xFF29B358) : const Color(0xFFD9D9D9),
            borderRadius: BorderRadius.circular(29 * s),
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              Icon(on ? onIcon : offIcon, color: Colors.white, size: 30 * s),
              if (!on)
                Transform.rotate(
                  angle: -0.75,
                  child: Container(width: 34 * s, height: 3 * s, color: Colors.white),
                ),
            ],
          ),
        ),
      );
}
