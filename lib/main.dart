import 'package:flame/game.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'game/sut_ve_gol_game.dart';
import 'services/auth_service.dart';
import 'services/game_service.dart';
import 'ui/auth_screen.dart';
import 'ui/game_over_overlay.dart';
import 'ui/leaderboard_screen.dart';
import 'ui/loading_screen.dart';
import 'ui/logo.dart';
import 'ui/mock_data.dart';
import 'ui/pause_overlay.dart';
import 'ui/profile_dialog.dart';
import 'ui/theme.dart';
import 'ui/username_screen.dart';

/// Geliştirme: `--dart-define=UI_PREVIEW=leaderboard|profile|pause|gameover` ile ekranı doğrudan açar.
const String kUiPreview = String.fromEnvironment('UI_PREVIEW');

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  await loadBrandIdentity();
  await AuthService.instance.initialize();
  runApp(const SutVeGolApp());
}

class SutVeGolApp extends StatelessWidget {
  const SutVeGolApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp(
    title: 'Şut ve Gol',
    debugShowCheckedModeBanner: false,
    theme: ThemeData(
      fontFamily: FK.font,
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: FK.navy,
      colorScheme: ColorScheme.fromSeed(
        seedColor: FK.orange,
        brightness: Brightness.dark,
      ),
    ),
    home: const AuthGate(),
  );
}

class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  bool guest = false;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: AuthService.instance,
    builder: (context, _) {
      final auth = AuthService.instance;
      if (auth.loading && auth.user == null) {
        return const LoadingScreen();
      }
      if (auth.user == null && !guest) {
        return AuthScreen(onGuest: () => setState(() => guest = true));
      }
      if (!guest && auth.user!.needsUsername) return const UsernameScreen();
      return GameScreen(guest: guest);
    },
  );
}

/// Oyun ekranı; çıkışta Yükleniyor gösterip oyunu baştan kurar.
class GameScreen extends StatefulWidget {
  const GameScreen({super.key, this.guest = false});
  final bool guest;

  @override
  State<GameScreen> createState() => _GameScreenState();
}

class _GameScreenState extends State<GameScreen> {
  final _online = GameSessionService();
  late SutVeGolGame _game = _create();

  @override
  void initState() {
    super.initState();
    if (kUiPreview.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        if (kUiPreview == 'leaderboard') {
          Navigator.of(context).push(
            MaterialPageRoute<void>(
              builder: (_) => const LeaderboardScreen(myScore: 450),
            ),
          );
        } else if (kUiPreview == 'profile') {
          showProfileDialog(context, lbEntries(LbTab.season)[3]);
        } else if (kUiPreview == 'pause' || kUiPreview == 'gameover') {
          // Splash bittikten sonra perdeyi aç.
          await Future<void>.delayed(const Duration(seconds: 9));
          if (!mounted) return;
          if (kUiPreview == 'pause') {
            _game.pause();
          } else {
            _game.state = GameState.gameOver;
            _game.overlays.add(kGameOverOverlay);
          }
        }
      });
    }
  }

  SutVeGolGame _create() {
    final g = SutVeGolGame();
    g.onExit = _exit;
    g.onRunStarted = () => unawaited(_online.start());
    g.onRunFinished = (run) => unawaited(
      _online.finish(
        score: run.score,
        shots: run.shots,
        hits: run.hits,
        misses: run.misses,
        feverHits: run.feverHits,
        maxStreak: run.maxStreak,
        durationMs: run.durationMs,
        stage: run.stage,
      ),
    );
    return g;
  }

  Future<void> _exit() async {
    final run = _game.runSummary;
    unawaited(
      _online.finish(
        score: run.score,
        shots: run.shots,
        hits: run.hits,
        misses: run.misses,
        feverHits: run.feverHits,
        maxStreak: run.maxStreak,
        durationMs: run.durationMs,
        stage: run.stage,
      ),
    );
    final nav = Navigator.of(context);
    nav.push(
      PageRouteBuilder<void>(
        pageBuilder: (_, a, b) => const LoadingScreen(),
        transitionDuration: Duration.zero,
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    if (!mounted) return;
    setState(() => _game = _create());
    nav.pop();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FK.navy,
    body: GameWidget<SutVeGolGame>(
      key: ValueKey(_game),
      game: _game,
      overlayBuilderMap: {
        kGameOverOverlay: (context, game) => GameOverOverlay(game: game),
        kPauseOverlay: (context, game) =>
            PauseOverlay(game: game, guest: widget.guest),
      },
    ),
  );
}
