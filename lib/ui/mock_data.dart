import 'package:flutter/material.dart' show IconData, Icons;

/// Leaderboard için yerel örnek veri (sunucu yok).
class LbEntry {
  const LbEntry(this.name, this.pts, this.avatar, {this.level = 3, this.badges = 2, this.likes = 0, this.chalk = false});
  final String name;
  final int pts;
  final String avatar;
  final int level;
  final int badges;
  final int likes;

  /// Profil kartı arka planı: yeşil saha (false) / karatahta taktik tahtası (true).
  final bool chalk;

  /// Kazanılmış rozetler (sırayla ilk N; "You" için Welcome + Profile picture).
  List<KlBadge> get earnedBadges => name == 'You'
      ? [kBadges.firstWhere((b) => b.id == 'welcome'), kBadges.firstWhere((b) => b.id == 'profile_picture')]
      : kBadges.take(badges.clamp(0, kBadges.length)).toList();
}

/// Rozet tanımı: dolu renkli oval (icon ya da sayı) veya açık mavi çerçeveli (outline).
class KlBadge {
  const KlBadge(this.id, this.label, this.color, {this.icon, this.text, this.outline = false});
  final String id;
  final String label;
  final int color;
  final IconData? icon;
  final String? text;
  final bool outline;
}

const int _orange = 0xFFF59E0B;
const int _yellow = 0xFFF5B400;
const int _red = 0xFFD7263D;
const int _teal = 0xFF1AA79C;
const int _green = 0xFF2E9E4F;
const int _brown = 0xFF7A4A21;
const int _blue = 0xFF2563EB;
const int _lightBlue = 0xFF7FB8F0;
const int _purple = 0xFF8B3FD9;
const int _crimson = 0xFFB4173A;
const int _darkRed = 0xFF7F1D1D;

/// Videodaki 37 rozet (görülen 28 + aynı ailelerden 9 tamamlayıcı).
const List<KlBadge> kBadges = [
  KlBadge('profile_picture', 'Profile picture', _orange, icon: Icons.account_circle),
  KlBadge('complete_profile', 'Complete profile', _yellow, icon: Icons.list_alt),
  KlBadge('live_match', 'Live match', _red, icon: Icons.stadium),
  KlBadge('amateur_scout', 'Amateur Scout', _teal, text: '1'),
  KlBadge('scout_training', 'Scout in training', _green, text: '5'),
  KlBadge('pro_scout', 'Professional scout', _teal, text: '11'),
  KlBadge('heavy_reader', 'Heavy reader', _brown, text: '100'),
  KlBadge('moving_pictures', 'Moving pictures', _green, text: '5'),
  KlBadge('long_viewer', 'Long time viewer', _green, text: '10'),
  KlBadge('bingewatcher', 'Bingewatcher', _green, text: '25'),
  KlBadge('at_home', 'Make yourself at home', _orange, text: '1'),
  KlBadge('diehard', 'Diehard', 0xFFE8571C, text: '24'),
  KlBadge('glued', 'Glued to the screen', _orange, text: '10'),
  KlBadge('kl_season_1', '#1 Kick Legend season', _blue, text: '1'),
  KlBadge('kl_season_3', 'Top 3 Kick Legend season', _blue, text: '3'),
  KlBadge('kl_month_1', '#1 Kick Legend month', _lightBlue, text: '1', outline: true),
  KlBadge('kl_month_3', 'Top 3 Kick Legend month', _lightBlue, text: '3', outline: true),
  KlBadge('top10', 'Top 10', _purple, text: '10'),
  KlBadge('ticket1', '1 Ticket', _crimson, icon: Icons.confirmation_number),
  KlBadge('season_ticket', 'Season ticket', _darkRed, icon: Icons.confirmation_number),
  KlBadge('tickets5', '5 Tickets', _crimson, text: '5'),
  KlBadge('pts1000', '1000 points Kick Legend', _blue, text: '1K'),
  KlBadge('pts1500', '1500 points Kick Legend', _blue, text: '1,5K'),
  KlBadge('pts2000', '2000 points Kick Legend', _blue, text: '2K'),
  KlBadge('newsreader', 'Newsreader', _brown, text: '15'),
  KlBadge('welcome', 'Welcome', _yellow, icon: Icons.phone_iphone),
  KlBadge('up_to_date', 'Up to date', _brown, text: '50'),
  KlBadge('birthday', 'Happy birthday', _orange, icon: Icons.cake),
  KlBadge('first_goal', 'First goal', _green, icon: Icons.sports_soccer),
  KlBadge('hat_trick', 'Hat-trick', _green, text: '3'),
  KlBadge('fever_master', 'Fever master', _orange, icon: Icons.local_fire_department),
  KlBadge('sharp_shooter', 'Sharp shooter', _blue, text: '50'),
  KlBadge('loyal_fan', 'Loyal fan', _red, icon: Icons.favorite),
  KlBadge('quiz_master', 'Quiz master', _purple, icon: Icons.quiz),
  KlBadge('collector', 'Collector', _yellow, icon: Icons.star),
  KlBadge('night_owl', 'Night owl', _darkRed, icon: Icons.nightlight_round),
  KlBadge('legend', 'Kick Legend', _blue, icon: Icons.emoji_events),
];

