import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import '../services/moderation_service.dart';
import 'theme.dart';
import 'widgets.dart';

/// Şikâyet/engel hedefi: başka bir oyuncunun kalıcı kimliği ve ekranda görünen adı.
class PlayerRef {
  const PlayerRef({required this.id, required this.name, this.blocked = false});
  final String id, name;

  /// Sunucunun bildirdiği engel durumu (yerel değişiklik önce gelir).
  final bool blocked;
}

enum _PlayerAction { report, block, unblock }

/// "⋯" düğmesi: Şikâyet et (sebep seçimi) · Engelle (onaylı) · Engeli kaldır.
class PlayerActionsButton extends StatelessWidget {
  const PlayerActionsButton({
    super.key,
    required this.player,
    required this.reportContext,
    this.duelId,
    this.onChanged,
    this.size = 22,
    this.filled = false,
  });
  final PlayerRef player;
  final ReportContext reportContext;
  final String? duelId;

  /// Engel değişince (sıralamayı yenilemek için).
  final VoidCallback? onChanged;
  final double size;

  /// Oyun sahası üstünde okunurluk için koyu zemin.
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final button = IconButton(
      tooltip: 'Oyuncu seçenekleri',
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      padding: EdgeInsets.zero,
      onPressed: () => showPlayerActions(
        context,
        player: player,
        reportContext: reportContext,
        duelId: duelId,
        onChanged: onChanged,
      ),
      icon: Icon(Icons.more_horiz_rounded, size: size, color: FK.text),
    );
    if (!filled) return button;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: FK.navy.withValues(alpha: .9),
        borderRadius: BorderRadius.circular(12),
      ),
      child: button,
    );
  }
}

Future<void> showPlayerActions(
  BuildContext context, {
  required PlayerRef player,
  required ReportContext reportContext,
  String? duelId,
  VoidCallback? onChanged,
}) async {
  if (AuthService.instance.user == null) {
    await _guestSheet(context, player);
    return;
  }
  final blocked = ModerationService.instance.isBlocked(
    player.id,
    server: player.blocked,
  );
  final action = await showModalBottomSheet<_PlayerAction>(
    context: context,
    backgroundColor: FK.navy2,
    showDragHandle: true,
    builder: (c) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text(
                _handle(player.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: FK.t(size: 18, w: FontWeight.w700),
              ),
            ),
            ListTile(
              key: const Key('player-report'),
              leading: const Icon(Icons.flag_outlined, color: FK.amber),
              title: const Text('Şikâyet et'),
              subtitle: const Text('Uygunsuz ad, hile ya da taciz'),
              onTap: () => Navigator.pop(c, _PlayerAction.report),
            ),
            ListTile(
              key: Key(blocked ? 'player-unblock' : 'player-block'),
              leading: Icon(
                blocked ? Icons.lock_open_rounded : Icons.block_rounded,
                color: blocked ? FK.green : FK.red,
              ),
              title: Text(blocked ? 'Engeli kaldır' : 'Engelle'),
              subtitle: Text(
                blocked
                    ? 'Yeniden eşleşebilir, adını görebilirsin'
                    : 'Bu oyuncuyla eşleşmezsin, adı sana gizlenir',
              ),
              onTap: () => Navigator.pop(
                c,
                blocked ? _PlayerAction.unblock : _PlayerAction.block,
              ),
            ),
          ],
        ),
      ),
    ),
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _PlayerAction.report:
      final sent = await showModalBottomSheet<bool>(
        context: context,
        backgroundColor: FK.navy2,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (_) => _ReportSheet(
          player: player,
          reportContext: reportContext,
          duelId: duelId,
        ),
      );
      if (sent == true && context.mounted) {
        final messenger = ScaffoldMessenger.of(context);
        messenger.showSnackBar(
          SnackBar(
            content: const Text(
              'Şikâyetin alındı. Ekibimiz 24 saat içinde inceleyecek.',
            ),
            action: blocked
                ? null
                : SnackBarAction(
                    label: 'ENGELLE',
                    onPressed: () {
                      if (context.mounted) {
                        _blockFlow(context, player, onChanged);
                      }
                    },
                  ),
          ),
        );
      }
    case _PlayerAction.block:
      await _blockFlow(context, player, onChanged);
    case _PlayerAction.unblock:
      await _run(
        context,
        () => ModerationService.instance.unblock(player.id),
        done: 'Engel kaldırıldı.',
      );
      onChanged?.call();
  }
}

