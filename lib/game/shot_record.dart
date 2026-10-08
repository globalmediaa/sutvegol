import 'package:flame/components.dart';

import 'geometry.dart';

/// Topun kale düzlemine ulaştığında izlediği yol.
enum ShotPath { net, keeper, post, out }

/// Bir şutun tam kaydı: girdi (kaydırma), o andaki sahne durumu ve şutu atan
/// cihazın HESAPLADIĞI sonuç + sonuç sonrası durum. Düelloda rakibe bu kayıt
/// gönderilir; rakibin ekranındaki kopya oyun uçuşu girdiden canlandırır,
/// sonucu ise kayıttan zorlar. Böylece iki cihazın kayan nokta/rastgelelik
/// uyumuna hiç güvenilmez.
class ShotRecord {
  const ShotRecord({
    required this.seq,
    required this.t,
    required this.stage,
    required this.view,
    required this.target,
    required this.chord,
    required this.dev,
    required this.tMax,
    required this.power,
    required this.keeper,
    required this.path,
    required this.hit,
    required this.end,
    required this.drop,
    required this.score,
    required this.lives,
    required this.streak,
    required this.fever,
    required this.feverLeft,
    required this.shots,
    required this.hits,
    required this.misses,
    required this.feverHits,
    required this.maxStreak,
  });

  static const int version = 1;

  /// Kayıt sırası (1'den başlar, boşluksuz).
  final int seq;

  /// Koşunun başından itibaren geçen oyun süresi (ms, simülasyon saati).
  final int t;

  /// Şut anındaki sahne (`Stage.name`) ve kamera (`wide` | `zoom`).
  final String stage;
  final String view;

  /// Şut anındaki hedef konumu (dünya px); hedef görünmüyorsa null.
  final Vector2? target;

  /// InputLayer → kick() parametreleri.
  final Vector2 chord;
  final double dev;
  final double tMax;
  final double power;

  /// İki kalecinin şut anındaki etkin süresi (s); pasif kaleci null.
  final List<double?> keeper;

  /// Sonuç: yol, isabet, topun kale düzlemindeki bitiş noktası ve
  /// (kaleci/direk için) düştüğü nokta.
  final ShotPath path;
  final bool hit;
  final Vector2 end;
  final Vector2? drop;

  /// Sonuç uygulandıktan SONRAKİ durum (yetkili değerler).
  final int score;
  final int lives;
  final int streak;
  final bool fever;
  final double feverLeft;
  final int shots;
  final int hits;
  final int misses;
  final int feverHits;
  final int maxStreak;

  Map<String, dynamic> toJson() => {
    'v': version,
    'seq': seq,
    't': t,
    'stage': stage,
    'view': view,
    'target': target == null ? null : _vec(target!),
    'chord': _vec(chord),
    'dev': _r(dev),
    'tMax': _r(tMax, 3),
    'power': _r(power, 3),
    'keeper': [for (final k in keeper) k == null ? null : _r(k, 3)],
    'path': path.name,
    'hit': hit,
    'end': _vec(end),
    'drop': drop == null ? null : _vec(drop!),
    'score': score,
    'lives': lives,
    'streak': streak,
    'fever': fever,
    'feverLeft': _r(feverLeft),
    'shots': shots,
    'hits': hits,
    'misses': misses,
    'feverHits': feverHits,
    'maxStreak': maxStreak,
  };

  /// Uzaktan gelen kaydı doğrulayarak çözer; geçersiz/aralık dışı değerlerde
  /// [FormatException] atar (kopya oyun hiçbir zaman çöpe maruz kalmaz).
  factory ShotRecord.fromJson(Map<String, dynamic> j) {
    if (j['v'] != version) throw const FormatException('version');
    final stage = j['stage'];
    if (stage is! String || !Stage.values.any((s) => s.name == stage)) {
      throw const FormatException('stage');
    }
    final view = j['view'];
    if (view != 'wide' && view != 'zoom') throw const FormatException('view');
    final pathName = j['path'];
    final path = ShotPath.values.cast<ShotPath?>().firstWhere(
      (p) => p!.name == pathName,
      orElse: () => null,
    );
    if (path == null) throw const FormatException('path');
    final keeperRaw = j['keeper'];
    if (keeperRaw is! List || keeperRaw.length != 2) {
      throw const FormatException('keeper');
    }
    return ShotRecord(
      seq: _int(j['seq'], 1, 100000, 'seq'),
      t: _int(j['t'], 0, 86400000, 't'),
      stage: stage,
      view: view,
      target: j['target'] == null ? null : _vecFrom(j['target'], 'target'),
      chord: _vecFrom(j['chord'], 'chord', limit: 6000),
      dev: _num(j['dev'], -3000, 3000, 'dev'),
      tMax: _num(j['tMax'], 0, 1, 'tMax'),
      power: _num(j['power'], 0, 1, 'power'),
      keeper: [
        for (final k in keeperRaw)
          k == null ? null : _num(k, 0, 86400, 'keeper'),
      ],
      path: path,
      hit: _bool(j['hit'], 'hit'),
      end: _vecFrom(j['end'], 'end'),
      drop: j['drop'] == null ? null : _vecFrom(j['drop'], 'drop'),
      score: _int(j['score'], 0, 100000, 'score'),
      lives: _int(j['lives'], 0, 3, 'lives'),
      streak: _int(j['streak'], 0, 10000, 'streak'),
      fever: _bool(j['fever'], 'fever'),
      feverLeft: _num(j['feverLeft'], 0, 10, 'feverLeft'),
      shots: _int(j['shots'], 0, 10000, 'shots'),
      hits: _int(j['hits'], 0, 10000, 'hits'),
      misses: _int(j['misses'], 0, 10000, 'misses'),
      feverHits: _int(j['feverHits'], 0, 10000, 'feverHits'),
      maxStreak: _int(j['maxStreak'], 0, 10000, 'maxStreak'),
    );
  }

  /// Sayaçların kendi içinde tutarlı olup olmadığı (sunucu kuralıyla aynı).
  bool get consistent =>
      hits + misses <= shots &&
      feverHits <= hits &&
      score == (hits - feverHits) * 30 + feverHits * 60 &&
      (!fever || feverLeft > 0) &&
      (path != ShotPath.out || !hit);

  static List<double> _vec(Vector2 v) => [_r(v.x), _r(v.y)];

  static double _r(double v, [int digits = 2]) {
    final f = digits == 3 ? 1000 : 100;
    return (v * f).roundToDouble() / f;
  }

  static Vector2 _vecFrom(dynamic v, String name, {double limit = 4000}) {
    if (v is! List || v.length != 2) throw FormatException(name);
    return Vector2(
      _num(v[0], -limit, limit, name),
      _num(v[1], -limit, limit, name),
    );
  }

  static double _num(dynamic v, double min, double max, String name) {
    if (v is! num || v.isNaN || v.isInfinite) throw FormatException(name);
    final d = v.toDouble();
    if (d < min || d > max) throw FormatException('$name aralık dışı');
    return d;
  }

  static int _int(dynamic v, int min, int max, String name) {
    if (v is! num || v.isNaN || v.isInfinite) throw FormatException(name);
    final i = v.round();
    if (i < min || i > max) throw FormatException('$name aralık dışı');
    return i;
  }

  static bool _bool(dynamic v, String name) {
    if (v is! bool) throw FormatException(name);
    return v;
  }
}
