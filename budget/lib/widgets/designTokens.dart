// Локальная версия: цвета нового дизайна (макет «Новый дизайн Cashew»).
// Фон, карточки и текст берутся из темы приложения, здесь только акценты.

import 'package:budget/struct/envelopePlan.dart';
import 'package:flutter/material.dart';

class AppTokens {
  static const Color accent = Color(0xFF1F7A5A);
  static const Color accentDark = Color(0xFF14573F);
  static const Color accentSoft = Color(0xFFE3F1EB);
  static const Color danger = Color(0xFFB3372D);
  static const Color warn = Color(0xFFC98A1B);
  static const Color muted = Color(0xFF7A8580);

  /// Высокий приоритет — красный, средний — жёлтый, низкий — серый.
  static Color priorityColor(EnvelopePriority priority) {
    switch (priority) {
      case EnvelopePriority.high:
        return danger;
      case EnvelopePriority.medium:
        return warn;
      case EnvelopePriority.low:
        return muted;
    }
  }
}