String _handle(String name) =>
    name == kBlockedLabel || name.startsWith('Oyuncu#') ? name : '@$name';

Future<void> _blockFlow(
  BuildContext context,
  PlayerRef player,
  VoidCallback? onChanged,
) async {
  if (!await confirmBlock(context, player) || !context.mounted) return;
  final ok = await _run(
    context,
    () => ModerationService.instance.block(player.id),
    done: 'Oyuncu engellendi.',
  );
  if (ok) onChanged?.call();
}

/// Engel onayı: neyin değiştiğini ve nasıl geri alınacağını açıkça söyler.
Future<bool> confirmBlock(BuildContext context, PlayerRef player) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      backgroundColor: FK.navy2,
      title: Text('${_handle(player.name)} engellensin mi?'),
      content: const Text(
        'Bu oyuncuyla bir daha eşleşmezsin ve kayıtlı koşusu karşına çıkmaz. '
        'Sıralamada adı sana “Engellenen oyuncu” olarak görünür. Engeli '
        'Hesabım > Engellenen oyuncular bölümünden kaldırabilirsin.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(c, false),
          child: const Text('Vazgeç'),
        ),
        FilledButton(
          key: const Key('confirm-block'),
          style: FilledButton.styleFrom(backgroundColor: FK.red),
          onPressed: () => Navigator.pop(c, true),
          child: const Text('Engelle'),
        ),
      ],
    ),
  );
  return ok == true;
}

Future<bool> _run(
  BuildContext context,
  Future<void> Function() action, {
  required String done,
}) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await action();
    messenger.showSnackBar(SnackBar(content: Text(done)));
    return true;
  } on ApiException catch (e) {
    messenger.showSnackBar(SnackBar(content: Text(e.message)));
  } catch (_) {
    messenger.showSnackBar(
      const SnackBar(content: Text('İşlem tamamlanamadı. Yeniden dene.')),
    );
  }
  return false;
}

/// Misafir: şikâyet ve engel hesap ister; e-posta ile bildirim yolu açık kalır.
Future<void> _guestSheet(
  BuildContext context,
  PlayerRef player,
) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: FK.navy2,
  showDragHandle: true,
  builder: (c) => SafeArea(
    child: Padding(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'Giriş yapman gerekiyor',
            style: FK.t(size: 20, w: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Text(
            'Oyuncuları uygulamadan şikâyet etmek ve engellemek için hesabınla '
            'giriş yap. Uygunsuz bir ad gördüysen bize e-postayla da bildirebilirsin.',
            style: FK.t(size: 15, color: FK.muted, height: 1.4),
          ),
          const SizedBox(height: 18),
          PillButton(
            label: 'E-POSTA İLE BİLDİR',
            icon: Icons.mail_outline_rounded,
            height: 50,
            fontSize: 15,
            onTap: () {
              Navigator.pop(c);
              launchUrl(reportMailUri(player));
            },
          ),
        ],
      ),
    ),
  ),
);

/// Misafir için hazır e-posta taslağı (oyuncu adı ve kalıcı kimliği).
Uri reportMailUri(PlayerRef player) => Uri(
  scheme: 'mailto',
  path: kSupportEmail,
  query:
      'subject=${Uri.encodeComponent('Şut ve Gol oyuncu şikâyeti')}'
      '&body=${Uri.encodeComponent('Görünen ad: ${player.name}\nOyuncu kimliği: ${player.id}\nSebep: \n')}',
);

class _ReportSheet extends StatefulWidget {
  const _ReportSheet({
    required this.player,
    required this.reportContext,
    this.duelId,
  });
  final PlayerRef player;
  final ReportContext reportContext;
  final String? duelId;

