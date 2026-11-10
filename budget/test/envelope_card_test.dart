// Локальная версия: тесты карточки подгруппы (полоска, состояние, ЗП и аванс).

import 'package:budget/struct/envelopeCard.dart';
import 'package:budget/struct/envelopePlan.dart';
import 'package:flutter_test/flutter_test.dart';

PlanLine line({
  double balance = 0,
  double scheduled = 0,
  double longRequired = 0,
  double goalRequired = 0,
  double wish = 0,
}) {
  return PlanLine(
    pk: "e",
    balance: balance,
    scheduled: scheduled,
    longRequired: longRequired,
    goalRequired: goalRequired,
    wish: wish,
  );
}

void main() {
  group('состояние карточки', () {
    test('лежит 6000 из 8000: не хватает 2000, полоска 75%', () {
      EnvelopeCardInfo info = envelopeCardInfo(line(balance: 6000, scheduled: 8000));
      expect(info.state, EnvelopeCardState.short);
      expect(info.amount, 2000);
      expect(info.progress, closeTo(0.75, 1e-9));
    });

    test('лежит ровно нужное: хватает, полоска полная', () {
      EnvelopeCardInfo info = envelopeCardInfo(line(balance: 2400, scheduled: 2400));
      expect(info.state, EnvelopeCardState.enough);
      expect(info.progress, 1);
      expect(info.amount, 0);
    });

    test('лежит больше нужного: полоска не выходит за 100%', () {
      EnvelopeCardInfo info = envelopeCardInfo(line(balance: 5000, scheduled: 2400));
      expect(info.state, EnvelopeCardState.enough);
      expect(info.progress, 1);
    });

    test('отрицательный остаток не уводит полоску ниже нуля', () {
      EnvelopeCardInfo info = envelopeCardInfo(line(balance: -300, scheduled: 1000));
      expect(info.state, EnvelopeCardState.short);
      expect(info.progress, 0);
      expect(info.amount, 1300);
    });

    test('цель без платежей: копим, полоска по сумме цели', () {
      EnvelopeCardInfo info =
          envelopeCardInfo(line(balance: 0, wish: 3000), targetAmount: 3000);
      expect(info.state, EnvelopeCardState.saving);
      expect(info.amount, 3000);
      expect(info.progress, 0);
    });

    test('цель без суммы в подгруппе: берём лежит + осталось', () {
      EnvelopeCardInfo info = envelopeCardInfo(line(balance: 1000, wish: 3000));
      expect(info.state, EnvelopeCardState.saving);
      expect(info.amount, 4000);
      expect(info.progress, closeTo(0.25, 1e-9));
    });

    test('цель достигнута: хватает', () {
      EnvelopeCardInfo info =
          envelopeCardInfo(line(balance: 3000), targetAmount: 3000);
      expect(info.state, EnvelopeCardState.enough);
      expect(info.progress, 1);
    });

    test('ничего не нужно и цели нет: пусто', () {
      EnvelopeCardInfo info = envelopeCardInfo(line(balance: 500));
      expect(info.state, EnvelopeCardState.none);
      expect(info.progress, 0);
    });
  });

  group('приоритет', () {
    test('высокий 3, средний 2, низкий 1', () {
      expect(priorityLevel(EnvelopePriority.high), 3);
      expect(priorityLevel(EnvelopePriority.medium), 2);
      expect(priorityLevel(EnvelopePriority.low), 1);
    });
  });

  group('ЗП и аванс', () {
    test('нечего добавлять: пусто', () {
      expect(payShares(0, DateTime(2026, 11, 5)), isEmpty);
    });

    test('до 12-го: ЗП 2/3 и аванс 1/3', () {
      List<PayShare> shares = payShares(4000, DateTime(2026, 11, 10));
      expect(shares.length, 2);
      expect(shares[0].kind, PayKind.salary);
      expect(shares[0].date, DateTime(2026, 11, 12));
      expect(shares[0].amount, closeTo(2666.67, 0.01));
      expect(shares[1].kind, PayKind.advance);
      expect(shares[1].date, DateTime(2026, 11, 25));
      expect(shares[1].amount, closeTo(1333.33, 0.01));
    });

    test('с 13-го до 25-го: аванс забирает всё', () {
      List<PayShare> shares = payShares(4000, DateTime(2026, 11, 20));
      expect(shares.length, 1);
      expect(shares[0].kind, PayKind.advance);
      expect(shares[0].amount, 4000);
    });

    test('после 25-го: «сейчас»', () {
      List<PayShare> shares = payShares(4000, DateTime(2026, 11, 28));
      expect(shares.length, 1);
      expect(shares[0].kind, PayKind.now);
      expect(shares[0].amount, 4000);
    });

    test('сумма долей равна потребности', () {
      for (int d in [1, 12, 13, 25, 26, 30]) {
        double sum = payShares(1234.56, DateTime(2026, 11, d))
            .fold(0.0, (double s, PayShare p) => s + p.amount);
        expect(sum, closeTo(1234.56, 1e-9));
      }
    });
  });
}
