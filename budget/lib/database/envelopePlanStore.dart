// Локальная версия: хранение плана подгрупп (в настройках приложения, без
// изменения схемы БД) и применение плана к реальным остаткам.
//
//   envelopePlans: {envelopePk: {"p": "high|medium|low"}}  — приоритет
//   envelopeSweep: {walletPk: "2026-10"}  — последний месяц, за который сделан перенос остатков
//
// Платежи подгруппы — это неоплаченные расходы календаря с этой подгруппой.

import 'dart:math';

import 'package:budget/database/envelopes.dart';
import 'package:budget/database/tables.dart';
import 'package:drift/drift.dart' show Value;
import 'package:budget/struct/envelopePlan.dart';
import 'package:budget/struct/settings.dart';

Map<String, dynamic> _mapSetting(String key) {
  final dynamic raw = appStateSettings[key];
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  return {};
}

EnvelopePriority getEnvelopePriority(String envelopePk) {
  final dynamic entry = _mapSetting("envelopePlans")[envelopePk];
  if (entry is Map) return envelopePriorityFromString(entry["p"]?.toString());
  return EnvelopePriority.medium;
}

Future<void> setEnvelopePriority(
    String envelopePk, EnvelopePriority priority) async {
  Map<String, dynamic> plans = _mapSetting("envelopePlans");
  plans[envelopePk] = {"p": priority.name};
  await updateSettings("envelopePlans", plans, updateGlobalState: false);
}

DateTime? _occurrenceDate(Transaction base, int n) {
  int period = (base.periodLength ?? 1) < 1 ? 1 : (base.periodLength ?? 1);
  DateTime d = base.dateCreated;
  switch (base.reoccurrence) {
    case BudgetReoccurence.yearly:
      return DateTime(d.year + n * period, d.month, d.day, d.hour, d.minute);
    case BudgetReoccurence.monthly:
      return DateTime(d.year, d.month + n * period, d.day, d.hour, d.minute);
    case BudgetReoccurence.weekly:
      return DateTime(d.year, d.month, d.day + n * period * 7, d.hour, d.minute);
    case BudgetReoccurence.daily:
      return DateTime(d.year, d.month, d.day + n * period, d.hour, d.minute);
    default:
      return null;
  }
}

/// Платежи календаря по подгруппам счёта, которые ещё предстоят в этом месяце:
/// неоплаченные (в том числе просроченные) и расчётные повторы до конца месяца.
Future<Map<String, double>> getScheduledForMonth(
    FinanceDatabase db, String walletPk,
    {DateTime? now}) async {
  DateTime today = now ?? DateTime.now();
  DateTime todayStart = DateTime(today.year, today.month, today.day);
  DateTime monthEnd = DateTime(today.year, today.month + 1, 1);
  List<Transaction> items = await (db.select(db.transactions)
        ..where((t) =>
            t.walletFk.equals(walletPk) &
            t.paid.equals(false) &
            t.skipPaid.equals(false) &
            t.income.equals(false) &
            t.envelopeFk.isNotNull() &
            (t.type.equals(TransactionSpecialType.upcoming.index) |
                t.type.equals(TransactionSpecialType.repetitive.index) |
                t.type.equals(TransactionSpecialType.subscription.index))))
      .get();
  Map<String, double> result = {};
  void add(Transaction t) {
    result[t.envelopeFk!] = (result[t.envelopeFk!] ?? 0) + t.amount.abs();
  }

  for (Transaction t in items) {
    if (t.dateCreated.isBefore(monthEnd)) add(t);
    bool repeats = t.type == TransactionSpecialType.repetitive ||
        t.type == TransactionSpecialType.subscription;
    if (!repeats || t.createdAnotherFutureTransaction == true) continue;
    for (int n = 1; n <= 400; n++) {
      DateTime? date = _occurrenceDate(t, n);
      if (date == null || !date.isBefore(monthEnd)) break;
      if (t.endDate != null && t.endDate!.isBefore(date)) break;
      if (date.isBefore(todayStart)) continue;
      add(t);
    }
  }
  return result;
}