  @override
  State<_ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends State<_ReportSheet> {
  final _note = TextEditingController();
  ReportReason? _reason;
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    final reason = _reason;
    if (reason == null || _busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ModerationService.instance.report(
        targetId: widget.player.id,
        reason: reason,
        context: widget.reportContext,
        duelId: widget.duelId,
        note: _note.text,
      );
      if (mounted) Navigator.pop(context, true);
    } on ApiException catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = e.message;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = 'Şikâyet gönderilemedi. Yeniden dene.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => SafeArea(
    child: Padding(
      padding: EdgeInsets.fromLTRB(
        20,
        0,
        20,
        16 + MediaQuery.viewInsetsOf(context).bottom,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Oyuncuyu şikâyet et',
              style: FK.t(size: 22, w: FontWeight.w700),
            ),
            const SizedBox(height: 4),
            Text(
              _handle(widget.player.name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: FK.t(size: 15, color: FK.amber, w: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            for (final r in ReportReason.values)
              Semantics(
                selected: _reason == r,
                button: true,
                child: ListTile(
                  key: Key('reason-${r.name}'),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4),
                  leading: Icon(
                    _reason == r
                        ? Icons.radio_button_checked_rounded
                        : Icons.radio_button_unchecked_rounded,
                    color: _reason == r ? FK.orange : FK.muted,
                  ),
                  title: Text(r.label),
                  subtitle: Text(r.hint),
                  onTap: _busy ? null : () => setState(() => _reason = r),
                ),
              ),
            const SizedBox(height: 8),
            TextField(
              key: const Key('report-note'),
              controller: _note,
              maxLength: 200,
              minLines: 1,
              maxLines: 3,
              enabled: !_busy,
              style: FK.t(size: 15),
              decoration: gameInput(
                label: 'Not (isteğe bağlı)',
                icon: Icons.notes_rounded,
                helper: 'Kısa açıklama. Kişisel bilgi yazma.',
              ),
            ),
            if (_error != null)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Text(
                  _error!,
                  style: FK.t(size: 13, color: FK.red, height: 1.3),
                ),
              ),
            const SizedBox(height: 14),
            if (_busy)
              const BusyPill(height: 52)
            else
              PillButton(
                key: const Key('report-send'),
                label: 'ŞİKÂYETİ GÖNDER',
                icon: Icons.flag_rounded,
                height: 52,
                fontSize: 16,
                enabled: _reason != null,
                onTap: _send,
              ),
            const SizedBox(height: 8),
            Text(
              'Şikâyetler 24 saat içinde incelenir. Kuralları ihlal eden adlar '
              'değiştirilir, hesaplar askıya alınabilir.',
              textAlign: TextAlign.center,
              style: FK.t(size: 12, color: FK.muted, height: 1.35),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Kullanıcı adı alanının yardım metni (kayıt ve ad seçimi aynı): topluluk kuralına
/// uymayan ad (sunucu mesajı), alınmış, uygun ya da biçim ipucu. `ok`: simge rengi.
({String text, TextStyle? style, bool? ok}) usernameFeedback(UsernameCheck? c) {
  if (c == null) {
    return (text: '3–20 karakter · harf, rakam ve _', style: null, ok: null);
  }
  if (!c.allowed) {
    return (
      text: c.message ?? kUsernameNotAllowed,
      style: FK.t(size: 12, color: FK.red, height: 1.25),
      ok: false,
    );
  }
  if (!c.available) {
    return (
      text: 'Bu kullanıcı adı alınmış. Başka bir tane dene.',
      style: FK.t(size: 12, color: FK.red),
      ok: false,
    );
  }
  return (
    text: 'Bu kullanıcı adı kullanılabilir',
    style: FK.t(size: 12, color: FK.green),
    ok: true,
  );
}

/// Ad gönderimi başarısız olunca alanın yeni durumu (uygunsuz ad mesajı korunur).
UsernameCheck usernameRejected(Object error) => UsernameCheck(
  valid: true,
  allowed: !(error is ApiException && error.code == 'username_not_allowed'),
  available: false,
  message: error is ApiException && error.code == 'username_not_allowed'
      ? error.message
      : null,
);

Future<void> openTerms() =>
    launchUrl(Uri.parse(kTermsUrl), mode: LaunchMode.externalApplication);

/// Kayıt ve ad seçiminde Kullanım Koşulları onayı; işaretlenmeden devam edilemez.
class TermsConsent extends StatefulWidget {
  const TermsConsent({super.key, required this.value, required this.onChanged});
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  State<TermsConsent> createState() => _TermsConsentState();
}

class _TermsConsentState extends State<TermsConsent> {
  late final TapGestureRecognizer _link = TapGestureRecognizer()
    ..onTap = openTerms;

  @override
  void dispose() {
    _link.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => MergeSemantics(
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: Checkbox(
            key: const Key('terms-consent'),
            value: widget.value,
            onChanged: (v) => widget.onChanged(v ?? false),
            activeColor: FK.orange,
            checkColor: Colors.white,
            side: const BorderSide(color: FK.muted, width: 1.6),
          ),
        ),
        const SizedBox(width: 4),
        Expanded(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => widget.onChanged(!widget.value),
            child: Padding(
              padding: const EdgeInsets.only(top: 9),
              child: Text.rich(
                TextSpan(
                  style: FK.t(size: 13, color: FK.muted, height: 1.35),
                  children: [
                    TextSpan(
                      text: 'Kullanım Koşulları',
                      style: FK
                          .t(
                            size: 13,
                            color: FK.amber,
                            w: FontWeight.w700,
                            height: 1.35,
                          )
                          .copyWith(decoration: TextDecoration.underline),
                      recognizer: _link,
                    ),
                    const TextSpan(
                      text:
                          '’nı okudum ve kabul ediyorum. Uygunsuz içeriğe ve diğer '
                          'oyuncuları taciz eden kullanıcılara sıfır tolerans '
                          'uygulanır; kuralları ihlal eden hesaplar askıya alınır.',
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    ),
  );
}

/// Hesabım > Engellenen oyuncular: liste ve "Engeli kaldır".
class BlockedPlayersScreen extends StatefulWidget {
  const BlockedPlayersScreen({super.key});
  @override
  State<BlockedPlayersScreen> createState() => _BlockedPlayersScreenState();
}

class _BlockedPlayersScreenState extends State<BlockedPlayersScreen> {
  late Future<List<BlockedPlayer>> _future = ModerationService.instance
      .loadBlocks();
  final _busy = <String>{};

  void _reload() => setState(() {
    _future = ModerationService.instance.loadBlocks();
  });

  Future<void> _unblock(BlockedPlayer p) async {
    setState(() => _busy.add(p.id));
    final ok = await _run(
      context,
      () => ModerationService.instance.unblock(p.id),
      done: 'Engel kaldırıldı.',
    );
    if (!mounted) return;
    setState(() {
      _busy.remove(p.id);
      if (ok) {
        _future = _future.then(
          (list) => list.where((b) => b.id != p.id).toList(),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Engellenen oyuncular')),
    body: FutureBuilder<List<BlockedPlayer>>(
      future: _future,
      builder: (context, snap) {
        if (snap.connectionState != ConnectionState.done) {
          return const Center(child: CircularProgressIndicator());
        }
        if (snap.hasError) {
          return _message(
            Icons.cloud_off_rounded,
            'Liste yüklenemedi',
            'Bağlantını kontrol edip yeniden dene.',
            action: TextButton(
              onPressed: _reload,
              child: const Text('Yeniden dene'),
            ),
          );
        }
        final list = snap.data ?? const [];
        if (list.isEmpty) {
          return _message(
            Icons.verified_user_outlined,
            'Engellediğin oyuncu yok',
            'Düelloda, kayıtlı rakipte ya da sıralamada bir oyuncunun yanındaki '
                '⋯ düğmesinden şikâyet edebilir veya engelleyebilirsin.',
          );
        }
        return ListView(
          padding: const EdgeInsets.all(20),
          children: [
            Text(
              'Engellediğin oyuncularla eşleşmezsin; sıralamada adları sana '
              '“Engellenen oyuncu” olarak görünür.',
              style: FK.t(size: 14, color: FK.muted, height: 1.4),
            ),
            const SizedBox(height: 14),
            for (final p in list)
              Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
                decoration: BoxDecoration(
                  color: FK.navy2,
                  border: Border.all(color: FK.glassBorder),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    AvatarCircle(p.name, size: 40),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _handle(p.name),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: FK.t(size: 16, w: FontWeight.w700),
                      ),
                    ),
                    TextButton(
                      key: Key('unblock-${p.id}'),
                      onPressed: _busy.contains(p.id)
                          ? null
                          : () => _unblock(p),
                      child: const Text('Engeli kaldır'),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    ),
  );

  Widget _message(IconData icon, String title, String text, {Widget? action}) =>
      Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 48, color: FK.amber),
              const SizedBox(height: 12),
              Text(
                title,
                textAlign: TextAlign.center,
                style: FK.t(size: 20, w: FontWeight.w700),
              ),
              const SizedBox(height: 6),
              Text(
                text,
                textAlign: TextAlign.center,
                style: FK.t(color: FK.muted, height: 1.4),
              ),
              ?action,
            ],
          ),
        ),
      );
}
