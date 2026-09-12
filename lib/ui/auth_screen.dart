import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import 'theme.dart';
import 'widgets.dart';

const bool kSocialAuthEnabled = bool.fromEnvironment('SOCIAL_AUTH');

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key, required this.onGuest});
  final VoidCallback onGuest;
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final email = TextEditingController();
  final password = TextEditingController();
  final username = TextEditingController();
  Timer? usernameTimer;
  bool? usernameAvailable;
  bool checkingUsername = false;
  bool register = true;
  bool hidden = true;

  @override
  void dispose() {
    email.dispose();
    password.dispose();
    username.dispose();
    usernameTimer?.cancel();
    super.dispose();
  }

  void checkUsername(String raw) {
    usernameTimer?.cancel();
    final value = raw.trim();
    final valid = RegExp(r'^[a-zA-Z0-9_]{3,20}$').hasMatch(value);
    setState(() {
      usernameAvailable = null;
      checkingUsername = valid;
    });
    if (!valid) return;
    usernameTimer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final available = await AuthService.instance.usernameAvailable(value);
        if (mounted && username.text.trim() == value) {
          setState(() {
            usernameAvailable = available;
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
    } catch (_) {
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance;
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const LogoWidget(width: 260),
                  const SizedBox(height: 28),
                  Text(
                    register ? 'Sahaya adını yaz.' : 'Tekrar hoş geldin.',
                    style: FK.t(size: 30, w: FontWeight.w700),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rekorunu kaydet, gerçek oyuncularla yarış ve bütün cihazlarında kaldığın yerden devam et.',
                    style: FK.t(size: 16, color: FK.muted, height: 1.45),
                  ),
                  const SizedBox(height: 26),
                  if (kSocialAuthEnabled && !kIsWeb && Platform.isIOS) ...[
                    _social(
                      Icons.apple,
                      'Apple ile devam et',
                      () => run(auth.apple),
                      dark: false,
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (kSocialAuthEnabled)
                    _social(
                      Icons.g_mobiledata_rounded,
                      'Google ile devam et',
                      () => run(auth.google),
                    ),
                  if (kSocialAuthEnabled)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 22),
                      child: Row(
                        children: [
                          Expanded(child: Divider()),
                          Padding(
                            padding: EdgeInsets.symmetric(horizontal: 12),
                            child: Text('veya'),
                          ),
                          Expanded(child: Divider()),
                        ],
                      ),
                    ),
                  if (register) ...[
                    TextField(
                      controller: username,
                      onChanged: checkUsername,
                      autocorrect: false,
                      textCapitalization: TextCapitalization.none,
                      maxLength: 20,
                      decoration: InputDecoration(
                        labelText: 'Kullanıcı adı',
                        prefixText: '@',
                        helperText: usernameAvailable == true
                            ? 'Bu kullanıcı adı kullanılabilir'
                            : '3–20 karakter · harf, rakam ve _',
                        helperStyle: usernameAvailable == true
                            ? FK.t(color: FK.green)
                            : null,
                        prefixIcon: const Icon(Icons.alternate_email_rounded),
                        suffixIcon: checkingUsername
                            ? const Padding(
                                padding: EdgeInsets.all(14),
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                            : usernameAvailable == null
                            ? null
                            : Icon(
                                usernameAvailable!
                                    ? Icons.check_circle
                                    : Icons.cancel,
                                color: usernameAvailable! ? FK.green : FK.red,
                              ),
                      ),
                    ),
                    if (usernameAvailable == false)
                      Text(
                        'Bu kullanıcı adı alınmış. Başka bir tane dene.',
                        style: FK.t(color: FK.red),
                      ),
                    const SizedBox(height: 14),
                  ],
                  TextField(
                    controller: email,
                    keyboardType: TextInputType.emailAddress,
                    autofillHints: const [AutofillHints.email],
                    decoration: const InputDecoration(
                      labelText: 'E-posta',
                      prefixIcon: Icon(Icons.mail_outline_rounded),
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextField(
                    controller: password,
                    obscureText: hidden,
                    autofillHints: [
                      register
                          ? AutofillHints.newPassword
                          : AutofillHints.password,
                    ],
                    decoration: InputDecoration(
                      labelText: 'Parola',
                      prefixIcon: const Icon(Icons.lock_outline_rounded),
                      helperText: register ? 'En az 8 karakter' : null,
                      suffixIcon: IconButton(
                        onPressed: () => setState(() => hidden = !hidden),
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
                      padding: const EdgeInsets.only(top: 14),
                      child: Text(
                        auth.error!,
                        style: FK.t(color: FK.red, height: 1.3),
                      ),
                    ),
                  const SizedBox(height: 20),
                  FilledButton.icon(
                    onPressed:
                        auth.loading || (register && usernameAvailable != true)
                        ? null
                        : () => run(
                            () => auth.emailAuth(
                              email.text,
                              password.text,
                              register: register,
                              username: username.text,
                            ),
                          ),
                    icon: auth.loading
                        ? const SizedBox.square(
                            dimension: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.sports_soccer),
                    label: Text(register ? 'HESABINI OLUŞTUR' : 'GİRİŞ YAP'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(56),
                      backgroundColor: FK.orange,
                    ),
                  ),
                  TextButton(
                    onPressed: auth.loading
                        ? null
                        : () => setState(() {
                            register = !register;
                            usernameAvailable = null;
                            checkingUsername = false;
                            usernameTimer?.cancel();
                            auth.error = null;
                          }),
                    child: Text(
                      register
                          ? 'Zaten hesabın var mı? Giriş yap'
                          : 'Yeni misin? Hesap oluştur',
                    ),
                  ),
                  OutlinedButton.icon(
                    onPressed: auth.loading ? null : widget.onGuest,
                    icon: const Icon(Icons.sports_soccer_outlined),
                    label: const Text('ŞİMDİLİK MİSAFİR OYNA'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(52),
                      side: const BorderSide(color: FK.glassBorder),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Devam ederek Kullanım Koşulları ve Gizlilik Politikası’nı kabul etmiş olursun.',
                    textAlign: TextAlign.center,
                    style: FK.t(size: 12, color: FK.muted, height: 1.35),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _social(
    IconData icon,
    String label,
    VoidCallback tap, {
    bool dark = true,
  }) => OutlinedButton.icon(
    onPressed: AuthService.instance.loading ? null : tap,
    icon: Icon(icon, size: 28),
    label: Text(label),
    style: OutlinedButton.styleFrom(
      minimumSize: const Size.fromHeight(54),
      foregroundColor: dark ? FK.text : FK.navy,
      backgroundColor: dark ? FK.navy2 : Colors.white,
      side: BorderSide(color: dark ? FK.glassBorder : Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
    ),
  );
}
