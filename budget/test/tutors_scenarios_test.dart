// Локальная версия: сценарии «Репетиторы» — несколько еженедельных платежей
// в одной подгруппе; потребность = ещё предстоящие платежи минус то, что лежит.

import 'package:budget/database/envelopePlanStore.dart';
import 'package:budget/database/envelopes.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/envelopePlan.dart';
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FinanceDatabase db;
  late String tutorsPk;

  setUp(() async {
    db = FinanceDatabase(NativeDatabase.memory());
    await db.createEnvelope(walletPk: "0", name: "Репетиторы", percent: 0);
    tutorsPk = (await db.getEnvelopes("0")).single.envelopePk;
  });

  tearDown(() async {
    await db.close();
  });

  // Октябрь 2026: понедельники 5, 12, 19, 26 и среды 7, 14, 21, 28 — 8 уроков по 1000.
  Future<void> weekly(String name, DateTime due, {bool paid = false}) async {
    await db.into(db.transactions).insert(TransactionsCompanion.insert(
          name: name,
          amount: -1000,
          note: "",
          categoryFk: "1",
          walletFk: Value("0"),
          envelopeFk: Value(tutorsPk),
          paid: Value(paid),
          type: Value(paid
              ? null
              : TransactionSpecialType.repetitive),
          reoccurrence: Value(paid ? null : BudgetReoccurence.weekly),
          periodLength: Value(paid ? null : 1),
          dateCreated: Value(due),
          createdAnotherFutureTransaction: Value(paid),
        ));
  }

  Future<double> need(DateTime now, {double? extraBalance}) async {
    EnvelopeBalances balances = await db.getEnvelopeBalances("0");
    Map<String, ScheduledInfo> scheduled =
        await getScheduledForMonth(db, "0", now: now);
    PlanLine line = PlanLine(
      pk: tutorsPk,
      balance: balances.balanceOf(tutorsPk),
      scheduled: scheduled[tutorsPk]?.scheduled ?? 0,
    );
    return line.need;
  }

  test('ситуация 1: на начало месяца 8000, списали 2000 — пополнение не нужно',
      () async {
    await db.distributeToEnvelopes(walletPk: "0", amounts: {tutorsPk: 8000});
    await weekly("Биология", DateTime(2026, 10, 5), paid: true);
    await weekly("Химия", DateTime(2026, 10, 7), paid: true);
    await weekly("Биология", DateTime(2026, 10, 12));
    await weekly("Химия", DateTime(2026, 10, 14));
    expect(await need(DateTime(2026, 10, 8)), 0);
  });

  test('ситуация 2: на начало месяца неполная сумма — есть нехватка', () async {
    await db.distributeToEnvelopes(walletPk: "0", amounts: {tutorsPk: 5000});
    await weekly("Биология", DateTime(2026, 10, 5));
    await weekly("Химия", DateTime(2026, 10, 7));
    expect(await need(DateTime(2026, 10, 1)), 3000);
  });

  test('ситуация 3: середина месяца, оплачено 4000, лежит 3000 — нужно 1000 с аванса',
      () async {
    await db.distributeToEnvelopes(walletPk: "0", amounts: {tutorsPk: 7000});
    await weekly("Биология", DateTime(2026, 10, 5), paid: true);
    await weekly("Химия", DateTime(2026, 10, 7), paid: true);
    await weekly("Биология", DateTime(2026, 10, 12), paid: true);
    await weekly("Химия", DateTime(2026, 10, 14), paid: true);
    await weekly("Биология", DateTime(2026, 10, 19));
    await weekly("Химия", DateTime(2026, 10, 21));
    DateTime now = DateTime(2026, 10, 18);
    double value = await need(now);
    expect(value, 1000);
    var split = splitNeed(value, now);
    expect(split.$1, 0);
    expect(split.$2, 1000);
  });
}
