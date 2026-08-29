/// Leaderboard için yerel örnek veri (sunucu yok).
class LbEntry {
  const LbEntry(this.name, this.pts, this.avatar, {this.level = 3, this.badges = 2, this.likes = 0});
  final String name;
  final int pts;
  final String avatar;
  final int level;
  final int badges;
  final int likes;
}

const String kMeHandle = 'sametocak';

const List<LbEntry> _season = [
  LbEntry('Tom', 1530, 'avatar_crest.png', level: 7, badges: 9, likes: 12),
  LbEntry('Siebenmorgen', 1530, 'avatar_glove.png', level: 6, badges: 8, likes: 4),
  LbEntry('jeffrey6765', 1500, 'avatar_crest.png', level: 6, badges: 7, likes: 3),
  LbEntry('Timbuchwaldt', 1470, 'avatar_2.png', level: 5, badges: 6),
  LbEntry('DaphneSieb', 1380, 'avatar_mascot.png', level: 5, badges: 5),
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
  LbEntry('Timbuchwaldt', 1470, 'avatar_2.png', level: 5, badges: 6),
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
