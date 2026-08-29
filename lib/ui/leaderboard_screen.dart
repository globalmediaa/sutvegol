import 'package:flutter/material.dart';

import 'mock_data.dart';
import 'profile_dialog.dart';
import 'theme.dart';

/// LEADERBOARD ekranı: kırmızı başlık, sekmeler, mavi gövde, podyum ve liste.
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
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    final list = lbEntries(_tab);
    final myRank = rankFor(list, widget.myScore);
    return Scaffold(
      backgroundColor: KL.bodyBottom,
      body: Column(
        children: [
          _header(context),
          _tabs(),
          Expanded(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [KL.bodyTop, KL.bodyBottom]),
              ),
              child: ListView(
                padding: const EdgeInsets.only(bottom: 30),
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    child: Image.asset('assets/images/logo.png', width: 240, height: 115, fit: BoxFit.contain),
                  ),
                  _row(context, rank: myRank, avatar: 'avatar_you.png', name: 'You', handle: '($kMeHandle)', pts: widget.myScore, highlight: true, entry: const LbEntry('You', 0, 'avatar_you.png')),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 40),
                      child: _Loading(),
                    )
                  else ...[
                    _Podium(list: list, onTap: (e) => showProfileDialog(context, e)),
                    for (var i = 3; i < list.length; i++)
                      _row(context, rank: rankAt(list, i), avatar: list[i].avatar, name: list[i].name, pts: list[i].pts, entry: list[i]),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _header(BuildContext context) => Container(
        color: KL.red,
        padding: EdgeInsets.only(top: MediaQuery.paddingOf(context).top),
        height: MediaQuery.paddingOf(context).top + 64,
        child: Stack(
          children: [
            Positioned(
              left: 14,
              top: 0,
              bottom: 0,
              child: IconButton(
                onPressed: () => Navigator.of(context).pop(),
                icon: const Icon(Icons.arrow_back_ios_new, color: Colors.white, size: 22),
              ),
            ),
            Center(child: Text('LEADERBOARD', style: KL.t(size: 22, w: FontWeight.w700, spacing: 0.5))),
          ],
        ),
      );

  Widget _tabs() => Container(
        color: KL.tabBlack,
        height: 40,
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
                  child: Container(
                    margin: const EdgeInsets.symmetric(vertical: 2),
                    decoration: BoxDecoration(
                      color: _tab == t ? KL.red : Colors.transparent,
                      borderRadius: t == LbTab.allTime
                          ? const BorderRadius.horizontal(left: Radius.circular(10))
                          : const BorderRadius.horizontal(right: Radius.circular(10)),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      switch (t) { LbTab.month => 'This month', LbTab.season => 'Season', LbTab.allTime => 'All time' },
                      style: KL.t(size: 17, w: _tab == t ? FontWeight.w700 : FontWeight.w600, color: _tab == t ? Colors.white : const Color(0xFFBDBDBD)),
                    ),
                  ),
                ),
              ),
          ],
        ),
      );

  Widget _row(BuildContext context, {required int rank, required String avatar, required String name, String? handle, required int pts, bool highlight = false, required LbEntry entry}) {
    return GestureDetector(
      onTap: highlight ? null : () => showProfileDialog(context, entry),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 10, vertical: 9),
        height: 77,
        decoration: BoxDecoration(
          color: highlight ? KL.youRow.withValues(alpha: 0.42) : Colors.white.withValues(alpha: 0.22),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            SizedBox(width: 62, child: Center(child: Text('$rank', style: KL.t(size: 20, w: FontWeight.w700)))),
            _Avatar(avatar, size: 55),
            const SizedBox(width: 12),
            Expanded(
              child: Text.rich(
                TextSpan(children: [
                  TextSpan(text: name, style: KL.t(size: 20, w: FontWeight.w600)),
                  if (handle != null) TextSpan(text: ' $handle', style: KL.t(size: 20, color: const Color(0xFFCFE3F5))),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 8),
            Text('$pts', style: KL.t(size: 20, w: FontWeight.w700)),
            Text(' PTS', style: KL.t(size: 18)),
            const SizedBox(width: 16),
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
          const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xCCFFFFFF))),
          const SizedBox(height: 10),
          Text('Loading', style: KL.t(size: 15, color: const Color(0xCCFFFFFF))),
        ],
      );
}

class _Avatar extends StatelessWidget {
  const _Avatar(this.asset, {required this.size, this.ring});
  final String asset;
  final double size;
  final Color? ring;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ring ?? Colors.white, width: ring != null ? 4 : 2.5),
          image: DecorationImage(image: AssetImage('assets/images/$asset'), fit: BoxFit.cover),
        ),
      );
}

/// İlk üç: #2 sol, #1 orta (yukarıda), #3 sağ; braket çizgileri arkada.
class _Podium extends StatelessWidget {
  const _Podium({required this.list, required this.onTap});
  final List<LbEntry> list;
  final void Function(LbEntry) onTap;

  @override
  Widget build(BuildContext context) {
    if (list.length < 3) return const SizedBox.shrink();
    return SizedBox(
      height: 250,
      child: Stack(
        children: [
          Positioned.fill(child: CustomPaint(painter: _BracketPainter())),
          _slot(context, list[1], 2, left: 24, top: 60, badge: const Color(0xFFBDBDBD)),
          _slot(context, list[0], 1, left: 172, top: 8, badge: const Color(0xFFD9A31C), ring: const Color(0xFFD9A31C)),
          _slot(context, list[2], 3, left: 320, top: 60, badge: const Color(0xFFBDBDBD)),
        ],
      ),
    );
  }

  Widget _slot(BuildContext context, LbEntry e, int rank, {required double left, required double top, required Color badge, Color? ring}) {
    return Positioned(
      left: left,
      top: top,
      width: 96,
      child: GestureDetector(
        onTap: () => onTap(e),
        child: Column(
          children: [
            Text(e.name.length > 10 ? '${e.name.substring(0, 8)}...' : e.name, style: KL.t(size: 17), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 8),
            _Avatar(e.avatar, size: 76, ring: ring),
            Transform.translate(
              offset: const Offset(0, -12),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 1),
                decoration: BoxDecoration(color: badge, borderRadius: BorderRadius.circular(10)),
                child: Text('#$rank', style: KL.t(size: 13, w: FontWeight.w700, color: rank == 1 ? Colors.white : const Color(0xFF333333))),
              ),
            ),
            Text('${e.pts}', style: KL.t(size: 20, w: FontWeight.w700)),
            Text('PTS', style: KL.t(size: 16)),
          ],
        ),
      ),
    );
  }
}

class _BracketPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = const Color(0x88DDE7F0)
      ..strokeWidth = 2
      ..style = PaintingStyle.stroke;
    final cx = size.width / 2;
    // Ortadan sağa/sola kollar, uçlar aşağı.
    final path = Path()
      ..moveTo(cx - 16, 100)
      ..lineTo(cx - 60, 100)
      ..lineTo(cx - 60, 128)
      ..lineTo(cx - 135, 128)
      ..lineTo(cx - 135, 170)
      ..moveTo(cx + 16, 100)
      ..lineTo(cx + 60, 100)
      ..lineTo(cx + 60, 128)
      ..lineTo(cx + 135, 128)
      ..lineTo(cx + 135, 170);
    canvas.drawPath(path, p);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
