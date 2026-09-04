import 'package:flutter/material.dart' show IconData, Icons;

/// Sıralama için yerel örnek veri (sunucu yok). Avatarlar isimden üretilir.
class LbEntry {
  const LbEntry(this.name, this.pts, {this.level = 3, this.badges = 2, this.likes = 0, this.street = false});
  final String name;
  final int pts;
  final int level;
  final int badges;
  final int likes;

  /// Profil kartı arka planı: gece sahası (false) / sokak duvarı (true).
  final bool street;

  /// Kazanılmış rozetler (sırayla ilk N; "Sen" için Hoş geldin + Profil fotoğrafı).
  List<FkBadge> get earnedBadges => name == kMeName
      ? [kBadges.firstWhere((b) => b.id == 'welcome'), kBadges.firstWhere((b) => b.id == 'profile_picture')]
      : kBadges.take(badges.clamp(0, kBadges.length)).toList();
}

/// Rozet tanımı: gradyanlı yuvarlak kare (ikon ya da sayı); outline = çerçeveli.
class FkBadge {
  const FkBadge(this.id, this.label, this.color, {this.icon, this.text, this.outline = false});
  final String id;
  final String label;
  final int color;
  final IconData? icon;
  final String? text;
  final bool outline;
}

const int _orange = 0xFFFF7A1A;
const int _yellow = 0xFFFFC53D;
const int _red = 0xFFFF3B5C;
const int _teal = 0xFF1AA79C;
const int _green = 0xFF2ED47A;
const int _brown = 0xFF9A5B2A;
const int _blue = 0xFF2563EB;
const int _lightBlue = 0xFF35D5F2;
const int _purple = 0xFF8B3FD9;
const int _crimson = 0xFFB4173A;
const int _darkRed = 0xFF7F1D1D;

/// Rozetler: oyun içi başarılar + sahne/seri ödülleri.
const List<FkBadge> kBadges = [
  FkBadge('profile_picture', 'Profil fotoğrafı', _orange, icon: Icons.account_circle),
  FkBadge('complete_profile', 'Profil tamam', _yellow, icon: Icons.list_alt),
  FkBadge('first_goal', 'İlk gol', _green, icon: Icons.sports_soccer),
  FkBadge('hat_trick', 'Hat-trick', _green, text: '3'),
  FkBadge('street_king', 'Sokağın kralı', _orange, icon: Icons.location_city),
  FkBadge('beach_king', 'Sahil kralı', 0xFFFF5C8A, icon: Icons.beach_access),
  FkBadge('cage_king', 'Halı saha kralı', _lightBlue, icon: Icons.sports),
  FkBadge('stadium_king', 'Stadyum kralı', _yellow, icon: Icons.stadium),
  FkBadge('king_mode_1', 'İlk Kral Modu', _orange, icon: Icons.local_fire_department),
  FkBadge('king_mode_10', '10 Kral Modu', _orange, text: '10'),
  FkBadge('king_mode_50', '50 Kral Modu', _orange, text: '50'),
  FkBadge('streak_10', '10 seri', _teal, text: '10'),
  FkBadge('streak_25', '25 seri', _teal, text: '25'),
  FkBadge('streak_50', '50 seri', _teal, text: '50'),
  FkBadge('fk_season_1', 'Sezon #1', _blue, text: '1'),
  FkBadge('fk_season_3', 'Sezon ilk 3', _blue, text: '3'),
  FkBadge('fk_month_1', 'Ay #1', _lightBlue, text: '1', outline: true),
  FkBadge('fk_month_3', 'Ay ilk 3', _lightBlue, text: '3', outline: true),
  FkBadge('top10', 'İlk 10', _purple, text: '10'),
  FkBadge('pts500', '500 puan', _blue, text: '500'),
  FkBadge('pts1000', '1000 puan', _blue, text: '1K'),
  FkBadge('pts1500', '1500 puan', _blue, text: '1,5K'),
  FkBadge('pts2000', '2000 puan', _blue, text: '2K'),
  FkBadge('post_hit', 'Direkten döndü', _brown, icon: Icons.grid_on),
  FkBadge('keeper_beat', 'Kaleciyi geçti', _brown, text: '25'),
  FkBadge('curve', 'Falso ustası', _purple, icon: Icons.gesture),
  FkBadge('welcome', 'Hoş geldin', _yellow, icon: Icons.phone_iphone),
  FkBadge('daily_7', '7 gün üst üste', _brown, text: '7'),
  FkBadge('daily_30', '30 gün üst üste', _brown, text: '30'),
  FkBadge('birthday', 'İyi ki doğdun', _orange, icon: Icons.cake),
  FkBadge('sharp_shooter', 'Nişancı', _blue, text: '50'),
  FkBadge('loyal', 'Sadık taraftar', _red, icon: Icons.favorite),
  FkBadge('collector', 'Koleksiyoncu', _yellow, icon: Icons.star),
  FkBadge('night_owl', 'Gece kuşu', _darkRed, icon: Icons.nightlight_round),
  FkBadge('early_bird', 'Erkenci', _crimson, icon: Icons.wb_twilight),
  FkBadge('comeback', 'Geri dönüş', _green, icon: Icons.replay),
  FkBadge('no_miss', 'Hatasız tur', _teal, icon: Icons.verified),
  FkBadge('legend', 'Şut ve Gol', _yellow, icon: Icons.emoji_events),
];

