import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

import '../services/ad_service.dart';

/// Oyun dışı ekranlardaki reklam alanı: alt şerit (uyarlanabilir) ya da
/// 300×250 kutu. Reklam yoksa (test, çevrimdışı, onay yok) yer kaplamaz.
/// Oyun sırasında hiçbir yerde kullanılmaz.
class AdBanner extends StatefulWidget {
  const AdBanner.anchored({super.key, this.maxHeight, this.safeArea = false})
    : box = false;
  const AdBanner.box({super.key})
    : box = true,
      maxHeight = null,
      safeArea = false;

  final bool box;

  /// Alt şerit bu yüksekliğe sığmazsa 320×50'ye düşer; o da sığmazsa hiç
  /// gösterilmez (butonlara yapışık reklam yanlış tıklamaya yol açar).
  final double? maxHeight;

  /// Ekranın altına oturan şerit: alt güvenli alan kadar boşluk bırakır.
  final bool safeArea;

  @override
  State<AdBanner> createState() => _AdBannerState();
}

class _AdBannerState extends State<AdBanner> {
  BannerAd? _ad;
  bool _loaded = false;
  bool _loading = false;
  int? _width;
  Timer? _retry;

  @override
  void initState() {
    super.initState();
    AdService.instance.addListener(_load);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _width = MediaQuery.sizeOf(context).width.truncate();
    _load();
  }

  @override
  void dispose() {
    AdService.instance.removeListener(_load);
    _retry?.cancel();
    _ad?.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final width = _width;
    if (!mounted || !AdService.instance.ready || width == null) return;
    if (_ad != null || _loading) return;
    _loading = true;
    try {
      final AdSize size;
      if (widget.box) {
        size = AdSize.mediumRectangle;
      } else {
        final adaptive = await AdSize.getLargeAnchoredAdaptiveBannerAdSize(
          width,
        );
        if (!mounted) return;
        final room = widget.maxHeight ?? double.infinity;
        if (adaptive != null && adaptive.height <= room) {
          size = adaptive;
        } else if (AdSize.banner.height <= room) {
          size = AdSize.banner;
        } else {
          return;
        }
      }
      final ad = BannerAd(
        adUnitId: AdUnits.banner(adaptive: !widget.box),
        size: size,
        request: const AdRequest(),
        listener: BannerAdListener(
          onAdLoaded: (_) {
            if (mounted) setState(() => _loaded = true);
          },
          onAdFailedToLoad: (ad, _) {
            ad.dispose();
            if (!mounted) return;
            setState(() {
              _ad = null;
              _loaded = false;
            });
            _retry = Timer(const Duration(seconds: 45), _load);
          },
        ),
      );
      _ad = ad;
      await ad.load();
    } catch (_) {
      _ad = null;
    } finally {
      _loading = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final ad = _ad;
    if (ad == null || !_loaded) return const SizedBox.shrink();
    final banner = SizedBox(
      width: ad.size.width.toDouble(),
      height: ad.size.height.toDouble(),
      child: AdWidget(ad: ad),
    );
    if (!widget.safeArea) return banner;
    return SafeArea(top: false, child: Center(heightFactor: 1, child: banner));
  }
}
