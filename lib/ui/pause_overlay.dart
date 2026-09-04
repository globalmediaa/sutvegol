import 'package:flutter/material.dart';

import '../game/sut_ve_gol_game.dart';
import 'leaderboard_screen.dart';
import 'led_painter.dart';
import 'mock_data.dart';
import 'theme.dart';
import 'widgets.dart';

/// Pause perdesi: bulanık karartma, "DURAKLATILDI" kartı; ses/titreşim
/// anahtarları, skor + sıra özeti, altta Devam / Yeniden / Çıkış.
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({super.key, required this.game});
  final SutVeGolGame game;

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
            const DimBackdrop(),
            Positioned(
              left: 24 * s,
              right: 24 * s,
              top: 210 * s,
              child: ScaleTransition(
                scale: CurvedAnimation(parent: _fade, curve: Curves.easeOutBack),
                child: _card(s, game, rank),
              ),
            ),
          ],
        ),
      );
    });
  }

  Widget _card(double s, SutVeGolGame game, int rank) {
    return GlassCard(
      radius: 26 * s,
      padding: EdgeInsets.fromLTRB(22 * s, 22 * s, 22 * s, 22 * s),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.pause_circle_filled_rounded, color: FK.amber, size: 26 * s),
              SizedBox(width: 8 * s),
              Text('DURAKLATILDI', style: FK.t(size: 20 * s, w: FontWeight.w700, spacing: 2.5 * s)),
            ],
          ),
          SizedBox(height: 14 * s),
          // Skor + sıra özeti.
          GestureDetector(
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => LeaderboardScreen(myScore: game.score))),
            child: Container(
              padding: EdgeInsets.all(12 * s),
              decoration: BoxDecoration(color: FK.glass, borderRadius: BorderRadius.circular(18 * s), border: Border.all(color: FK.glassBorder)),
              child: Row(
                children: [
                  AvatarCircle(kMeHandle, size: 48 * s, ring: FK.orange, ringWidth: 2.5 * s),
                  SizedBox(width: 12 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('SKOR', style: FK.t(size: 11 * s, w: FontWeight.w600, color: FK.muted, spacing: 2 * s)),
                        SizedBox(height: 2 * s),
                        LedDigits(value: game.score, height: 22 * s, width: 120 * s, color: Colors.white),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Chip2('#$rank', fontSize: 12 * s),
                      SizedBox(height: 4 * s),
                      Row(
                        children: [
                          Text('Sıralama', style: FK.t(size: 12 * s, w: FontWeight.w600, color: FK.amber)),
                          Icon(Icons.chevron_right_rounded, size: 16 * s, color: FK.amber),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12 * s),
          ToggleRow(icon: Icons.volume_up_rounded, label: 'Ses', value: game.soundOn, scale: s, onChanged: (v) => setState(() => game.setSound(v))),
          ToggleRow(icon: Icons.vibration_rounded, label: 'Titreşim', value: game.hapticsOn, scale: s, onChanged: (v) => setState(() => game.setHaptics(v))),
          SizedBox(height: 18 * s),
          PillButton(label: 'DEVAM ET', icon: Icons.play_arrow_rounded, onTap: game.resume, height: 56 * s, fontSize: 18 * s, width: double.infinity),
          SizedBox(height: 10 * s),
          Row(
            children: [
              Expanded(child: PillButton(label: 'YENİDEN', icon: Icons.replay_rounded, primary: false, onTap: game.restart, height: 48 * s, fontSize: 15 * s, width: double.infinity)),
              SizedBox(width: 10 * s),
              Expanded(child: PillButton(label: 'ÇIKIŞ', icon: Icons.logout_rounded, primary: false, onTap: () => game.onExit?.call(), height: 48 * s, fontSize: 15 * s, width: double.infinity)),
            ],
          ),
        ],
      ),
    );
  }
}
