import 'package:flutter_test/flutter_test.dart';
import 'package:sut_ve_gol/services/ad_policy.dart';

void main() {
  late DateTime now;
  AdPolicy policy() => AdPolicy(now: () => now);

  setUp(() => now = DateTime(2026, 10, 19, 12));

  test(
    'yeni oyuncu ilk koşularda geçiş reklamı görmez, sonra her 3 koşuda bir',
    () {
      final p = policy();
      p.runFinished();
      p.runFinished();
      expect(p.soloInterstitialDue, isFalse);
      p.runFinished();
      expect(p.soloInterstitialDue, isTrue);
      p.fullscreenShown(interstitial: true);
      expect(p.soloInterstitialDue, isFalse);

      now = now.add(const Duration(minutes: 5));
      p.runFinished();
      p.runFinished();
      expect(p.soloInterstitialDue, isFalse);
      p.runFinished();
      expect(p.soloInterstitialDue, isTrue);
    },
  );

  test('iki tam ekran reklam arasında en az 90 sn (ödüllü dahil)', () {
    final p = policy()..totalRuns = 10;
    p.runsSinceInterstitial = 5;
    p.fullscreenShown(interstitial: false);
    expect(p.soloInterstitialDue, isFalse);
    expect(p.runsSinceInterstitial, 5, reason: 'ödüllü sırayı sıfırlamaz');
    now = now.add(const Duration(seconds: 89));
    expect(p.soloInterstitialDue, isFalse);
    now = now.add(const Duration(seconds: 1));
    expect(p.soloInterstitialDue, isTrue);
  });

  test('düello: her 2 maçta bir, aynı aralık kuralıyla', () {
    final p = policy();
    p.duelFinished();
    expect(p.duelInterstitialDue, isFalse);
    p.duelFinished();
    expect(p.duelInterstitialDue, isTrue);
    p.fullscreenShown(interstitial: true);
    p.duelFinished();
    p.duelFinished();
    expect(p.duelInterstitialDue, isFalse, reason: '90 sn dolmadı');
    now = now.add(AdPolicy.minGap);
    expect(p.duelInterstitialDue, isTrue);
  });

  test(
    '"1 hak daha" koşu başına bir kez ve en az bir golle; Kral Modu teklifi 2 koşudan sonra',
    () {
      final p = policy();
      expect(p.canOfferContinue(score: 0, usedThisRun: false), isFalse);
      expect(p.canOfferContinue(score: 30, usedThisRun: false), isTrue);
      expect(p.canOfferContinue(score: 30, usedThisRun: true), isFalse);
      expect(p.canOfferFeverStart, isFalse);
      p.runFinished();
      p.runFinished();
      expect(p.canOfferFeverStart, isTrue);
    },
  );
}