const String kMeName = 'Sen';
const String kMeHandle = 'sametocak';

const List<LbEntry> _season = [
  LbEntry('Kerem', 1530, level: 17, badges: 12, likes: 12),
  LbEntry('Deniz Aksoy', 1530, level: 21, badges: 25, likes: 4),
  LbEntry('mert_10', 1500, level: 18, badges: 15, likes: 1),
  LbEntry('Elif Kaya', 1470, level: 16, badges: 20),
  LbEntry('Baran', 1380, level: 14, badges: 13, likes: 1, street: true),
  LbEntry('Zeynep', 1110, level: 4, badges: 4),
  LbEntry('Oyuncu9493', 1110, level: 4, badges: 3),
  LbEntry('Emre B.', 1080, level: 4, badges: 3),
  LbEntry('Can Yılmaz', 1050, level: 4, badges: 3),
  LbEntry('Selin', 1050, level: 4, badges: 2),
  LbEntry('Burak', 1020, level: 3, badges: 2),
  LbEntry('Ece', 990, level: 3, badges: 2),
  LbEntry('Yusuf', 960, level: 3, badges: 2, street: true),
  LbEntry('Melis', 930, level: 3, badges: 1),
  LbEntry('Arda', 900, level: 2, badges: 1),
  LbEntry('Naz', 870, level: 2, badges: 1),
  LbEntry('Kaan', 840, level: 2, badges: 1),
  LbEntry('Derya', 810, level: 2, badges: 1),
  LbEntry('Onur', 780, level: 1, badges: 1),
  LbEntry('İrem', 750, level: 1, badges: 1),
];

const List<LbEntry> _month = [
  LbEntry('Deniz Aksoy', 1200, level: 21, badges: 25, likes: 4),
  LbEntry('Elif Kaya', 1170, level: 16, badges: 20),
  LbEntry('Kerem', 1140, level: 17, badges: 12, likes: 12),
  LbEntry('Baran', 990, level: 14, badges: 13, street: true),
  LbEntry('Selin', 930, level: 4, badges: 2),
  LbEntry('Zeynep', 900, level: 4, badges: 4),
  LbEntry('Arda', 870, level: 2, badges: 1),
  LbEntry('Melis', 810, level: 3, badges: 1),
  LbEntry('Kaan', 780, level: 2, badges: 1),
  LbEntry('Onur', 720, level: 1, badges: 1),
  LbEntry('İrem', 690, level: 1, badges: 1),
  LbEntry('Yusuf', 660, level: 3, badges: 2, street: true),
];

const List<LbEntry> _allTime = [
  LbEntry('Deniz Aksoy', 2310, level: 21, badges: 25, likes: 4),
  LbEntry('Kerem', 2190, level: 17, badges: 12, likes: 12),
  LbEntry('mert_10', 2070, level: 18, badges: 15, likes: 1),
  LbEntry('Elif Kaya', 1980, level: 16, badges: 20),
  LbEntry('Baran', 1860, level: 14, badges: 13, likes: 1, street: true),
  LbEntry('Can Yılmaz', 1650, level: 4, badges: 3),
  LbEntry('Emre B.', 1590, level: 4, badges: 3),
  LbEntry('Zeynep', 1500, level: 4, badges: 4),
  LbEntry('Oyuncu9493', 1470, level: 4, badges: 3),
  LbEntry('Selin', 1410, level: 4, badges: 2),
  LbEntry('Burak', 1380, level: 3, badges: 2),
  LbEntry('Ece', 1320, level: 3, badges: 2),
  LbEntry('Yusuf', 1290, level: 3, badges: 2, street: true),
  LbEntry('Melis', 1230, level: 3, badges: 1),
  LbEntry('Arda', 1200, level: 2, badges: 1),
  LbEntry('Naz', 1170, level: 2, badges: 1),
  LbEntry('Kaan', 1110, level: 2, badges: 1),
  LbEntry('Derya', 1080, level: 2, badges: 1),
  LbEntry('Onur', 1050, level: 1, badges: 1),
  LbEntry('İrem', 990, level: 1, badges: 1),
];

enum LbTab { month, season, allTime }

List<LbEntry> lbEntries(LbTab t) => switch (t) { LbTab.month => _month, LbTab.season => _season, LbTab.allTime => _allTime };

/// Eşit puanlar aynı sırayı paylaşır (1, 1, 3 ...).
int rankAt(List<LbEntry> list, int i) => list.indexWhere((e) => e.pts == list[i].pts) + 1;

/// Oyuncunun listedeki yeri: kendinden yüksek puanlıların sayısı + 1.
int rankFor(List<LbEntry> list, int score) => list.where((e) => e.pts > score).length + 1;
