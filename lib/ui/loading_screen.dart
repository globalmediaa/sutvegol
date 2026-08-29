import 'package:flutter/material.dart';

import 'theme.dart';

/// Kırmızı "Loading" ekranı (çıkış → ana uygulamaya dönüş hissi).
class LoadingScreen extends StatelessWidget {
  const LoadingScreen({super.key});

  @override
  Widget build(BuildContext context) => Scaffold(
        backgroundColor: KL.red,
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white)),
              const SizedBox(height: 12),
              Text('Loading', style: KL.t(size: 15, w: FontWeight.w600)),
            ],
          ),
        ),
      );
}
