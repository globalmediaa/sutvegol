import 'dart:async';
import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'theme.dart';
import 'widgets.dart';

class UsernameScreen extends StatefulWidget {
  const UsernameScreen({super.key});
  @override
  State<UsernameScreen> createState() => _UsernameScreenState();
}

class _UsernameScreenState extends State<UsernameScreen> {
  final controller = TextEditingController();
  Timer? timer;
  bool? available;
  bool checking = false;
  @override
  void dispose() {
    timer?.cancel();
    controller.dispose();
    super.dispose();
  }

  void changed(String value) {
    timer?.cancel();
    setState(() {
      available = null;
      checking = value.length >= 3;
    });
    if (value.length < 3) return;
    timer = Timer(const Duration(milliseconds: 450), () async {
      try {
        final ok = await AuthService.instance.usernameAvailable(value);
        if (mounted) {
          setState(() {
            available = ok;
            checking = false;
          });
        }
      } catch (_) {
        if (mounted) setState(() => checking = false);
      }
    });
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 440),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const LogoWidget(width: 220, subtitle: false),
                const SizedBox(height: 28),
                Text(
                  'Benzersiz kullanıcı adın',
                  style: FK.t(size: 30, w: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Sıralamada bu ad görünecek. Bir başkası aldıysa kullanılamaz; seçimin hesabına kalıcı olarak bağlanır.',
                  style: FK.t(size: 16, color: FK.muted, height: 1.45),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: controller,
                  onChanged: changed,
                  autocorrect: false,
                  textCapitalization: TextCapitalization.none,
                  maxLength: 20,
                  decoration: InputDecoration(
                    labelText: 'Kullanıcı adı',
                    prefixText: '@',
                    helperText: '3–20 karakter · harf, rakam ve _',
                    suffixIcon: checking
                        ? const Padding(
                            padding: EdgeInsets.all(14),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : available == null
                        ? null
                        : Icon(
                            available! ? Icons.check_circle : Icons.cancel,
                            color: available! ? FK.green : FK.red,
                          ),
                  ),
                ),
                if (available == false)
                  Text(
                    'Bu kullanıcı adı alınmış. Başka bir tane dene.',
                    style: FK.t(color: FK.red),
                  ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: available == true && !AuthService.instance.loading
                      ? () async {
                          try {
                            await AuthService.instance.chooseUsername(
                              controller.text,
                            );
                          } catch (_) {
                            if (mounted) setState(() => available = false);
                          }
                        }
                      : null,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(56),
                    backgroundColor: FK.orange,
                  ),
                  child: const Text('SAHAYA ÇIK'),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
