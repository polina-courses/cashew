import 'package:budget/struct/utilities.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('оплата сбрасывается сама в начале следующего месяца', () {
    var i = UtilityItem(id: "1", name: "Свет", amount: 1000);
    i.markPaid(1000, DateTime(2026, 11, 8));
    expect(i.isPaid(DateTime(2026, 11, 30)), true);
    expect(i.isPaid(DateTime(2026, 12, 1)), false);
    expect(i.isPaid(DateTime(2027, 11, 1)), false);
  });

  test('переплата уменьшает следующий платёж', () {
    var i = UtilityItem(id: "1", name: "Вода", amount: 1000);
    i.markPaid(1500, DateTime(2026, 11, 8));
    expect(i.credit, 500);
    expect(i.due(), 500);
    i.markPaid(500, DateTime(2026, 12, 5));
    expect(i.credit, 0);
    expect(i.due(), 1000);
  });

  test('переплата больше суммы: платить не нужно', () {
    var i = UtilityItem(id: "1", name: "Газ", amount: 1000, credit: 2500);
    expect(i.due(), 0);
  });

  test('недоплата попадает в минус и увеличивает платёж', () {
    var i = UtilityItem(id: "1", name: "Отопление", amount: 1000);
    i.markPaid(800, DateTime(2026, 11, 8));
    expect(i.credit, -200);
    expect(i.due(), 1200);
  });

  test('снятие отметки возвращает баланс', () {
    var i = UtilityItem(id: "1", name: "Свет", amount: 1000, credit: 300);
    i.markPaid(1000, DateTime(2026, 11, 8));
    i.unmarkPaid();
    expect(i.credit, 300);
    expect(i.isPaid(DateTime(2026, 11, 8)), false);
  });

  test('без суммы баланс не ведётся', () {
    var i = UtilityItem(id: "1", name: "Свет", amount: 0);
    i.markPaid(777, DateTime(2026, 11, 8));
    expect(i.credit, 0);
    expect(i.isPaid(DateTime(2026, 11, 8)), true);
  });

  test('сохранение в настройки и обратно', () {
    var i = UtilityItem(id: "1", name: "Свет", amount: 1000);
    i.markPaid(1200, DateTime(2026, 11, 8));
    var back = utilitiesFromSettings(utilitiesToSettings([i])).single;
    expect(back.credit, 200);
    expect(back.paidMonth, i.paidMonth);
    expect(back.paidOn, DateTime(2026, 11, 8));
  });

  test('сколько осталось оплатить', () {
    var a = UtilityItem(id: "1", name: "A", amount: 1000);
    var b = UtilityItem(id: "2", name: "B", amount: 500, credit: 200);
    var c = UtilityItem(id: "3", name: "C", amount: 700);
    c.markPaid(700, DateTime(2026, 11, 2));
    expect(utilitiesLeftToPay([a, b, c], DateTime(2026, 11, 8)), 1300);
  });
}
