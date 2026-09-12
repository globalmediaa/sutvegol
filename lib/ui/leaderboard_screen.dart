import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../game/geometry.dart';
import 'theme.dart';
import 'widgets.dart';

/// Gerçek cihaz rekoru; çevrimiçi sıralama veya örnek oyuncu göstermez.
class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key, required this.myScore});
  final int myScore;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('Kişisel rekor')),
    body: FutureBuilder<SharedPreferences>(
      future: SharedPreferences.getInstance(),
      builder: (context, snapshot) {
        final best = snapshot.data?.getInt('best') ?? myScore;
        return ListView(padding: const EdgeInsets.all(24), children: [
          const Center(child: LogoWidget(width: 240, subtitle: false)),
          const SizedBox(height: 24),
          Text('Bir sonraki şut, yeni bir rekor.', style: FK.t(size: 28, w: FontWeight.w700)),
          const SizedBox(height: 24),
          GlassCard(padding: const EdgeInsets.all(24), child: Column(children: [
            const Icon(Icons.emoji_events_rounded, color: FK.amber, size: 44),
            Text('$best', style: FK.t(size: 56, w: FontWeight.w700, color: FK.amber)),
            const Text('Bu cihazdaki en yüksek puan'),
            const SizedBox(height: 16),
            Text('Son tur: $myScore puan'),
          ])),
          const SizedBox(height: 24),
          Text('SAHALAR', style: FK.t(size: 18, w: FontWeight.w700)),
          for (final stage in Stage.values)
            ListTile(contentPadding: EdgeInsets.zero,
              leading: Icon(best >= stage.minScore ? Icons.check_circle : Icons.lock_outline,
                color: best >= stage.minScore ? FK.amber : FK.muted),
              title: Text(stage.label), subtitle: Text('${stage.minScore}+ puan')),
          const SizedBox(height: 16),
          Text('Rekorun cihazında saklanır. İnternet bağlantısı veya hesap gerekmez.', style: FK.t(size: 15, color: FK.muted)),
        ]);
      },
    ),
  );
}
