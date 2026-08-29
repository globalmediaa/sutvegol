import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'game/kick_legend_game.dart';
import 'ui/game_over_overlay.dart';
import 'ui/loading_screen.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const KickLegendApp());
}

class KickLegendApp extends StatelessWidget {
  const KickLegendApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: ThemeData(fontFamily: 'TitilliumWeb', useMaterial3: true),
        home: const GameScreen(),
      );
}

/// Oyun ekranı; çıkışta kırmızı Loading gösterip oyunu baştan kurar.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key});

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  late KickLegendGame _game = _create();

  KickLegendGame _create() {
    final g = KickLegendGame();
    g.onExit = _exit;
    return g;
  }

  Future<void> _exit() async {
    final nav = Navigator.of(context);
    nav.push(PageRouteBuilder<void>(pageBuilder: (_, __, ___) => const LoadingScreen(), transitionDuration: Duration.zero));
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() => _game = _create());
    nav.pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: Colors.black,
        body: GameWidget<KickLegendGame>(
          key: ValueKey(_game),
          game: _game,
          overlayBuilderMap: {
            kGameOverOverlay: (context, game) => GameOverOverlay(game: game),
          },
        ),
      );
}