const String kMeHandle = 'sametocak';

const List<LbEntry> _season = [
  LbEntry('Tom', 1530, 'avatar_crest.png', level: 17, badges: 12, likes: 12),
  LbEntry('Siebenmorgen', 1530, 'avatar_glove.png', level: 21, badges: 25, likes: 4),
  LbEntry('jeffrey6765', 1500, 'avatar_crest.png', level: 18, badges: 15, likes: 1),
  LbEntry('Timbuchwaldt', 1470, 'avatar_2.png', level: 16, badges: 20),
  LbEntry('DaphneSieb', 1380, 'avatar_mascot.png', level: 14, badges: 13, likes: 1, chalk: true),
  LbEntry('Esther', 1110, 'avatar_mascot.png', level: 4, badges: 4),
  LbEntry('User9493', 1110, 'avatar_mascot.png', level: 4, badges: 3),
  LbEntry('EdwinB', 1080, 'avatar_mascot.png', level: 4, badges: 3),
  LbEntry('Maurits', 1050, 'avatar_mascot.png', level: 4, badges: 3),
  LbEntry('Dompel', 1050, 'avatar_crest.png', level: 4, badges: 2),
  LbEntry('Patrick', 1020, 'avatar_crest.png', level: 3, badges: 2),
  LbEntry('frans', 990, 'avatar_2.png', level: 3, badges: 2),
  LbEntry('Shahiryar', 960, 'avatar_2.png', level: 3, badges: 2),
  LbEntry('RoyDL', 900, 'avatar_crest.png', level: 3, badges: 2),
  LbEntry('Emile', 900, 'avatar_mascot.png', level: 3, badges: 2),
  LbEntry('AllyDeAap', 870, 'avatar_mascot.png', level: 3, badges: 2),
  LbEntry('VvanRiet', 840, 'avatar_crest.png', level: 3, badges: 1),
  LbEntry('Thootje036', 840, 'avatar_crest.png', level: 3, badges: 1),
  LbEntry('Milan', 810, 'avatar_mascot.png', level: 2, badges: 1),
  LbEntry('RonG', 780, 'avatar_mascot.png', level: 2, badges: 1),
  LbEntry('ThomasTroost', 750, 'avatar_mascot.png', level: 2, badges: 1),
  LbEntry('AllyDeKnaap', 750, 'avatar_crest.png', level: 2, badges: 1),
  LbEntry('ua2005', 750, 'avatar_mascot.png', level: 2, badges: 1),
  LbEntry('Sjoerd', 750, 'avatar_crest.png', level: 2, badges: 1),
  LbEntry('Astrid85', 750, 'avatar_crest.png', level: 2, badges: 1),
  LbEntry('Vincent', 720, 'avatar_mascot.png', level: 2, badges: 1),
  LbEntry('MichaelT', 720, 'avatar_mascot.png', level: 2, badges: 1),
  LbEntry('User6793', 690, 'avatar_crest.png', level: 2, badges: 1),
  LbEntry('Sepp', 660, 'avatar_2.png', level: 2, badges: 1),
];

