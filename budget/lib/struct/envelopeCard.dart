// Локальная версия: чистая логика карточки подгруппы на странице счёта
// (без базы и экрана, чтобы её проверяли тесты).
//
// Карточка показывает: полоску прогресса, короткое состояние («хватает»,
// «ещё 2 000 ₽», «цель 3 000 ₽») и долю с ближайших поступлений (ЗП, аванс).

import 'dart:math';
import 'package:budget/struct/envelopePlan.dart';

enum EnvelopeCardState {
  /// Лежащего хватает на всё, что нужно в этом месяце (или цель достигнута).
  enough,

  /// Не хватает до потребности месяца.
  short,

  /// Копим на цель (без платежей в этом месяце).
  saving,

  /// Ничего не нужно и цели нет.
  none,
}

class EnvelopeCardInfo {
  const EnvelopeCardInfo({
    required this.progress,
    required this.state,
    required this.amount,
    required this.required,
  });

  /// Доля 0..1 для полоски.
  final double progress;
  final EnvelopeCardState state;

  /// short — сколько ещё нужно; saving — сумма цели; иначе 0.
  final double amount;

  /// Сколько должно лежать к концу месяца (платежи + копилка + цель).
  final double required;
}

double _clamp01(double value) => max(0.0, min(1.0, value));

/// [targetAmount] — сумма цели подгруппы, если она задана.
EnvelopeCardInfo envelopeCardInfo(PlanLine line, {double? targetAmount}) {
  double required = line.scheduled + line.longRequired + line.goalRequired;
  double balance = max(0.0, line.balance);
  if (required > 0) {
    double progress = _clamp01(balance / required);
    if (line.need > 0.005) {
      return EnvelopeCardInfo(
        progress: progress,
        state: EnvelopeCardState.short,
        amount: line.need,
        required: required,
      );
    }
    return EnvelopeCardInfo(
      progress: 1,
      state: EnvelopeCardState.enough,
      amount: 0,
      required: required,
    );
  }
  double target = (targetAmount ?? 0) > 0
      ? targetAmount!
      : (line.wish > 0 ? balance + line.wish : 0);
  if (target > 0) {
    if (balance + 0.005 >= target) {
      return EnvelopeCardInfo(
        progress: 1,
        state: EnvelopeCardState.enough,
        amount: 0,
        required: 0,
      );
    }
    return EnvelopeCardInfo(
      progress: _clamp01(balance / target),
      state: EnvelopeCardState.saving,
      amount: target,
      required: 0,
    );
  }
  return const EnvelopeCardInfo(
    progress: 0,
    state: EnvelopeCardState.none,
    amount: 0,
    required: 0,
  );
}

/// Уровень приоритета для значка из трёх столбиков: 3 высокий, 1 низкий.
int priorityLevel(EnvelopePriority priority) {
  switch (priority) {
    case EnvelopePriority.high:
      return 3;
    case EnvelopePriority.medium:
      return 2;
    case EnvelopePriority.low:
      return 1;
  }
}

enum PayKind { salary, advance, now }

class PayShare {
  const PayShare(this.kind, this.date, this.amount);
  final PayKind kind;
  final DateTime date;
  final double amount;
}

/// Сколько с какого ближайшего поступления нужно добавить.
/// До 12-го: ЗП 2/3 и аванс 1/3. С 13-го до 25-го: аванс — всё. После 25-го:
/// «сейчас» (обе даты уже прошли).
List<PayShare> payShares(double need, DateTime now) {
  if (need <= 0.005) return [];
  DateTime day(int d) => DateTime(now.year, now.month, d);
  if (now.day > 25) {
    return [PayShare(PayKind.now, DateTime(now.year, now.month, now.day), need)];
  }
  (double, double) split = splitNeed(need, now);
  if (split.$1 > 0) {
    return [
      PayShare(PayKind.salary, day(12), split.$1),
      PayShare(PayKind.advance, day(25), split.$2),
    ];
  }
  return [PayShare(PayKind.advance, day(25), split.$2)];
}