/// Ежемесячный взнос на цель подгруппы (0, если цели нет).
double goalMonthlyOf(Envelope envelope, double balance) {
  if (envelope.targetAmount == null || envelope.targetDate == null) return 0;
  double left = envelope.targetAmount! - balance;
  if (left <= 0) return 0;
  DateTime now = DateTime.now();
  DateTime target = envelope.targetDate!;
  int months = max(1, (target.year - now.year) * 12 + target.month - now.month + 1);
  return left / months;
}

List<PlanLine> planLinesOf(
    EnvelopeBalances balances, Map<String, double> scheduled) {
  return [
    for (Envelope envelope in balances.envelopes)
      PlanLine(
        pk: envelope.envelopePk,
        balance: balances.balanceOf(envelope.envelopePk),
        priority: getEnvelopePriority(envelope.envelopePk),
        scheduled: scheduled[envelope.envelopePk] ?? 0,
        goalMonthly:
            goalMonthlyOf(envelope, balances.balanceOf(envelope.envelopePk)),
        hasGoal: (envelope.targetAmount ?? 0) > 0,
      ),
  ];
}

String _monthKey(DateTime date) =>
    date.year.toString() + "-" + date.month.toString().padLeft(2, "0");

extension EnvelopePlanQueries on FinanceDatabase {
  Future<void> _applyMoves(String walletPk, List<PlanMove> moves) async {
    for (PlanMove move in moves) {
      await addEnvelopeMove(
        walletPk: walletPk,
        fromEnvelopePk: move.from,
        toEnvelopePk: move.to,
        amount: move.amount,
      );
    }
  }

  /// Минусов быть не должно: нехватку в подгруппе закрывают «Свободные».
  /// Если свободных нет, минус остаётся (его видно красным).
  Future<void> fixNegativeEnvelopes(String walletPk) async {
    EnvelopeBalances balances = await getEnvelopeBalances(walletPk);
    double free = balances.free;
    for (Envelope envelope in balances.envelopes) {
      double balance = balances.balanceOf(envelope.envelopePk);
      if (balance >= -0.0001) continue;
      double take = takeFromFree(-balance, free);
      if (take <= 0) continue;
      await addEnvelopeMove(
        walletPk: walletPk,
        fromEnvelopePk: null,
        toEnvelopePk: envelope.envelopePk,
        amount: take,
      );
      free -= take;
    }
  }

  /// Календарный месяц закончился: остатки уходят в «Свободные».
  Future<void> sweepEnvelopesIfMonthChanged(String walletPk) async {
    Map<String, dynamic> sweeps = _mapSetting("envelopeSweep");
    String nowKey = _monthKey(DateTime.now());
    String? last = sweeps[walletPk]?.toString();
    if (last == nowKey) return;
    if (last != null) {
      EnvelopeBalances balances = await getEnvelopeBalances(walletPk);
      await _applyMoves(
          walletPk, sweepMonthEnd(lines: planLinesOf(balances, {})));
    }
    sweeps[walletPk] = nowKey;
    await updateSettings("envelopeSweep", sweeps, updateGlobalState: false);
  }

  /// Привести подгруппы счёта в порядок: перенос остатков и закрытие минусов.
  Future<void> prepareEnvelopes(String walletPk) async {
    await sweepEnvelopesIfMonthChanged(walletPk);
    await fixNegativeEnvelopes(walletPk);
  }

  /// Можно ли провести оплату расхода: если в подгруппе не хватает, а свободных
  /// денег тоже нет — возвращает текст причины, иначе null.
  Future<String?> envelopePayBlockReason(Transaction t) async {
    if (t.income || t.envelopeFk == null) return null;
    Envelope? envelope = await getEnvelopeOrNull(t.envelopeFk!);
    if (envelope == null) return null;
    EnvelopeBalances balances = await getEnvelopeBalances(t.walletFk);
    double shortage = t.amount.abs() - balances.balanceOf(t.envelopeFk!);
    if (shortage <= 0) return null;
    return freeCovers(shortage, balances.free) ? null : "Нет свободных денег";
  }
}