const List<LbEntry> _allTime = [
  LbEntry('jeffrey6765', 2400, 'avatar_crest.png', level: 9, badges: 12, likes: 20),
  LbEntry('DylanBarendse', 2070, 'avatar_mascot.png', level: 8, badges: 10, likes: 8),
  LbEntry('Tom', 1950, 'avatar_crest.png', level: 7, badges: 9, likes: 12),
  LbEntry('KH036', 1950, 'avatar_2.png', level: 7, badges: 8),
  LbEntry('DaphneSieb', 1950, 'avatar_mascot.png', level: 7, badges: 8),
  LbEntry('Siebenmorgen', 1710, 'avatar_glove.png', level: 6, badges: 8),
  LbEntry('FemkeZuurbier', 1620, 'avatar_2.png', level: 6, badges: 6),
  LbEntry('Chantal', 1590, 'avatar_2.png', level: 5, badges: 5),
  LbEntry('Justin', 1590, 'avatar_mascot.png', level: 5, badges: 5),
  LbEntry('Martin', 1530, 'avatar_2.png', level: 5, badges: 5),
  LbEntry('Marnix', 1500, 'avatar_2.png', level: 5, badges: 4),
  LbEntry('Timbuchwaldt', 1470, 'avatar_2.png', level: 16, badges: 20),
  LbEntry('Esther', 1110, 'avatar_mascot.png', level: 4, badges: 4),
  LbEntry('User9493', 1110, 'avatar_mascot.png', level: 4, badges: 3),
  LbEntry('EdwinB', 1080, 'avatar_mascot.png', level: 4, badges: 3),
  LbEntry('Maurits', 1050, 'avatar_mascot.png', level: 4, badges: 3),
  LbEntry('Dompel', 1050, 'avatar_crest.png', level: 4, badges: 2),
  LbEntry('Patrick', 1020, 'avatar_crest.png', level: 3, badges: 2),
  LbEntry('frans', 990, 'avatar_2.png', level: 3, badges: 2),
  LbEntry('Sepp', 660, 'avatar_2.png', level: 2, badges: 1),
];

const List<LbEntry> _month = [
  LbEntry('jeffrey6765', 1500, 'avatar_crest.png', level: 9, badges: 12, likes: 20),
  LbEntry('DaphneSieb', 1380, 'avatar_mascot.png', level: 7, badges: 8),
  LbEntry('Esther', 1110, 'avatar_mascot.png', level: 4, badges: 4),
  LbEntry('User9493', 1110, 'avatar_mascot.png', level: 4, badges: 3),
  LbEntry('Maurits', 1050, 'avatar_mascot.png', level: 4, badges: 3),
  LbEntry('Dompel', 1050, 'avatar_crest.png', level: 4, badges: 2),
  LbEntry('Patrick', 1020, 'avatar_crest.png', level: 3, badges: 2),
  LbEntry('frans', 990, 'avatar_2.png', level: 3, badges: 2),
  LbEntry('Shahiryar', 960, 'avatar_2.png', level: 3, badges: 2),
  LbEntry('RoyDL', 900, 'avatar_crest.png', level: 3, badges: 2),
  LbEntry('Emile', 900, 'avatar_mascot.png', level: 3, badges: 2),
  LbEntry('Milan', 810, 'avatar_mascot.png', level: 2, badges: 1),
  LbEntry('Sjoerd', 750, 'avatar_crest.png', level: 2, badges: 1),
  LbEntry('Vincent', 720, 'avatar_mascot.png', level: 2, badges: 1),
  LbEntry('Sepp', 660, 'avatar_2.png', level: 2, badges: 1),
];

enum LbTab { month, season, allTime }

List<LbEntry> lbEntries(LbTab tab) => switch (tab) {
      LbTab.month => _month,
      LbTab.season => _season,
      LbTab.allTime => _allTime,
    };

/// Kendi skorumun sıralaması (eşit puanlar aynı sırayı paylaşır).
int rankFor(List<LbEntry> list, int pts) => list.where((e) => e.pts > pts).length + 1;

/// Tablodaki sıra numarası (aynı puana aynı sıra).
int rankAt(List<LbEntry> list, int index) => list.where((e) => e.pts > list[index].pts).length + 1;
