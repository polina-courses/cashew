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
    this.longRequired = 0,
    this.goalRequired = 0,
    this.hasGoal = false,
    this.wish = 0,
    this.accrualMonthly = 0,
    this.accrualDue,
  });
  final String pk;
  final double balance;
  final EnvelopePriority priority;
  final double scheduled; // платежи, которые ещё предстоят в этом месяце
  // Копилка под редкие платежи (раз в 3/6 месяцев, раз в год): сколько должно
  // лежать к концу этого месяца, чтобы к сроку набралась вся сумма.
  final double longRequired;
  // Цель со сроком: сколько должно лежать к концу этого месяца
  // (остаток на начало месяца + ежемесячный взнос).
  final double goalRequired;
  final bool hasGoal; // с целью: остаток в конце месяца не уходит в «Свободные»
  // Цель без срока: сколько ещё осталось собрать «по возможности»
  final double wish;
  // Копим к будущему платежу: сколько в месяц и к какому сроку (ближайшему)
  final double accrualMonthly;
  final DateTime? accrualDue;

  /// Сколько ещё нужно положить (0, если лежащего хватает).
  double get need =>
      max(0.0, scheduled + longRequired + goalRequired - balance);
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
/// по порядку подгрупп. [share] — какую часть потребности даёт это поступление
/// (зарплата 2/3, аванс — всё оставшееся). То, что не ушло в потребности,
/// идёт в цели без срока «по возможности», остальное остаётся в «Свободных».
PlanResult planDeposit({
  required List<PlanLine> lines,
  required double deposit,
  double share = 1.0,
  int decimals = 2,
}) {
  Map<String, double> amounts = {for (PlanLine l in lines) l.pk: 0.0};
  double left = max(0.0, deposit);
  double shortfall = 0;
  for (EnvelopePriority priority in EnvelopePriority.values) {
    for (PlanLine line in lines.where((l) => l.priority == priority)) {
      double want = line.need * share;
      double give = min(want, left);
      amounts[line.pk] = amounts[line.pk]! + give;
      left -= give;
      shortfall += want - give;
    }
  }
  for (PlanLine line in lines) {
    if (line.wish <= 0 || left <= 0) continue;
    double give = min(line.wish, left);
    amounts[line.pk] = amounts[line.pk]! + give;
    left -= give;
  }
  return PlanResult(
    amounts: {for (var e in amounts.entries) e.key: _round(e.value, decimals)},
    shortfall: _round(shortfall, decimals),
  );
}

/// Доля потребности, которую закрывает поступление: зарплата (ближайшее
/// к 12-му числу) — 2/3, аванс (к 25-му) — всё, что осталось.
double receiptShare(DateTime date) {
  return (date.day - 12).abs() <= (date.day - 25).abs() ? 2 / 3 : 1.0;
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
