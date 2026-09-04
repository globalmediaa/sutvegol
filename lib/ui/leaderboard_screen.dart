import 'package:flutter/material.dart';

import 'mock_data.dart';
import 'profile_dialog.dart';
import 'theme.dart';
import 'widgets.dart';

/// SIRALAMA ekranı: lacivert zemin, üstte logo + sekmeler, sabit "Sen" satırı,
/// podyum (cam kaideler) ve kayan liste.
class LeaderboardScreen extends StatefulWidget {
  const LeaderboardScreen({super.key, required this.myScore});
  final int myScore;

  @override
  State<LeaderboardScreen> createState() => _LeaderboardScreenState();
}

class _LeaderboardScreenState extends State<LeaderboardScreen> {
  LbTab _tab = LbTab.season;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    await Future<void>.delayed(const Duration(milliseconds: 600));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = lbEntries(_tab);
    final myRank = rankFor(list, widget.myScore);
    final top = MediaQuery.paddingOf(context).top;
    return Scaffold(
      backgroundColor: FK.navy,
      body: Stack(
        children: [
          // Üstte sıcak parıltı.
          Positioned(
            top: -220,
            left: -100,
            right: -100,
            child: IgnorePointer(
              child: Container(
                height: 520,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [FK.orange.withValues(alpha: 0.35), FK.orange.withValues(alpha: 0)]),
                ),
              ),
            ),
          ),
          Column(
            children: [
              SizedBox(height: top + 8),
              _header(context),
              const SizedBox(height: 4),
              const LogoWidget(width: 210, subtitle: false),
              const SizedBox(height: 10),
              _tabs(),
              const SizedBox(height: 10),
              _row(context, rank: myRank, name: kMeName, handle: kMeHandle, pts: widget.myScore, highlight: true, entry: const LbEntry(kMeName, 0)),
              Expanded(
                child: AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  child: _loading
                      ? const Padding(key: ValueKey('loading'), padding: EdgeInsets.only(top: 60), child: _Loading())
                      : ListView(
                          key: ValueKey(_tab),
                          padding: const EdgeInsets.only(bottom: 30),
                          children: [
                            _Podium(list: list, onTap: (e) => showProfileDialog(context, e)),
                            for (var i = 3; i < list.length; i++) _row(context, rank: rankAt(list, i), name: list[i].name, pts: list[i].pts, entry: list[i]),
                          ],
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Row(
          children: [
            RoundButton(icon: Icons.arrow_back_ios_new_rounded, size: 44, onTap: () => Navigator.of(context).pop()),
            Expanded(child: Center(child: Text('SIRALAMA', style: FK.t(size: 20, w: FontWeight.w700, spacing: 3)))),
            const SizedBox(width: 44),
          ],
        ),
      );

  Widget _tabs() => Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        height: 44,
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(color: FK.glass, borderRadius: BorderRadius.circular(22), border: Border.all(color: FK.glassBorder)),
        child: Row(
          children: [
            for (final t in LbTab.values)
              Expanded(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    if (_tab == t) return;
                    setState(() => _tab = t);
                    _load();
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    decoration: BoxDecoration(
                      gradient: _tab == t ? FK.fire : null,
                      borderRadius: BorderRadius.circular(18),
                      boxShadow: _tab == t ? FK.glow(12, alpha: 0.35, dy: 3) : null,
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      switch (t) { LbTab.month => 'Bu ay', LbTab.season => 'Sezon', LbTab.allTime => 'Tüm zamanlar' },
                      style: FK.t(size: 14.5, w: FontWeight.w700, color: _tab == t ? Colors.white : FK.muted),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _row(BuildContext context, {required int rank, required String name, String? handle, required int pts, bool highlight = false, required LbEntry entry}) {
    return GestureDetector(
      onTap: highlight ? null : () => showProfileDialog(context, entry),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        height: 64,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          gradient: highlight ? LinearGradient(colors: [FK.orange.withValues(alpha: 0.28), FK.amber.withValues(alpha: 0.12)]) : null,
          color: highlight ? null : FK.glass,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: highlight ? FK.orange.withValues(alpha: 0.7) : FK.glassBorder),
        ),
        child: Row(
          children: [
            SizedBox(width: 36, child: Center(child: Text('$rank', style: FK.t(size: 17, w: FontWeight.w700, color: highlight ? FK.amber : FK.muted)))),
            AvatarCircle(highlight ? kMeHandle : name, size: 44, ring: highlight ? FK.orange : null),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name, maxLines: 1, overflow: TextOverflow.ellipsis, style: FK.t(size: 16, w: FontWeight.w700)),
                  if (handle != null) Text('@$handle', style: FK.t(size: 12, color: FK.muted)),
                  if (handle == null) Text('Seviye ${entry.level}', style: FK.t(size: 12, color: FK.muted)),
                ],
              ),
            ),
            const SizedBox(width: 8),
            Text('$pts', style: FK.t(size: 18, w: FontWeight.w700, color: highlight ? FK.amber : Colors.white)),
            const SizedBox(width: 4),
            Text('PUAN', style: FK.t(size: 11, w: FontWeight.w600, color: FK.muted, spacing: 1)),
            const SizedBox(width: 6),
          ],
        ),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();
  @override
  Widget build(BuildContext context) => Column(
        children: [
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: FK.orange)),
          const SizedBox(height: 10),
          Text('Yükleniyor', style: FK.t(size: 14, color: FK.muted)),
        ],
      );
}

/// İlk üç: cam kaideler (2-1-3), gradyan halkalı avatarlar, madalya rozetleri.
class _Podium extends StatelessWidget {
  const _Podium({required this.list, required this.onTap});
  final List<LbEntry> list;
  final void Function(LbEntry) onTap;

  @override
  Widget build(BuildContext context) {
    if (list.length < 3) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
      child: SizedBox(
        height: 300,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(child: _slot(list[1], 2, 104, FK.silver)),
            const SizedBox(width: 8),
            Expanded(child: _slot(list[0], 1, 134, FK.gold)),
            const SizedBox(width: 8),
            Expanded(child: _slot(list[2], 3, 80, FK.bronze)),
          ],
        ),
      ),
    );
  }

  Widget _slot(LbEntry e, int rank, double pedestal, Color medal) {
    final size = rank == 1 ? 76.0 : 62.0;
    return GestureDetector(
      onTap: () => onTap(e),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (rank == 1) Icon(Icons.emoji_events_rounded, color: FK.gold, size: 26),
          Stack(
            clipBehavior: Clip.none,
            alignment: Alignment.bottomCenter,
            children: [
              Container(
                decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: FK.glow(18, color: medal, alpha: 0.5, dy: 4)),
                child: AvatarCircle(e.name, size: size, ring: medal, ringWidth: 3.5),
              ),
              Positioned(bottom: -10, child: Chip2('#$rank', color: medal, fontSize: 11)),
            ],
          ),
          const SizedBox(height: 16),
          Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: FK.t(size: 14, w: FontWeight.w700)),
          const SizedBox(height: 6),
          Container(
            height: pedestal,
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [medal.withValues(alpha: 0.35), FK.glass]),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
              border: Border.all(color: medal.withValues(alpha: 0.45)),
            ),
            padding: const EdgeInsets.only(top: 10),
            child: Column(
              children: [
                Text('${e.pts}', style: FK.t(size: 20, w: FontWeight.w700)),
                Text('PUAN', style: FK.t(size: 10, w: FontWeight.w600, color: FK.muted, spacing: 1)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
