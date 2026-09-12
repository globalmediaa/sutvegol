import 'package:flutter/material.dart';
import '../services/auth_service.dart';
import 'theme.dart';
import 'widgets.dart';

class AccountScreen extends StatelessWidget {
  const AccountScreen({super.key});
  @override
  Widget build(BuildContext context) {
    final auth = AuthService.instance, user = auth.user!;
    return Scaffold(
      appBar: AppBar(title: const Text('Hesabım')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Center(
            child: AvatarCircle(
              user.username ?? 'Oyuncu',
              size: 88,
              ring: FK.orange,
            ),
          ),
          const SizedBox(height: 14),
          Center(
            child: Text(
              '@${user.username}',
              style: FK.t(size: 26, w: FontWeight.w700),
            ),
          ),
          if (user.email != null)
            Center(
              child: Text(user.email!, style: FK.t(color: FK.muted)),
            ),
          const SizedBox(height: 28),
          GlassCard(
            padding: const EdgeInsets.all(18),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(
                    Icons.verified_user_outlined,
                    color: FK.green,
                  ),
                  title: const Text('Benzersiz kullanıcı adı'),
                  subtitle: const Text('Sıralamada ve profilinde görünür.'),
                ),
                ListTile(
                  leading: const Icon(
                    Icons.cloud_done_outlined,
                    color: FK.cyan,
                  ),
                  title: const Text('Bulut senkronizasyonu'),
                  subtitle: const Text(
                    'Skorların hesabına güvenli şekilde bağlıdır.',
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 20),
          OutlinedButton.icon(
            onPressed: () => auth.logout(),
            icon: const Icon(Icons.logout_rounded),
            label: const Text('Çıkış yap'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
            ),
          ),
          const SizedBox(height: 28),
          Text(
            'HESAP YÖNETİMİ',
            style: FK.t(
              size: 12,
              w: FontWeight.w700,
              color: FK.muted,
              spacing: 1.5,
            ),
          ),
          const SizedBox(height: 8),
          TextButton.icon(
            style: TextButton.styleFrom(
              foregroundColor: FK.red,
              minimumSize: const Size.fromHeight(48),
              alignment: Alignment.centerLeft,
            ),
            onPressed: () => _delete(context, auth),
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Hesabımı kalıcı olarak sil'),
          ),
        ],
      ),
    );
  }

  Future<void> _delete(BuildContext context, AuthService auth) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('Hesap silinsin mi?'),
        content: const Text(
          'Kullanıcı adın, giriş bağlantıların ve kişisel istatistiklerin kalıcı olarak silinir. Bu işlem geri alınamaz.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('Vazgeç'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: FK.red),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('Kalıcı olarak sil'),
          ),
        ],
      ),
    );
    if (ok == true) {
      try {
        await auth.deleteAccount();
        if (context.mounted) Navigator.pop(context);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(auth.error ?? 'Hesap silinemedi.')),
          );
        }
      }
    }
  }
}
