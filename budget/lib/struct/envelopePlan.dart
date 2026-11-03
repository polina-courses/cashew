// Локальная версия: логика подгрупп счёта — потребность по календарю, приоритеты,
// «Свободные». Чистая логика без базы и экрана, чтобы её проверяли тесты.
//
// Потребность подгруппы на месяц = платежи, которые ещё предстоят в этом месяце
// (по календарю), + ежемесячный взнос на цель (если есть) − что уже лежит.
// Поступление раскладывается по приоритету. Нехватку при оплате закрывают
// «Свободные»; если и их нет — платёж не проводится.

import 'dart:math';

enum EnvelopePriority { high, medium, low }

EnvelopePriority envelopePriorityFromString(String? value) {
  for (EnvelopePriority p in EnvelopePriority.values) {
    if (p.name == value) return p;
  }
  return EnvelopePriority.medium;
}

String envelopePriorityLabel(EnvelopePriority priority) {
  switch (priority) {
    case EnvelopePriority.high:
      return "Высокий";
    case EnvelopePriority.medium:
      return "Средний";
    case EnvelopePriority.low:
      return "Низкий";
  }
}

class PlanLine {
  PlanLine({
    required this.pk,
    required this.balance,
    this.priority = EnvelopePriority.medium,
    this.scheduled = 0,
    this.goalMonthly = 0,
    this.hasGoal = false,
  });
  final String pk;
  final double balance;
  final EnvelopePriority priority;
  final double scheduled; // платежи, которые ещё предстоят в этом месяце
  final double goalMonthly; // ежемесячный взнос на цель
  final bool hasGoal; // с целью: остаток в конце месяца не уходит в «Свободные»

  /// Сколько ещё нужно положить (0, если лежащего хватает).
  double get need => max(0.0, scheduled + goalMonthly - balance);
}

double _round(double value, int decimals) {
  double factor = pow(10, decimals).toDouble();
  return (value * factor).round() / factor;
}

class PlanResult {
  PlanResult({required this.amounts, required this.shortfall});
  final Map<String, double> amounts; // сколько добавить в каждую подгруппу
  final double shortfall; // сколько не хватило до потребности
}

/// Раскладка поступления: по приоритету (высокий → низкий), внутри приоритета
/// по порядку подгрупп. Что не ушло в потребности, остаётся в «Свободных».
PlanResult planDeposit({
  required List<PlanLine> lines,
  required double deposit,
  int decimals = 2,
}) {
  Map<String, double> amounts = {for (PlanLine l in lines) l.pk: 0.0};
  double left = max(0.0, deposit);
  double shortfall = 0;
  for (EnvelopePriority priority in EnvelopePriority.values) {
    for (PlanLine line in lines.where((l) => l.priority == priority)) {
      double give = min(line.need, left);
      amounts[line.pk] = amounts[line.pk]! + give;
      left -= give;
      shortfall += line.need - give;
    }
  }
  return PlanResult(
    amounts: {for (var e in amounts.entries) e.key: _round(e.value, decimals)},
    shortfall: _round(shortfall, decimals),
  );
}

/// Хватит ли свободных денег, чтобы закрыть нехватку [shortage]?
bool freeCovers(double shortage, double free) => free + 0.005 >= shortage;

/// Сколько взять из «Свободных» на нехватку.
double takeFromFree(double shortage, double free, {int decimals = 2}) =>
    _round(min(max(0.0, shortage), max(0.0, free)), decimals);

class PlanMove {
  PlanMove(this.from, this.to, this.amount);
  final String? from; // null — свободные
  final String? to;
  final double amount;
}

/// Конец месяца: нерастраченное уходит в «Свободные». Подгруппы с целью
/// (накопления) остаются как есть.
List<PlanMove> sweepMonthEnd({
  required List<PlanLine> lines,
  int decimals = 2,
}) {
  return [
    for (PlanLine line in lines)
      if (!line.hasGoal && line.balance > 0)
        PlanMove(line.pk, null, _round(line.balance, decimals)),
  ];
}
