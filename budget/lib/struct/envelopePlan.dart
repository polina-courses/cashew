// Локальная версия: план распределения денег по подгруппам счёта.
// Чистая логика без базы и экрана — чтобы её можно было проверить тестами.
//
// Виды строк:
//   monthly      — тратится каждый месяц (корм, лекарства): сумма в месяц
//   weekly       — тратится каждую неделю: сумма за неделю × число недель в месяце
//   accumulating — копится к цели и дате: (цель − накоплено) / месяцев до даты
//   reserve      — «Непредвиденное»: получает остатки и копит их
//   none         — без плана, ручное управление (деньги не трогаем)

import 'dart:math';

enum EnvelopeKind { none, monthly, weekly, accumulating, reserve }

EnvelopeKind envelopeKindFromString(String? value) {
  for (EnvelopeKind kind in EnvelopeKind.values) {
    if (kind.name == value) return kind;
  }
  return EnvelopeKind.none;
}

String envelopeKindLabel(EnvelopeKind kind) {
  switch (kind) {
    case EnvelopeKind.monthly:
      return "Каждый месяц";
    case EnvelopeKind.weekly:
      return "Каждую неделю";
    case EnvelopeKind.accumulating:
      return "Накопление";
    case EnvelopeKind.reserve:
      return "Непредвиденное";
    case EnvelopeKind.none:
      return "Без плана";
  }
}

/// Сколько понедельников в календарном месяце (= сколько «недель» в нём считаем).
int weeksInMonth(int year, int month) {
  int days = DateTime(year, month + 1, 0).day;
  int count = 0;
  for (int day = 1; day <= days; day++) {
    if (DateTime(year, month, day).weekday == DateTime.monday) count++;
  }
  return count;
}

/// Доля месяца, которая приходится на поступление: ближайшая к дате выплата
/// (12-е — зарплата, 2/3; 25-е — аванс, 1/3).
double receiptShare(DateTime date) {
  int day = date.day;
  int toSalary = (day - 12).abs();
  int toAdvance = (day - 25).abs();
  return toSalary <= toAdvance ? 2 / 3 : 1 / 3;
}

class PlanLine {
  PlanLine({
    required this.pk,
    required this.kind,
    required this.balance,
    this.amount = 0,
    this.targetAmount,
    this.targetDate,
  });
  final String pk;
  final EnvelopeKind kind;
  final double balance;
  final double amount; // для monthly — в месяц, для weekly — за неделю
  final double? targetAmount;
  final DateTime? targetDate;

  bool get isCurrent =>
      kind == EnvelopeKind.monthly || kind == EnvelopeKind.weekly;
}

/// Сколько месяцев осталось до даты цели, считая текущий (минимум 1).
int monthsUntil(DateTime from, DateTime target) {
  int months = (target.year - from.year) * 12 + (target.month - from.month) + 1;
  return max(1, months);
}

/// Потребность строки на календарный месяц.
double monthlyNeed(PlanLine line, DateTime month) {
  switch (line.kind) {
    case EnvelopeKind.monthly:
      return max(0.0, line.amount);
    case EnvelopeKind.weekly:
      return max(0.0, line.amount) * weeksInMonth(month.year, month.month);
    case EnvelopeKind.accumulating:
      if (line.targetAmount == null || line.targetDate == null) return 0;
      double left = line.targetAmount! - line.balance;
      if (left <= 0) return 0;
      return left / monthsUntil(month, line.targetDate!);
    case EnvelopeKind.reserve:
    case EnvelopeKind.none:
      return 0;
  }
}

class PlanResult {
  PlanResult({required this.amounts, required this.shortfall});
  final Map<String, double> amounts; // сколько добавить в каждую подгруппу
  final double shortfall; // сколько не хватило до плана на это поступление
}

double _round(double value, int decimals) {
  double factor = pow(10, decimals).toDouble();
  return (value * factor).round() / factor;
}

