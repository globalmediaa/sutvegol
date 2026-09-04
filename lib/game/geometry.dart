import 'dart:ui';

import 'package:flame/components.dart';

/// Tüm sahne 1320x2868 sanal çözünürlükte (dikey telefon).
const double kWorldW = 1320;
const double kWorldH = 2868;

/// Topun doğal çapı (üretilen top görseli 216 px kare).
const double kBallDiameter = 216;

/// Hedef halkasının çapı.
const double kTargetDiameter = 148;

/// Oyunun sahneleri: skor arttıkça sokaktan stadyuma.
enum Stage {
  street('SOKAK', 0, Color(0xFFFF7A1A)),
  cage('HALI SAHA', 300, Color(0xFF35D5F2)),
  stadium('STADYUM', 900, Color(0xFFFFC53D));

  const Stage(this.label, this.minScore, this.accent);
  final String label;
  final int minScore;
  final Color accent;

  static Stage forScore(int score) {
    var s = Stage.street;
    for (final st in Stage.values) {
      if (score >= st.minScore) s = st;
    }
    return s;
  }
}

/// Bir kamera görünümünün (geniş / yakın) sabit ölçüleri.
class ViewGeom {
  const ViewGeom({
    required this.name,
    required this.goalLeft,
    required this.goalRight,
    required this.crossbarY,
    required this.groundY,
    required this.ballRest,
    required this.ballRestScale,
    required this.ballGoalScale,
    required this.boardRect,
    required this.scoreRect,
    required this.bestRect,
    required this.heartFirst,
    required this.heartGap,
    required this.heartScale,
    required this.railY,
    required this.keeperScale,
    required this.zoom,
  });

  /// Üretilen arka plan anahtarının parçası ("wide" / "zoom").
  final String name;

  /// Kale ağzı (direklerin iç kenarları) ve üst direk altı / kale çizgisi.
  final double goalLeft, goalRight, crossbarY, groundY;

  /// Topun bekleme merkezi ve ölçeği; kale düzlemindeki ölçek.
  final Vector2 ballRest;
  final double ballRestScale;
  final double ballGoalScale;

  /// Tabela paneli ve içindeki rakam alanları (6 hane).
  final Rect boardRect;
  final Rect scoreRect;
  final Rect bestRect;

  /// Kalpler: ilkinin merkezi, dikey aralık, ölçek.
  final Vector2 heartFirst;
  final double heartGap;
  final double heartScale;

  /// Kaleci mankeninin rayı (üst kenar y) ve ölçeği.
  final double railY;
  final double keeperScale;

  /// Arka plan katmanlarının büyütme oranı (kamera yaklaşması).
  final double zoom;

  double get goalWidth => goalRight - goalLeft;
  double get goalCenterX => (goalLeft + goalRight) / 2;
  double get goalHeight => groundY - crossbarY;

  String bgKey(Stage s) => 'bg_${s.name}_$name';
}

final ViewGeom kWide = ViewGeom(
  name: 'wide',
  goalLeft: 398,
  goalRight: 940,
  crossbarY: 1290,
  groundY: 1636,
  ballRest: Vector2(665, 2323),
  ballRestScale: 1.0,
  ballGoalScale: 0.20,
  boardRect: const Rect.fromLTRB(410, 846, 960, 1112),
  scoreRect: const Rect.fromLTRB(520, 896, 800, 960),
  bestRect: const Rect.fromLTRB(520, 998, 800, 1062),
  heartFirst: Vector2(884, 916),
  heartGap: 60,
  heartScale: 1.0,
  railY: 1685,
  keeperScale: 1.0,
  zoom: 1.0,
);

final ViewGeom kZoom = ViewGeom(
  name: 'zoom',
  goalLeft: 388,
  goalRight: 955,
  crossbarY: 1262,
  groundY: 1682,
  ballRest: Vector2(657, 2454),
  ballRestScale: 1.12,
  ballGoalScale: 0.28,
  boardRect: const Rect.fromLTRB(300, 700, 1020, 1030),
  scoreRect: const Rect.fromLTRB(440, 760, 800, 850),
  bestRect: const Rect.fromLTRB(440, 885, 800, 975),
  heartFirst: Vector2(908, 790),
  heartGap: 74,
  heartScale: 1.2,
  railY: 1760,
  keeperScale: 1.3,
  zoom: 1.14,
);

/// Sağ üstteki pause butonu (arka plana çizilir, burası dokunma alanı).
const Rect kPauseRect = Rect.fromLTRB(1040, 130, 1290, 380);
