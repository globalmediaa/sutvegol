import 'package:flutter/material.dart';

import '../game/sut_ve_gol_game.dart';
import '../services/ad_service.dart';
import '../services/moderation_service.dart';
import '../services/progress_service.dart';
import 'leaderboard_screen.dart';
import 'account_screen.dart';
import 'led_painter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'theme.dart';
import 'widgets.dart';

/// Pause perdesi: bulanık karartma, "DURAKLATILDI" kartı; ses/titreşim
/// anahtarları, skor + sıra özeti, altta Devam / Yeniden / Çıkış.
class PauseOverlay extends StatefulWidget {
  const PauseOverlay({
    super.key,
    required this.game,
    this.guest = false,
    this.onDuel,
  });
  final SutVeGolGame game;
  final bool guest;
  final VoidCallback? onDuel;

  @override
  State<PauseOverlay> createState() => _PauseOverlayState();
}

class _PauseOverlayState extends State<PauseOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  )..forward();

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final game = widget.game;
    final rank = game.best;
    return LayoutBuilder(
      builder: (context, c) {
        final s = (c.maxWidth / 440).clamp(0.0, 1.0);
        return FadeTransition(
          opacity: _fade,
          child: Stack(
            children: [
              const DimBackdrop(),
              Positioned(
                left: 24 * s,
                right: 24 * s,
                top: MediaQuery.paddingOf(context).top + 24,
                bottom: MediaQuery.paddingOf(context).bottom + 24,
                child: Center(
                  child: SingleChildScrollView(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 440),
                      child: ScaleTransition(
                        scale: CurvedAnimation(
                          parent: _fade,
                          curve: Curves.easeOutBack,
                        ),
                        child: _card(s, game, rank),
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

  Future<void> _open(String address) async {
    try {
      if (await launchUrl(
        Uri.parse(address),
        mode: LaunchMode.externalApplication,
      )) {
        return;
      }
    } catch (_) {}
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text('Bağlantı açılamadı. $address')));
  }

  bool _resetting = false;

  /// İki onaylı "Sil ve baştan başla": girişliyse yerel + bulut + diğer cihazlar.
  Future<void> _resetProgress() async {
    final game = widget.game;
    final progress = ProgressService.instance;
    final cloud = progress.signedIn;
    final first = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Sil ve baştan başla?'),
        content: Text(
          cloud
              ? 'Rekorun ve oyun istatistiklerin bu cihazdan, bulut kaydından ve '
                    'hesabınla giriş yaptığın diğer cihazlardan silinir. Ses/titreşim '
                    'ayarların, düello puanın ve sıralamadaki geçmiş skorların korunur.'
              : 'Rekorun ve oyun istatistiklerin bu cihazdan silinir. '
                    'Ses/titreşim ayarların korunur.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Devam'),
          ),
        ],
      ),
    );
    if (first != true || !mounted) return;
    final second = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Emin misin?'),
        content: const Text(
          'Bu işlem geri alınamaz. Silinen ilerleme geri getirilemez.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FK.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Sil ve baştan başla'),
          ),
        ],
      ),
    );
    if (second != true || !mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() => _resetting = true);
    try {
      await progress.resetAll();
    } catch (_) {
      if (mounted) setState(() => _resetting = false);
      messenger?.showSnackBar(
        const SnackBar(
          content: Text(
            'Sunucuya ulaşılamadı; ilerleme silinmedi. Bağlantını kontrol edip yeniden dene.',
          ),
        ),
      );
      return;
    }
    messenger?.showSnackBar(
      const SnackBar(content: Text('İlerleme silindi. Baştan başlıyorsun.')),
    );
    game.restartAfterReset();
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
              Icon(
                Icons.pause_circle_filled_rounded,
                color: FK.amber,
                size: 26 * s,
              ),
              SizedBox(width: 8 * s),
              Text(
                'DURAKLATILDI',
                style: FK.t(size: 20 * s, w: FontWeight.w700, spacing: 2.5 * s),
              ),
            ],
          ),
          SizedBox(height: 14 * s),
          // Skor + sıra özeti.
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => LeaderboardScreen(myScore: game.score),
              ),
            ),
            child: Container(
              padding: EdgeInsets.all(12 * s),
              decoration: BoxDecoration(
                color: FK.glass,
                borderRadius: BorderRadius.circular(18 * s),
                border: Border.all(color: FK.glassBorder),
              ),
              child: Row(
                children: [
                  AvatarCircle(
                    'Oyuncu',
                    size: 48 * s,
                    ring: FK.orange,
                    ringWidth: 2.5 * s,
                  ),
                  SizedBox(width: 12 * s),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'SKOR',
                          style: FK.t(
                            size: 11 * s,
                            w: FontWeight.w600,
                            color: FK.muted,
                            spacing: 2 * s,
                          ),
                        ),
                        SizedBox(height: 2 * s),
                        LedDigits(
                          value: game.score,
                          height: 22 * s,
                          width: 120 * s,
                          color: Colors.white,
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Chip2('$rank', fontSize: 12 * s),
                      SizedBox(height: 4 * s),
                      Row(
                        children: [
                          Text(
                            'Rekor',
                            style: FK.t(
                              size: 12 * s,
                              w: FontWeight.w600,
                              color: FK.amber,
                            ),
                          ),
                          Icon(
                            Icons.chevron_right_rounded,
                            size: 16 * s,
                            color: FK.amber,
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          SizedBox(height: 12 * s),
          ToggleRow(
            icon: Icons.volume_up_rounded,
            label: 'Ses',
            value: game.soundOn,
            scale: s,
            onChanged: (v) => setState(() => game.setSound(v)),
          ),
          ToggleRow(
            icon: Icons.vibration_rounded,
            label: 'Titreşim',
            value: game.hapticsOn,
            scale: s,
            onChanged: (v) => setState(() => game.setHaptics(v)),
          ),
          _HowToRow(scale: s, onTap: game.showTutorial),
          _ResetRow(
            scale: s,
            busy: _resetting,
            onTap: _resetting ? null : _resetProgress,
          ),
          Padding(
            padding: EdgeInsets.only(top: 4 * s, bottom: 4 * s),
            child: Text(
              widget.guest
                  ? 'Misafir ilerlemen yalnız bu cihazda saklanır. Giriş yaparsan '
                        'hesabına anlık kaydedilir.'
                  : 'İlerlemen hesabına anlık kaydedilir; yeniden yüklediğinde giriş '
                        'yapınca kaldığın yerden devam edersin. Hesabını silersen '
                        '(Hesabım) bulut kaydın da kalıcı olarak silinir.',
              textAlign: TextAlign.center,
              style: FK.t(size: 12 * s, color: FK.muted, height: 1.35),
            ),
          ),
          Wrap(
            alignment: WrapAlignment.center,
            children: [
              if (!widget.guest)
                TextButton(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => const AccountScreen()),
                  ),
                  child: const Text('Hesabım'),
                ),
              TextButton(
                onPressed: () => _open(kPrivacyUrl),
                child: const Text('Gizlilik'),
              ),
              TextButton(
                onPressed: () => _open(kTermsUrl),
                child: const Text('Koşullar'),
              ),
              // AB/BK/İsviçre: reklam onayını değiştirme yolu (UMP zorunluluğu).
              if (AdService.instance.privacyOptionsRequired)
                TextButton(
                  onPressed: AdService.instance.showPrivacyOptions,
                  child: const Text('Reklam tercihleri'),
                ),
              TextButton(
                onPressed: () => _open('https://sutvegol.gmgaming.app/#destek'),
                child: const Text('Destek'),
              ),
            ],
          ),
          SizedBox(height: 18 * s),
          if (widget.onDuel != null) ...[
            PillButton(
              label: 'ONLINE DÜELLO',
              icon: Icons.sports_soccer_rounded,
              onTap: widget.onDuel!,
              height: 52,
              width: double.infinity,
              fontSize: 17,
            ),
            const SizedBox(height: 12),
          ],
          PillButton(
            label: 'DEVAM ET',
            icon: Icons.play_arrow_rounded,
            onTap: game.resume,
            height: 56 * s,
            fontSize: 18 * s,
            width: double.infinity,
          ),
          SizedBox(height: 10 * s),
          Row(
            children: [
              Expanded(
                child: PillButton(
                  label: 'YENİDEN',
                  icon: Icons.replay_rounded,
                  primary: false,
                  onTap: game.restart,
                  height: 48 * s,
                  fontSize: 15 * s,
                  width: double.infinity,
                ),
              ),
              SizedBox(width: 10 * s),
              Expanded(
                child: PillButton(
                  label: 'ÇIKIŞ',
                  icon: Icons.logout_rounded,
                  primary: false,
                  onTap: () => game.onExit?.call(),
                  height: 48 * s,
                  fontSize: 15 * s,
                  width: double.infinity,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Nasıl oynanır": rehberi baştan açar (ses/titreşim satırlarıyla aynı dil).
class _HowToRow extends StatelessWidget {
  const _HowToRow({required this.onTap, this.scale = 1});
  final VoidCallback onTap;
  final double scale;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * s),
        child: Row(
          children: [
            Container(
              width: 40 * s,
              height: 40 * s,
              decoration: BoxDecoration(
                color: FK.glass,
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: Icon(
                Icons.pan_tool_alt_rounded,
                color: FK.amber,
                size: 22 * s,
              ),
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Text(
                'Nasıl oynanır',
                style: FK.t(size: 16 * s, w: FontWeight.w600),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: FK.muted, size: 26 * s),
          ],
        ),
      ),
    );
  }
}

/// "Sil ve baştan başla": kırmızı, iki onaylı sıfırlama satırı.
class _ResetRow extends StatelessWidget {
  const _ResetRow({required this.onTap, this.scale = 1, this.busy = false});
  final VoidCallback? onTap;
  final double scale;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final s = scale;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: 8 * s),
        child: Row(
          children: [
            Container(
              width: 40 * s,
              height: 40 * s,
              decoration: BoxDecoration(
                color: FK.glass,
                borderRadius: BorderRadius.circular(12 * s),
              ),
              child: busy
                  ? Padding(
                      padding: EdgeInsets.all(10 * s),
                      child: const CircularProgressIndicator(
                        strokeWidth: 2.4,
                        color: FK.red,
                      ),
                    )
                  : Icon(
                      Icons.restart_alt_rounded,
                      color: FK.red,
                      size: 22 * s,
                    ),
            ),
            SizedBox(width: 12 * s),
            Expanded(
              child: Text(
                'Sil ve baştan başla',
                style: FK.t(size: 16 * s, w: FontWeight.w600, color: FK.red),
              ),
            ),
            Icon(Icons.chevron_right_rounded, color: FK.muted, size: 26 * s),
          ],
        ),
      ),
    );
  }
}
