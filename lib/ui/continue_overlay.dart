import 'dart:math';

import 'package:flutter/material.dart';

import '../game/sut_ve_gol_game.dart';
import '../services/ad_service.dart';
import 'led_painter.dart';
import 'theme.dart';
import 'widgets.dart';

/// Son kalp gidince: "BİR ŞANS DAHA" — ödüllü reklam izlenirse koşu 1 kalple
/// kaldığı yerden sürer (koşu başına bir kez). Süre dolarsa ya da "Hayır"
/// denirse oyun biter ve skor gönderilir.
class ContinueOverlay extends StatefulWidget {
  const ContinueOverlay({super.key, required this.game});
  final SutVeGolGame game;

  /// Karar süresi; halka bu sürede boşalır.
  static const Duration window = Duration(seconds: 6);

  @override
  State<ContinueOverlay> createState() => _ContinueOverlayState();
}

class _ContinueOverlayState extends State<ContinueOverlay>
    with TickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 260),
  )..forward();
  late final AnimationController _clock =
      AnimationController(vsync: this, duration: ContinueOverlay.window)
        ..addStatusListener((s) {
          if (s == AnimationStatus.completed) _decline();
        })
        ..forward();
  bool _busy = false;

  @override
  void dispose() {
    _fade.dispose();
    _clock.dispose();
    super.dispose();
  }

  void _decline() {
    if (_busy) return;
    _busy = true;
    widget.game.declineContinue();
  }

  Future<void> _watch() async {
    if (_busy) return;
    setState(() => _busy = true);
    _clock.stop();
    final game = widget.game;
    final result = await AdService.instance.showRewarded(
      onOpen: game.suspendForAd,
      onClose: game.resumeAfterAd,
    );
    // Reklam açılamadıysa oyuncunun suçu değil: hak yine verilir.
    if (result == RewardResult.skipped) {
      game.declineContinue();
    } else {
      game.continueRun();
    }
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    return LayoutBuilder(
      builder: (context, c) {
        final s = min(c.maxWidth / 440, c.maxHeight / 760).clamp(0.0, 1.0);
        return FadeTransition(
          opacity: _fade,
          child: Stack(
            children: [
              const DimBackdrop(),
              Center(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: 24 * s),
                  child: ScaleTransition(
                    scale: CurvedAnimation(
                      parent: _fade,
                      curve: Curves.easeOutBack,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(maxWidth: 392 * s),
                      child: GlassCard(
                        radius: 26 * s,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              height: 46 * s,
                              decoration: BoxDecoration(
                                gradient: FK.fire,
                                borderRadius: BorderRadius.vertical(
                                  top: Radius.circular(26 * s),
                                ),
                              ),
                              alignment: Alignment.center,
                              child: Text(
                                'BİR ŞANS DAHA',
                                style: FK.t(
                                  size: 20 * s,
                                  w: FontWeight.w700,
                                  spacing: 3 * s,
                                ),
                              ),
                            ),
                            Padding(
                              padding: EdgeInsets.fromLTRB(
                                20 * s,
                                20 * s,
                                20 * s,
                                8 * s,
                              ),
                              child: Column(
                                children: [
                                  _heart(s),
                                  SizedBox(height: 14 * s),
                                  LedDigits(
                                    value: game.score,
                                    height: 30 * s,
                                    width: 160 * s,
                                    color: Colors.white,
                                  ),
                                  SizedBox(height: 10 * s),
                                  Text(
                                    'Kısa bir reklam izle, 1 kalple '
                                    'kaldığın yerden devam et.',
                                    textAlign: TextAlign.center,
                                    style: FK.t(
                                      size: 15 * s,
                                      color: FK.muted,
                                      height: 1.35,
                                    ),
                                  ),
                                  SizedBox(height: 18 * s),
                                  _busy
                                      ? BusyPill(height: 58 * s)
                                      : PillButton(
                                          key: const Key('continue-watch'),
                                          label: 'REKLAM İZLE · DEVAM',
                                          icon: Icons.smart_display_rounded,
                                          onTap: _watch,
                                          height: 58 * s,
                                          fontSize: 17 * s,
                                          width: double.infinity,
                                        ),
                                  SizedBox(height: 4 * s),
                                  TextButton(
                                    key: const Key('continue-decline'),
                                    onPressed: _busy ? null : _decline,
                                    child: Text(
                                      'Hayır, oyunu bitir',
                                      style: FK.t(
                                        size: 15 * s,
                                        w: FontWeight.w600,
                                        color: FK.muted,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Boşalan süre halkası içinde "+1" kalp.
  Widget _heart(double s) => SizedBox(
    width: 112 * s,
    height: 112 * s,
    child: Stack(
      alignment: Alignment.center,
      children: [
        Positioned.fill(
          child: AnimatedBuilder(
            animation: _clock,
            builder: (_, _) => CircularProgressIndicator(
              value: 1 - _clock.value,
              strokeWidth: 6 * s,
              color: FK.amber,
              backgroundColor: FK.glass,
            ),
          ),
        ),
        Icon(Icons.favorite_rounded, color: FK.red, size: 58 * s),
        Positioned(
          right: 12 * s,
          bottom: 14 * s,
          child: Chip2('+1', color: FK.green, fontSize: 13 * s),
        ),
      ],
    ),
  );
}