/// Раскладка одного поступления по плану.
/// 1) закрыть минусы; 2) текущие строки — их доля месяца;
/// 3) накопления — только из того, что осталось; 4) остаток — в «Непредвиденное».
/// [plannedSum] — сумма счёта на месяц; если она больше суммы потребностей,
/// разница тоже идёт в «Непредвиденное» (в долю поступления).
PlanResult planDeposit({
  required List<PlanLine> lines,
  required double deposit,
  required double share,
  required DateTime month,
  double plannedSum = 0,
  int decimals = 2,
}) {
  Map<String, double> amounts = {for (PlanLine l in lines) l.pk: 0.0};
  double left = max(0.0, deposit);
  double shortfall = 0;

  void give(String pk, double want) {
    double wanted = max(0.0, want);
    double got = min(wanted, left);
    amounts[pk] = amounts[pk]! + got;
    left -= got;
    shortfall += wanted - got;
  }

  // 1. минусы
  for (PlanLine line in lines) {
    if (line.balance < 0) give(line.pk, -line.balance);
  }
  // 2. текущие
  double needsTotal = 0;
  for (PlanLine line in lines) {
    double need = monthlyNeed(line, month);
    needsTotal += need;
    if (line.isCurrent) give(line.pk, need * share);
  }
  // 3. накопления
  for (PlanLine line in lines) {
    if (line.kind == EnvelopeKind.accumulating) {
      give(line.pk, monthlyNeed(line, month) * share);
    }
  }
  // план счёта на месяц больше потребностей — тоже недобор, если денег меньше
  shortfall = max(shortfall, plannedSum * share - max(0.0, deposit));
  // 4. остаток — в «Непредвиденное» (плановая часть и всё, что осталось)
  PlanLine? reserve;
  for (PlanLine line in lines) {
    if (line.kind == EnvelopeKind.reserve) {
      reserve = line;
      break;
    }
  }
  if (reserve != null && left > 0) {
    amounts[reserve.pk] = amounts[reserve.pk]! + left;
    left = 0;
  }

  return PlanResult(
    amounts: {for (var e in amounts.entries) e.key: _round(e.value, decimals)},
    shortfall: _round(shortfall, decimals),
  );
}

/// Перемещение денег: from -> to (null — свободные деньги).
class PlanMove {
  PlanMove(this.from, this.to, this.amount);
  final String? from;
  final String? to;
  final double amount;
}

/// Где брать деньги, если в строке [pk] не хватает [shortage]:
/// «Непредвиденное» → другие текущие → накопления → свободные деньги.
/// Строки «без плана» не трогаем. Возвращает перемещения «откуда → в pk».
List<PlanMove> coverShortage({
  required List<PlanLine> lines,
  required String pk,
  required double shortage,
  double free = 0,
  int decimals = 2,
}) {
  List<PlanMove> moves = [];
  double need = shortage;
  List<List<PlanLine>> groups = [
    lines.where((l) => l.kind == EnvelopeKind.reserve && l.pk != pk).toList(),
    lines.where((l) => l.isCurrent && l.pk != pk).toList(),
    lines
        .where((l) => l.kind == EnvelopeKind.accumulating && l.pk != pk)
        .toList(),
  ];
  for (List<PlanLine> group in groups) {
    for (PlanLine line in group) {
      if (need <= 0) break;
      double take = min(need, max(0.0, line.balance));
      take = _round(take, decimals);
      if (take <= 0) continue;
      moves.add(PlanMove(line.pk, pk, take));
      need = _round(need - take, decimals);
    }
  }
  if (need > 0 && free > 0) {
    double take = _round(min(need, free), decimals);
    if (take > 0) moves.add(PlanMove(null, pk, take));
  }
  return moves;
}

/// Конец месяца: нерастраченный остаток текущих строк уходит в «Непредвиденное».
/// Накопления остаются как есть.
List<PlanMove> sweepMonthEnd({
  required List<PlanLine> lines,
  int decimals = 2,
}) {
  PlanLine? reserve;
  for (PlanLine line in lines) {
    if (line.kind == EnvelopeKind.reserve) {
      reserve = line;
      break;
    }
  }
  if (reserve == null) return [];
  List<PlanMove> moves = [];
  for (PlanLine line in lines) {
    if (line.isCurrent && line.balance > 0) {
      moves.add(PlanMove(line.pk, reserve.pk, _round(line.balance, decimals)));
    }
  }
  return moves;
}
