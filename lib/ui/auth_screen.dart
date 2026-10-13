import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/api_client.dart';
import '../services/auth_service.dart';
import 'moderation_ui.dart';
import 'theme.dart';
import 'widgets.dart';

/// Giriş / kayıt: oyunun sokak sahnesi önünde cam kart. Apple ve Google ile
/// tek dokunuşla giriş, e-posta ile hesap oluşturma / giriş, altta misafir.
class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onGuest});
  final VoidCallback onGuest;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen>
    with SingleTickerProviderStateMixin {
  final email = TextEditingController();
  final password = TextEditingController();
  final username = TextEditingController();
  Timer? usernameTimer;
  UsernameCheck? usernameCheck;
  bool checkingUsername = false;
  bool register = true;
  bool hidden = true;

  /// Kayıtta Kullanım Koşulları onayı; işaretlenmeden hesap açılmaz.
  bool consent = false;
  late final AnimationController _enter;
  late final TapGestureRecognizer _termsLink = TapGestureRecognizer()
    ..onTap = openTerms;
  late final TapGestureRecognizer _privacyLink = TapGestureRecognizer()
    ..onTap = () => launchUrl(
      Uri.parse('https://sutvegol.gmgaming.app/privacy'),
      mode: LaunchMode.externalApplication,
    );

  bool get appleAvailable => appleSignInAvailable;

  @override
  void initState() {
    super.initState();
    // Denetleyici burada kurulur; dispose() sırasında tembel oluşturulmasın.
    _enter = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 520),
    )..forward();
  }

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    username.dispose();
    usernameTimer?.cancel();
    _enter.dispose();
    _termsLink.dispose();
    _privacyLink.dispose();
    super.dispose();
  }

  void checkUsername(String raw) {
    usernameTimer?.cancel();
    final value = raw.trim();
    final valid = RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(value);
    setState(() {
      usernameCheck = null;
      checkingUsername = valid;
    });
    if (!valid) return;
    usernameTimer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final result = await AuthService.instance.checkUsername(value);
        if (mounted && username.text.trim() == value) {
          setState(() {
            usernameCheck = result;
            checkingUsername = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => checkingUsername = false);
      }
    });
  }

  Future<void> run(Future<void> Function() action) async {
    try {
      await action();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        if (register && e is ApiException && e.code == 'username_not_allowed') {
          usernameCheck = usernameRejected(e);
        }
      });
    }
  }

  void _switch(int index) => setState(() {
    register = index == 0;
    usernameCheck = null;
    checkingUsername = false;
    usernameTimer?.cancel();
    AuthService.instance.error = null;
  });

  bool get canSubmit =>
      !AuthService.instance.loading &&
      (!register ||
          (usernameCheck?.available == true &&
              usernameCheck!.allowed &&
              consent));

  Future<void> _submit() => run(
    () => AuthService.instance.emailAuth(
      email.text,
      password.text,
      register: register,
      username: username.text,
    ),
  );

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    final busy = auth.loading;
    final pad = MediaQuery.paddingOf(context);
    return Scaffold(
      backgroundColor: FK.navy,
      body: GameBackdrop(
        child: Center(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(20, pad.top + 6, 20, pad.bottom + 16),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: FadeTransition(
                opacity: _enter,
                child: SlideTransition(
                  position:
                      Tween(
                        begin: const Offset(0, 0.05),
                        end: Offset.zero,
                      ).animate(
                        CurvedAnimation(
                          parent: _enter,
                          curve: Curves.easeOutCubic,
                        ),
                      ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const BrandHeader(width: 190),
                      const SizedBox(height: 10),
                      GlassCard(
                        radius: 28,
                        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                        child: _card(auth, busy),
                      ),
                      const SizedBox(height: 10),
                      Text.rich(
                        TextSpan(
                          style: FK.t(size: 12, color: FK.muted, height: 1.35),
                          children: [
                            const TextSpan(text: 'Devam ederek '),
                            TextSpan(
                              text: 'Kullanım Koşulları',
                              style: FK.t(
                                size: 12,
                                color: FK.amber,
                                height: 1.35,
                              ).copyWith(decoration: TextDecoration.underline),
                              recognizer: _termsLink,
                            ),
                            const TextSpan(text: ' ve '),
                            TextSpan(
                              text: 'Gizlilik Politikası',
                              style: FK.t(
                                size: 12,
                                color: FK.amber,
                                height: 1.35,
                              ).copyWith(decoration: TextDecoration.underline),
                              recognizer: _privacyLink,
                            ),
                            const TextSpan(
                              text:
                                  '’nı kabul etmiş olursun. Uygunsuz içeriğe ve tacize sıfır tolerans uygulanır.',
                            ),
                          ],
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _card(AuthService auth, bool busy) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'SOKAKTAN STADYUMA',
        textAlign: TextAlign.center,
        style: FK.t(size: 12, w: FontWeight.w700, color: FK.amber, spacing: 3),
      ),
      const SizedBox(height: 6),
      Text(
        register ? 'Sahaya çık.' : 'Tekrar hoş geldin.',
        textAlign: TextAlign.center,
        style: FK.t(size: 28, w: FontWeight.w700),
      ),
      const SizedBox(height: 4),
      Text(
        register
            ? 'Rekorunu kaydet, sıralamada yerini al.'
            : 'Kaldığın yerden devam et.',
        textAlign: TextAlign.center,
        style: FK.t(size: 15, color: FK.muted, height: 1.4),
      ),
      const SizedBox(height: 16),
      if (appleAvailable) ...[
        SocialButton(
          label: 'Apple ile devam et',
          icon: const Icon(Icons.apple, color: Colors.black, size: 26),
          enabled: !busy,
          onTap: () => run(auth.apple),
        ),
        const SizedBox(height: 8),
      ],
      // Google kimliği bu derlemede yoksa düğme hiç gösterilmez.
      if (googleAvailable)
        SocialButton(
          label: 'Google ile devam et',
          icon: const GoogleMark(size: 22),
          enabled: !busy,
          onTap: () => run(auth.google),
        ),
      const SizedBox(height: 14),
      _divider('veya e-posta ile'),
      const SizedBox(height: 12),
      SegmentedPill(
        labels: const ['Hesap oluştur', 'Giriş yap'],
        index: register ? 0 : 1,
        onChanged: busy ? null : _switch,
      ),
      const SizedBox(height: 12),
      if (register) ...[_usernameField(), const SizedBox(height: 10)],
      TextField(
        controller: email,
        keyboardType: TextInputType.emailAddress,
        autofillHints: const [AutofillHints.email],
        style: FK.t(size: 16),
        decoration: gameInput(
          label: 'E-posta',
          icon: Icons.mail_outline_rounded,
        ),
      ),
      const SizedBox(height: 10),
      TextField(
        controller: password,
        obscureText: hidden,
        autofillHints: [
          register ? AutofillHints.newPassword : AutofillHints.password,
        ],
        style: FK.t(size: 16),
        decoration: gameInput(
          label: 'Parola',
          icon: Icons.lock_outline_rounded,
          helper: register ? 'En az 8 karakter' : null,
          suffix: IconButton(
            onPressed: () => setState(() => hidden = !hidden),
            color: FK.muted,
            icon: Icon(
              hidden
                  ? Icons.visibility_outlined
                  : Icons.visibility_off_outlined,
            ),
          ),
        ),
      ),
      if (auth.error != null)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Padding(
                padding: EdgeInsets.only(top: 1),
                child: Icon(
                  Icons.error_outline_rounded,
                  color: FK.red,
                  size: 18,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  auth.error!,
                  style: FK.t(size: 13, color: FK.red, height: 1.3),
                ),
              ),
            ],
          ),
        ),
      if (register) ...[
        const SizedBox(height: 12),
        TermsConsent(
          value: consent,
          onChanged: (v) => setState(() => consent = v),
        ),
      ],
      const SizedBox(height: 16),
      if (busy)
        const BusyPill(height: 56)
      else
        PillButton(
          label: register ? 'HESABINI OLUŞTUR' : 'GİRİŞ YAP',
          icon: Icons.sports_soccer,
          height: 56,
          enabled: canSubmit,
          onTap: _submit,
        ),
      const SizedBox(height: 8),
      PillButton(
        label: 'MİSAFİR OLARAK OYNA',
        primary: false,
        height: 48,
        fontSize: 15,
        enabled: !busy,
        onTap: widget.onGuest,
      ),
    ],
  );

  Widget _usernameField() {
    final feedback = usernameFeedback(usernameCheck);
    return TextField(
      controller: username,
      onChanged: checkUsername,
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
        suffix: checkingUsername
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
    );
  }

  Widget _divider(String text) => Row(
    children: [
      Expanded(child: Container(height: 1, color: FK.glassBorder)),
      Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Text(text, style: FK.t(size: 12, color: FK.muted, spacing: 0.5)),
      ),
      Expanded(child: Container(height: 1, color: FK.glassBorder)),
    ],
  );
}
