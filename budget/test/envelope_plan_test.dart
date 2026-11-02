// Локальная версия: тесты плана распределения по подгруппам (чистая логика).

import 'package:budget/struct/envelopePlan.dart';
import 'package:flutter_test/flutter_test.dart';

PlanLine line(String pk, EnvelopeKind kind,
    {double balance = 0,
    double amount = 0,
    double? target,
    DateTime? date}) {
  return PlanLine(
      pk: pk,
      kind: kind,
      balance: balance,
      amount: amount,
      targetAmount: target,
      targetDate: date);
}

void main() {
  test('недель в календарном месяце — число понедельников', () {
    expect(weeksInMonth(2026, 10), 4);
    expect(weeksInMonth(2026, 11), 5);
    expect(weeksInMonth(2026, 2), 4);
  });

  test('доля поступления: 12-е — 2/3, 25-е — 1/3', () {
    expect(receiptShare(DateTime(2026, 10, 12)), closeTo(2 / 3, 1e-9));
    expect(receiptShare(DateTime(2026, 10, 25)), closeTo(1 / 3, 1e-9));
    expect(receiptShare(DateTime(2026, 10, 3)), closeTo(2 / 3, 1e-9));
    expect(receiptShare(DateTime(2026, 10, 30)), closeTo(1 / 3, 1e-9));
  });

  test('потребность: месяц, неделя, накопление', () {
    DateTime october = DateTime(2026, 10, 12);
    expect(monthlyNeed(line("a", EnvelopeKind.monthly, amount: 6000), october),
        6000);
    expect(monthlyNeed(line("b", EnvelopeKind.weekly, amount: 300), october),
        1200);
    expect(
        monthlyNeed(
            line("c", EnvelopeKind.accumulating,
                balance: 0, target: 3000, date: DateTime(2026, 12, 20)),
            october),
        1000);
    expect(monthlyNeed(line("r", EnvelopeKind.reserve), october), 0);
  });

  List<PlanLine> animals() => [
        line("food", EnvelopeKind.monthly, amount: 6000),
        line("meds", EnvelopeKind.monthly, amount: 2000),
        line("toys", EnvelopeKind.weekly, amount: 300),
        line("shots", EnvelopeKind.accumulating,
            target: 3000, date: DateTime(2026, 12, 20)),
        line("reserve", EnvelopeKind.reserve),
      ];

  test('зарплата 12-го: 2/3 потребностей, остаток в «Непредвиденное»', () {
    PlanResult result = planDeposit(
      lines: animals(),
      deposit: 8000,
      share: 2 / 3,
      month: DateTime(2026, 10, 12),
      plannedSum: 10200,
    );
    expect(result.amounts["food"], 4000);
    expect(result.amounts["meds"], closeTo(1333.33, 0.01));
    expect(result.amounts["toys"], 800);
    expect(result.amounts["shots"], closeTo(666.67, 0.01));
    expect(result.amounts["reserve"], closeTo(1200, 0.02));
    expect(result.shortfall, 0);
    double sum = result.amounts.values.fold(0.0, (a, b) => a + b);
    expect(sum, closeTo(8000, 0.02));
  });

  test('денег мало: накопления получают только остаток, есть недобор', () {
    PlanResult result = planDeposit(
      lines: animals(),
      deposit: 5500,
      share: 2 / 3,
      month: DateTime(2026, 10, 12),
    );
    expect(result.amounts["food"], 4000);
    expect(result.amounts["meds"], closeTo(1333.33, 0.01));
    expect(result.amounts["toys"], closeTo(166.67, 0.01));
    expect(result.amounts["shots"], 0);
    expect(result.amounts["reserve"], 0);
    expect(result.shortfall, closeTo(1300, 0.02));
  });

  test('минус в подгруппе закрывается первым', () {
    List<PlanLine> lines = [
      line("food", EnvelopeKind.monthly, amount: 600, balance: -100),
      line("reserve", EnvelopeKind.reserve),
    ];
    PlanResult result = planDeposit(
      lines: lines,
      deposit: 1000,
      share: 1,
      month: DateTime(2026, 10, 12),
    );
    expect(result.amounts["food"], 700);
    expect(result.amounts["reserve"], 300);
  });

  test('нехватка: сначала «Непредвиденное», потом текущие, потом накопления',
      () {
    List<PlanLine> lines = [
      line("food", EnvelopeKind.monthly, balance: -500),
      line("meds", EnvelopeKind.monthly, balance: 300),
      line("shots", EnvelopeKind.accumulating, balance: 1000),
      line("reserve", EnvelopeKind.reserve, balance: 200),
      line("manual", EnvelopeKind.none, balance: 9999),
    ];
    List<PlanMove> moves =
        coverShortage(lines: lines, pk: "food", shortage: 500, free: 50);
    expect(moves.map((m) => m.from).toList(), ["reserve", "meds"]);
    expect(moves[0].amount, 200);
    expect(moves[1].amount, 300);

    List<PlanMove> more =
        coverShortage(lines: lines, pk: "food", shortage: 1400, free: 50);
    expect(more.map((m) => m.from).toList(), ["reserve", "meds", "shots"]);
    expect(more[2].amount, 900);
  });

  test('конец месяца: остатки текущих строк уходят в «Непредвиденное»', () {
    List<PlanLine> lines = [
      line("food", EnvelopeKind.monthly, balance: 400),
      line("toys", EnvelopeKind.weekly, balance: 0),
      line("shots", EnvelopeKind.accumulating, balance: 1000),
      line("reserve", EnvelopeKind.reserve, balance: 100),
    ];
    List<PlanMove> moves = sweepMonthEnd(lines: lines);
    expect(moves.length, 1);
    expect(moves.single.from, "food");
    expect(moves.single.to, "reserve");
    expect(moves.single.amount, 400);
  });
}
