import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/game_service.dart';
import 'theme.dart';
import 'widgets.dart';

class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, required this.myScore});
  final int myScore;
  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  final service = GameSessionService();
  String period = 'weekly';
  late Future<List<LeaderboardEntry>> entries = service.leaderboard(period);

  void select(String value) => setState(() {
    period = value;
    entries = service.leaderboard(period);
  });

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('Sıralama'),
      actions: AuthService.instance.user == null
          ? null
          : [
              IconButton(
                tooltip: 'Çıkış yap',
                onPressed: () => AuthService.instance.logout(),
                icon: const Icon(Icons.logout_rounded),
              ),
            ],
    ),
    body: RefreshIndicator(
      onRefresh: () async =>
          setState(() => entries = service.leaderboard(period)),
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          const Center(child: LogoWidget(width: 220, subtitle: false)),
          const SizedBox(height: 20),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'daily', label: Text('Bugün')),
              ButtonSegment(value: 'weekly', label: Text('Hafta')),
              ButtonSegment(value: 'all', label: Text('Tümü')),
            ],
            selected: {period},
            onSelectionChanged: (value) => select(value.first),
          ),
          const SizedBox(height: 18),
          FutureBuilder<List<LeaderboardEntry>>(
            future: entries,
            builder: (context, snapshot) {
              if (snapshot.connectionState != ConnectionState.done) {
                return const Padding(
                  padding: EdgeInsets.all(60),
                  child: Center(child: CircularProgressIndicator()),
                );
              }
              if (snapshot.hasError) {
                return _empty(
                  Icons.cloud_off_rounded,
                  'Sıralama yüklenemedi',
                  'Aşağı çekerek tekrar deneyebilirsin.',
                );
              }
              final list = snapshot.data ?? [];
              if (list.isEmpty) {
                return _empty(
                  Icons.emoji_events_outlined,
                  'Henüz skor yok',
                  'İlk sıraya adını yazmak için oyuna dön.',
                );
              }
              return Column(
                children: [
                  for (var i = 0; i < list.length; i++) _row(i, list[i]),
                ],
              );
            },
          ),
        ],
      ),
    ),
  );

  Widget _row(int index, LeaderboardEntry entry) {
    final me = entry.username == AuthService.instance.user?.username;
    const medals = [FK.gold, FK.silver, FK.bronze];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: me ? FK.orange.withValues(alpha: .14) : FK.navy2,
        border: Border.all(color: me ? FK.orange : FK.glassBorder),
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: index < 3
                ? Icon(Icons.emoji_events_rounded, color: medals[index])
                : Text(
                    '${index + 1}',
                    style: FK.t(size: 17, w: FontWeight.w700, color: FK.muted),
                  ),
          ),
          AvatarCircle(entry.username, size: 46, ring: me ? FK.orange : null),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '@${entry.username}',
                  style: FK.t(size: 17, w: FontWeight.w700),
                ),
                Text(
                  '${entry.games} oyun',
                  style: FK.t(size: 12, color: FK.muted),
                ),
              ],
            ),
          ),
          Text(
            '${entry.score}',
            style: FK.t(
              size: 24,
              w: FontWeight.w700,
              color: index < 3 ? medals[index] : FK.text,
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty(IconData icon, String title, String text) => GlassCard(
    padding: const EdgeInsets.all(28),
    child: Column(
      children: [
        Icon(icon, size: 48, color: FK.amber),
        const SizedBox(height: 12),
        Text(title, style: FK.t(size: 22, w: FontWeight.w700)),
        const SizedBox(height: 5),
        Text(
          text,
          textAlign: TextAlign.center,
          style: FK.t(color: FK.muted, height: 1.4),
        ),
      ],
    ),
  );
}
