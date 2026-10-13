import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'moderation_ui.dart';
import 'theme.dart';
import 'widgets.dart';

/// Apple / Google ile girişten sonra tek adım: sıralamada görünecek takma ad.
class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});
  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final controller = TextEditingController();
  Timer? timer;
  UsernameCheck? check;
  bool checking = false;

  /// Kullanım Koşulları onayı; işaretlenmeden ad kaydedilemez.
  bool consent = false;
  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  void changed(String raw) {
    timer?.cancel();
    final value = raw.trim();
    final valid = RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(value);
    setState(() {
      check = null;
      checking = valid;
    });
    if (!valid) return;
    timer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final result = await AuthService.instance.checkUsername(value);
        if (mounted && controller.text.trim() == value) {
          setState(() {
            check = result;
            checking = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => checking = false);
      }
    });
  }

  Future<void> _submit() async {
    try {
      await AuthService.instance.chooseUsername(controller.text);
    } catch (e) {
      if (mounted) setState(() => check = usernameRejected(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final busy = auth.loading;
    final pad = MediaQuery.paddingOf(context);
    final feedback = usernameFeedback(check);
    final free = check?.available == true && check!.allowed;
    return Scaffold(
      backgroundColor: FK.navy,
      body: GameBackdrop(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, pad.top + 20, 20, pad.bottom + 20),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const BrandHeader(width: 220),
                  const SizedBox(height: 16),
                  GlassCard(
                    radius: 28,
                    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          'SON ADIM',
                          textAlign: TextAlign.center,
                          style: FK.t(
                            size: 12,
                            w: FontWeight.w700,
                            color: FK.amber,
                            spacing: 3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Forma adını seç.',
                          textAlign: TextAlign.center,
                          style: FK.t(size: 30, w: FontWeight.w700),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sıralamada bu ad görünecek; hesabına kalıcı olarak bağlanır.',
                          textAlign: TextAlign.center,
                          style: FK.t(size: 15, color: FK.muted, height: 1.4),
                        ),
                        const SizedBox(height: 22),
                        TextField(
                          controller: controller,
                          onChanged: changed,
                          autocorrect: false,
                          textCapitalization: TextCapitalization.none,
                          maxLength: 20,
                          style: FK.t(size: 16),
                          decoration: gameInput(
                            label: 'Kullanıcı adı',
                            icon: Icons.alternate_email_rounded,
                            helper: feedback.text,
                            helperStyle: feedback.style,
                            helperMaxLines: 3,
                            suffix: checking
                                ? const Padding(
                                    padding: EdgeInsets.all(14),
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: FK.amber,
                                    ),
                                  )
                                : feedback.ok == null
                                ? null
                                : Icon(
                                    feedback.ok!
                                        ? Icons.check_circle_rounded
                                        : Icons.cancel_rounded,
                                    color: feedback.ok! ? FK.green : FK.red,
                                  ),
                          ),
                        ),
                        if (auth.error != null)
                          Padding(
                            padding: const EdgeInsets.only(top: 12),
                            child: Text(
                              auth.error!,
                              style: FK.t(size: 13, color: FK.red, height: 1.3),
                            ),
                          ),
                        const SizedBox(height: 14),
                        TermsConsent(
                          value: consent,
                          onChanged: (v) => setState(() => consent = v),
                        ),
                        const SizedBox(height: 14),
                        if (busy)
                          const BusyPill(height: 58)
                        else
                          PillButton(
                            label: 'SAHAYA ÇIK',
                            icon: Icons.sports_soccer,
                            height: 58,
                            enabled: free && consent,
                            onTap: _submit,
                          ),
                        const SizedBox(height: 10),
                        PillButton(
                          label: 'FARKLI HESAPLA GİR',
                          primary: false,
                          height: 50,
                          fontSize: 15,
                          enabled: !busy,
                          onTap: auth.logout,
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
    );
  }
}
