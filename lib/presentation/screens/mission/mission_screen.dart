import 'package:flutter/material.dart';
import 'math_mission_screen.dart';
import 'color_mission_screen.dart';
import 'shake_mission_screen.dart';
// import 'step_mission_screen.dart';
import 'barcode_mission_screen.dart';

class MissionScreen extends StatelessWidget {
  final String missionType;
  final String difficulty;

  const MissionScreen({
    super.key,
    required this.missionType,
    required this.difficulty,
  });

  @override
  Widget build(BuildContext context) {
    // Rota yönlendiricisi (Router) olarak çalışır.
    // Her bir görev karmaşık mantıklara sahip olduğundan ayrı sayfalarda ele alınmalıdır.
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        // Geri tuşuyla çıkış engellendi. Görev tamamlanmalı.
      },
      child: _buildMissionContent(),
    );
  }

  Widget _buildMissionContent() {
    switch (missionType) {
      case 'MATEMATİK SINAVI':
        return MathMissionScreen(difficulty: difficulty);
      case 'RENK TUZAĞI':
        return ColorMissionScreen(difficulty: difficulty);
      case 'TELEFONU SALLA':
        return ShakeMissionScreen(difficulty: difficulty);
      case 'BARKOD OKUT':
        return BarcodeMissionScreen(difficulty: difficulty);
      default:
        return MathMissionScreen(difficulty: difficulty);
    }
  }
}
