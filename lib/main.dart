import 'package:flutter/material.dart';

import 'features/calculator/calculator_page.dart';
import 'theme/app_colors.dart';

export 'features/pace/pace_view.dart'
    show debugPaceStateLoaderOverride, debugTrackFileStoreOverride;

void main() {
  runApp(const CalculatorApp());
}

class CalculatorApp extends StatelessWidget {
  const CalculatorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'uRunCalc',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: AppColors.background,
        colorScheme: ColorScheme.fromSeed(
          seedColor: AppColors.accent,
          brightness: Brightness.dark,
        ),
      ),
      home: const CalculatorPage(),
    );
  }
}
