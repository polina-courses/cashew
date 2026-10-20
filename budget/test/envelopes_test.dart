// Локальная версия: тесты подгрупп счёта (сохранение цели, поток данных, расчёт подсказки).

import 'dart:async';

import 'package:budget/database/envelopes.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/widgets/envelopes.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FinanceDatabase db;

  setUp(() {
    db = FinanceDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    await db.close();
  });

  test('изменение целевой суммы сохраняется в базе', () async {
    DateTime date = DateTime(2026, 12, 7);
    await db.createEnvelope(
      walletPk: "0",
      name: "День рождения",
      percent: 0,
      targetAmount: 12000,
      targetDate: date,
    );
    Envelope envelope = (await db.getEnvelopes("0")).single;
    expect(envelope.targetAmount, 12000);
    expect(envelope.targetDate, date);

    await db.updateEnvelope(envelope.copyWith(
      targetAmount: Value(120000.0),
      targetDate: Value(date),
    ));
    Envelope updated = (await db.getEnvelopes("0")).single;
    expect(updated.targetAmount, 120000);
    expect(updated.targetDate, date);
  });

  test('сброс цели (null) сохраняется в базе', () async {
    await db.createEnvelope(
      walletPk: "0",
      name: "Корм",
      percent: 0,
      targetAmount: 5000,
      targetDate: DateTime(2026, 12, 7),
      note: "заметка",
    );
    Envelope envelope = (await db.getEnvelopes("0")).single;
    await db.updateEnvelope(envelope.copyWith(
      targetAmount: Value(null),
      targetDate: Value(null),
      note: Value(null),
    ));
    Envelope updated = (await db.getEnvelopes("0")).single;
    expect(updated.targetAmount, isNull);
    expect(updated.targetDate, isNull);
    expect(updated.note, isNull);
  });

  test('поток остатков отдаёт новую цель после изменения', () async {
    await db.createEnvelope(
      walletPk: "0",
      name: "День рождения",
      percent: 0,
      targetAmount: 12000,
    );
    List<double?> seenTargets = [];
    Completer<void> gotUpdate = Completer();
    StreamSubscription sub =
        db.watchEnvelopeBalances("0").listen((balances) {
      seenTargets.add(balances.envelopes.single.targetAmount);
      if (balances.envelopes.single.targetAmount == 120000 &&
          !gotUpdate.isCompleted) gotUpdate.complete();
    });
    await Future.delayed(Duration(milliseconds: 200));
    Envelope envelope = (await db.getEnvelopes("0")).single;
    await db.updateEnvelope(
        envelope.copyWith(targetAmount: Value(120000.0)));
    await gotUpdate.future.timeout(Duration(seconds: 5),
        onTimeout: () => fail("Нет обновления в потоке, видели: $seenTargets"));
    await sub.cancel();
  });

  test('рекомендуемое пополнение пересчитывается от суммы цели', () {
    DateTime now = DateTime.now();
    DateTime date = DateTime(now.year, now.month, now.day)
        .add(Duration(days: 91)); // ≈ 3 месяца
    EnvelopeGoal small =
        EnvelopeGoal(targetAmount: 12000, targetDate: date, balance: 0);
    EnvelopeGoal big =
        EnvelopeGoal(targetAmount: 120000, targetDate: date, balance: 0);
    expect(small.monthsLeft, 3);
    expect(small.monthlyRecommended, 4000);
    expect(big.monthlyRecommended, 40000);
  });
}
