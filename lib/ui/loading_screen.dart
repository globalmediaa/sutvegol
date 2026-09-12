import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// Lacivert "Yükleniyor" ekranı (çıkış → oyunun baştan kurulması).
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: FK.navy,
    body: Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const LogoWidget(width: 220, subtitle: false),
          const SizedBox(height: 28),
          const SizedBox(
            width: 26,
            height: 26,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: FK.orange,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Yükleniyor',
            style: FK.t(
              size: 15,
              w: FontWeight.w600,
              color: FK.muted,
              spacing: 1,
            ),
          ),
        ],
      ),
    ),
  );
}
