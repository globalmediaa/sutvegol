import 'dart:ui';

import 'package:flame/components.dart';

/// Tüm sahne 1320x2868 sanal çözünürlükte (video kaynağı ile birebir).
const double kWorldW = 1320;
const double kWorldH = 2868;

/// Kaynak topun doğal çapı (ball.png, 218px kare içinde ~216px top).
const double kBallDiameter = 216;

/// Hedef sprite çapı (target.png 148px).
const double kTargetDiameter = 148;

/// Bir kamera görünümünün (geniş / yakın) sabit ölçüleri.
class ViewGeom {
  const ViewGeom({
    required this.bg,
    required this.goalLeft,
    required this.goalRight,
    required this.crossbarY,
    required this.groundY,
    required this.ballRest,
    required this.ballRestScale,
    required this.ballGoalScale,
    required this.scoreRect,
    required this.bestRect,
    required this.skew,
    required this.heartFirst,
    required this.heartGap,
    required this.heartScale,
    required this.railY,
    required this.keeperScale,
  });

  final String bg;

  /// Kale ağzı (direklerin iç kenarları) ve üst direk altı / kale çizgisi.
  final double goalLeft, goalRight, crossbarY, groundY;

  /// Topun bekleme merkezi ve ölçeği; kale düzlemindeki ölçek.
  final Vector2 ballRest;
  final double ballRestScale;
  final double ballGoalScale;

  /// Skor tabelası rakam alanları (6 hane).
  final Rect scoreRect;
  final Rect bestRect;

  /// Yakın görünümde tabela perspektifi (dikey kayma oranı).
  final double skew;

  /// Kalpler: ilkinin merkezi, dikey aralık, ölçek.
  final Vector2 heartFirst;
  final double heartGap;
  final double heartScale;

  /// Kaleci mankeninin rayı (üst kenar y) ve ölçeği.
  final double railY;
  final double keeperScale;

  double get goalWidth => goalRight - goalLeft;
  double get goalCenterX => (goalLeft + goalRight) / 2;
  double get goalHeight => groundY - crossbarY;
}

final ViewGeom kWide = ViewGeom(
  bg: 'bg_wide.png',
  goalLeft: 398,
  goalRight: 940,
  crossbarY: 1290,
  groundY: 1636,
  ballRest: Vector2(665, 2323),
  ballRestScale: 1.0,
  ballGoalScale: 0.20,
  scoreRect: const Rect.fromLTRB(504, 902, 790, 965),
  bestRect: const Rect.fromLTRB(504, 1002, 790, 1066),
  skew: 0,
  heartFirst: Vector2(869, 916),
  heartGap: 60,
  heartScale: 1.0,
  railY: 1685,
  keeperScale: 1.0,
);

final ViewGeom kZoom = ViewGeom(
  bg: 'bg_zoom.png',
  goalLeft: 388,
  goalRight: 955,
  crossbarY: 1262,
  groundY: 1682,
  ballRest: Vector2(657, 2454),
  ballRestScale: 1.12,
  ballGoalScale: 0.28,
  scoreRect: const Rect.fromLTRB(320, 780, 645, 870),
  bestRect: const Rect.fromLTRB(320, 905, 645, 995),
  skew: 0.075,
  heartFirst: Vector2(718, 849),
  heartGap: 66,
  heartScale: 1.15,
  railY: 1760,
  keeperScale: 1.3,
);

/// Sağ üstteki pause butonu (arka plana gömülü, sadece dokunma alanı).
const Rect kPauseRect = Rect.fromLTRB(960, 145, 1275, 345);
