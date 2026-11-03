// Локальная версия: тесты логики подгрупп (потребность, приоритеты, «Свободные»).

import 'package:budget/struct/envelopePlan.dart';
import 'package:flutter_test/flutter_test.dart';

PlanLine line(String pk,
    {double balance = 0,
    double scheduled = 0,
    double goalRequired = 0,
    double longRequired = 0,
    double wish = 0,
    bool hasGoal = false,
    EnvelopePriority priority = EnvelopePriority.medium}) {
  return PlanLine(
      pk: pk,
      balance: balance,
      scheduled: scheduled,
      goalRequired: goalRequired,
      longRequired: longRequired,
      wish: wish,
      hasGoal: hasGoal,
      priority: priority);
}

void main() {
  test('карманные: 5 понедельников = 1250, после первого платежа пополнение не нужно',
      () {
    // начало месяца: лежит 1250, впереди 5 платежей по 250
    expect(line("p", balance: 1250, scheduled: 1250).need, 0);
    // отметили первый платёж: лежит 1000, впереди 4 платежа
    expect(line("p", balance: 1000, scheduled: 1000).need, 0);
    // лежит только 750 при 1250 впереди — нужно 500
    expect(line("p", balance: 750, scheduled: 1250).need, 500);
  });

  test('зарплата 750 + аванс 500 закрывают 1250 по частям', () {
    PlanResult salary = planDeposit(
        lines: [line("p", scheduled: 1250)], deposit: 750);
    expect(salary.amounts["p"], 750);
    expect(salary.shortfall, 500);
    PlanResult advance = planDeposit(
        lines: [line("p", balance: 750, scheduled: 1250)], deposit: 500);
    expect(advance.amounts["p"], 500);
    expect(advance.shortfall, 0);
  });

  test('приоритеты: сначала высокий, потом средний, потом низкий', () {
    PlanResult result = planDeposit(lines: [
      line("low", scheduled: 1000, priority: EnvelopePriority.low),
      line("high", scheduled: 1000, priority: EnvelopePriority.high),
      line("mid", scheduled: 1000, priority: EnvelopePriority.medium),
    ], deposit: 1500);
    expect(result.amounts["high"], 1000);
    expect(result.amounts["mid"], 500);
    expect(result.amounts["low"], 0);
    expect(result.shortfall, 1500);
  });

  test('лишние деньги не раскладываются: остаются свободными', () {
    PlanResult result = planDeposit(
        lines: [line("a", scheduled: 300), line("b", scheduled: 200)],
        deposit: 1000);
    expect(result.amounts["a"], 300);
    expect(result.amounts["b"], 200);
    expect(result.shortfall, 0);
  });

  test('цель со сроком и копилка под редкие платежи входят в потребность', () {
    expect(line("g", scheduled: 100, goalRequired: 1000, hasGoal: true).need,
        1100);
    expect(line("y", longRequired: 3000, balance: 2000).need, 1000);
  });

  test('зарплата даёт 2/3 потребности, аванс — всё оставшееся', () {
    expect(receiptShare(DateTime(2026, 11, 12)), closeTo(2 / 3, 1e-9));
    expect(receiptShare(DateTime(2026, 11, 25)), 1.0);
    PlanResult salary = planDeposit(
        lines: [line("p", scheduled: 1250)], deposit: 5000, share: 2 / 3);
    expect(salary.amounts["p"], closeTo(833.33, 0.01));
    PlanResult advance = planDeposit(
        lines: [line("p", balance: 833.33, scheduled: 1250)], deposit: 5000);
    expect(advance.amounts["p"], closeTo(416.67, 0.01));
  });

  test('цели без срока получают деньги последними, из остатка', () {
    PlanResult result = planDeposit(lines: [
      line("a", scheduled: 500),
      line("wish", wish: 3000),
    ], deposit: 2000);
    expect(result.amounts["a"], 500);
    expect(result.amounts["wish"], 1500);
    PlanResult tight = planDeposit(lines: [
      line("a", scheduled: 500),
      line("wish", wish: 3000),
    ], deposit: 400);
    expect(tight.amounts["wish"], 0);
  });

  test('нехватка закрывается только из свободных', () {
    expect(freeCovers(300, 300), true);
    expect(freeCovers(300, 299), false);
    expect(takeFromFree(300, 200), 200);
    expect(takeFromFree(300, 500), 300);
    expect(takeFromFree(300, -5), 0);
  });

  test('конец месяца: остатки уходят в свободные, цели остаются', () {
    List<PlanMove> moves = sweepMonthEnd(lines: [
      line("pocket", balance: 250),
      line("goal", balance: 5000, hasGoal: true),
      line("empty", balance: 0),
    ]);
    expect(moves.length, 1);
    expect(moves.single.from, "pocket");
    expect(moves.single.to, null);
    expect(moves.single.amount, 250);
  });
}
