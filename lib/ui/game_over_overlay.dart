import 'dart:math';

import 'package:flutter/material.dart';

import '../game/sut_ve_gol_game.dart';
import '../game/sfx.dart';
import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/progress_service.dart';
import 'ad_banner.dart';
import 'leaderboard_screen.dart';
import 'led_painter.dart';
import 'theme.dart';
import 'widgets.dart';

/// Oyun sonu perdesi: bulanık karartma, üstte çıkış, cam kart (sayaçla artan
/// skor, rekor, sahne), sıra paneli ve "TEKRAR OYNA" hap butonu.
/// Reklam: "TEKRAR OYNA"da sıklık sınırlı geçiş reklamı, isteğe bağlı ödüllü
/// "Kral Moduyla başla" ve altta banner (butonlardan uzak; sığmazsa yok).
class GameOverOverlay extends StatefulWidget {
  const GameOverOverlay({
    super.key,
    required this.game,
    this.onDuel,
    this.guest = false,
    this.onSignIn,
  });
  final SutVeGolGame game;
  final VoidCallback? onDuel;

  /// Misafir: ilk oyundan sonra bir kez atlanabilir "Apple/Google ile kaydet" önerisi.
  final bool guest;
  final VoidCallback? onSignIn;

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

  /// Reklam / yeniden başlatma sürerken butonlar ikinci kez tetiklenmez.
  bool _busy = false;

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
    if (widget.guest && !ProgressService.instance.saveOfferSeen) {
      Future.delayed(const Duration(milliseconds: 1900), () {
        if (mounted) showSaveProgressOffer(context, onSignIn: widget.onSignIn);
      });
    }
  }

  @override
  void dispose() {
    _fade.dispose();
    _count.dispose();
    super.dispose();
  }

  /// [fever]: ödüllü reklamla Kral Modu'nda başla; aksi hâlde sıra geldiyse
  /// geçiş reklamı, sonra yeni koşu.
  Future<void> _replay({bool fever = false}) async {
    if (_busy) return;
    setState(() => _busy = true);
    final game = widget.game;
    final ads = AdService.instance;
    if (fever) {
      final result = await ads.showRewarded(
        onOpen: game.suspendForAd,
        onClose: game.resumeAfterAd,
      );
      if (result == RewardResult.skipped) {
        if (mounted) setState(() => _busy = false);
        return;
      }
    } else {
      await ads.maybeShowInterstitial(
        AdMoment.soloReplay,
        onOpen: game.suspendForAd,
        onClose: game.resumeAfterAd,
      );
    }
    game.restart(feverStart: fever);
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
        final bottom = MediaQuery.paddingOf(context).bottom;
        final buttonsEnd = widget.onDuel != null ? 630 * s + 48 : 620 * s;
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
                left: 24 * s,
                right: 24 * s,
                top: 495 * s,
                child: Center(child: _feverOffer(s)),
              ),
              Positioned(
                left: 0,
                right: 0,
                top: 560 * s,
                child: Center(
                  child: PillButton(
                    label: 'TEKRAR OYNA',
                    icon: Icons.replay_rounded,
                    onTap: _replay,
                    enabled: !_busy,
                    height: 60 * s,
                    fontSize: 19 * s,
                  ),
                ),
              ),
              if (widget.onDuel != null)
                Positioned(
                  left: 24,
                  right: 24,
                  top: 630 * s,
                  child: Center(
                    child: PillButton(
                      label: 'ONLINE DÜELLO',
                      icon: Icons.sports_soccer_rounded,
                      primary: false,
                      onTap: widget.onDuel!,
                      height: 48,
                      fontSize: 16,
                    ),
                  ),
                ),
              Positioned(
                left: 0,
                right: 0,
                bottom: bottom + 8,
                child: Center(
                  child: AdBanner.anchored(
                    maxHeight: c.maxHeight - bottom - 8 - buttonsEnd - 20,
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  /// Ödüllü teklif: reklam hazırsa ve yeni oyuncu değilse görünür.
  Widget _feverOffer(double s) => ListenableBuilder(
    listenable: AdService.instance,
    builder: (context, _) {
      if (!AdService.instance.canOfferFeverStart) {
        return const SizedBox.shrink();
      }
      return GestureDetector(
        key: const Key('fever-start-offer'),
        onTap: _busy ? null : () => _replay(fever: true),
        child: Container(
          height: 54 * s,
          padding: EdgeInsets.symmetric(horizontal: 18 * s),
          decoration: BoxDecoration(
            color: FK.gold.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(27 * s),
            border: Border.all(
              color: FK.gold.withValues(alpha: .7),
              width: 1.4,
            ),
          ),
          // Dar ekranda satır kırpılmaz, birlikte küçülür.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.smart_display_rounded, color: FK.gold, size: 24 * s),
                SizedBox(width: 10 * s),
                Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'KRAL MODUYLA BAŞLA',
                      style: FK.t(
                        size: 15 * s,
                        w: FontWeight.w700,
                        color: FK.gold,
                        spacing: 1 * s,
                      ),
                    ),
                    SizedBox(height: 2 * s),
                    Text(
                      'Reklam izle · ilk 10 sn altın top, x2 puan',
                      style: FK.t(size: 11.5 * s, color: FK.muted),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      );
    },
  );

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

/// Misafire bir kez gösterilen, atlanabilir kayıt önerisi. Yalnız bu derlemede
/// çalışan sağlayıcılar listelenir (Google kimliği yoksa Google düğmesi yok);
/// hiçbiri yoksa giriş ekranına götürür.
Future<void> showSaveProgressOffer(
  BuildContext context, {
  VoidCallback? onSignIn,
}) async {
  await ProgressService.instance.markSaveOfferSeen();
  if (!context.mounted) return;
  final messenger = ScaffoldMessenger.maybeOf(context);
  final auth = AuthService.instance;
  Future<void> Function()? chosen;
  await showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheet) {
      void pick(Future<void> Function() action) {
        chosen = action;
        Navigator.of(sheet).pop();
      }

      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: GlassCard(
            radius: 24,
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Icon(
                  Icons.cloud_upload_rounded,
                  color: FK.amber,
                  size: 34,
                ),
                const SizedBox(height: 8),
                Text(
                  'İlerlemeni kaydet',
                  textAlign: TextAlign.center,
                  style: FK.t(size: 22, w: FontWeight.w700),
                ),
                const SizedBox(height: 6),
                Text(
                  'Misafir ilerlemen yalnız bu cihazda. Kaydedersen uygulamayı '
                  'silip yeniden yüklesen de giriş yapınca kaldığın yerden devam edersin.',
                  textAlign: TextAlign.center,
                  style: FK.t(size: 14, color: FK.muted, height: 1.4),
                ),
                const SizedBox(height: 16),
                if (appleSignInAvailable) ...[
                  SocialButton(
                    label: 'Apple ile kaydet',
                    icon: const Icon(
                      Icons.apple,
                      color: Colors.black,
                      size: 26,
                    ),
                    onTap: () => pick(auth.apple),
                  ),
                  const SizedBox(height: 8),
                ],
                if (googleAvailable) ...[
                  SocialButton(
                    label: 'Google ile kaydet',
                    icon: const GoogleMark(size: 22),
                    onTap: () => pick(auth.google),
                  ),
                  const SizedBox(height: 8),
                ],
                if (!appleSignInAvailable &&
                    !googleAvailable &&
                    onSignIn != null)
                  PillButton(
                    label: 'HESAPLA KAYDET',
                    icon: Icons.person_add_alt_1_rounded,
                    onTap: () {
                      Navigator.of(sheet).pop();
                      onSignIn();
                    },
                    height: 52,
                    fontSize: 16,
                    width: double.infinity,
                  ),
                TextButton(
                  onPressed: () => Navigator.of(sheet).pop(),
                  child: const Text('Şimdi değil'),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  final action = chosen;
  if (action == null) return;
  try {
    await action();
  } catch (_) {
    final message = auth.error;
    if (message != null) {
      messenger?.showSnackBar(SnackBar(content: Text(message)));
    }
  }
}
