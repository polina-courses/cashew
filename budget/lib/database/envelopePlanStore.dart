// Локальная версия: хранение плана подгрупп (в настройках приложения, без
// изменения схемы БД) и применение плана к реальным остаткам.
//
//   envelopePlans: {envelopePk: {"k": "monthly", "a": 6000}}
//   walletPlans:   {walletPk: {"sum": 12000}}
//   envelopeSweep: {walletPk: "2026-10"}  — последний месяц, за который сделан перенос остатков

import 'package:budget/database/envelopes.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/envelopePlan.dart';
import 'package:budget/struct/settings.dart';

Map<String, dynamic> _mapSetting(String key) {
  final dynamic raw = appStateSettings[key];
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v));
  }
  return {};
}

({EnvelopeKind kind, double amount}) getEnvelopePlan(String envelopePk) {
  final dynamic entry = _mapSetting("envelopePlans")[envelopePk];
  if (entry is Map) {
    return (
      kind: envelopeKindFromString(entry["k"]?.toString()),
      amount: (entry["a"] is num) ? (entry["a"] as num).toDouble() : 0.0,
    );
  }
  return (kind: EnvelopeKind.none, amount: 0.0);
}

Future<void> setEnvelopePlan(
    String envelopePk, EnvelopeKind kind, double amount) async {
  Map<String, dynamic> plans = _mapSetting("envelopePlans");
  if (kind == EnvelopeKind.none) {
    plans.remove(envelopePk);
  } else {
    plans[envelopePk] = {"k": kind.name, "a": amount};
  }
  await updateSettings("envelopePlans", plans, updateGlobalState: false);
}

double getWalletPlannedSum(String walletPk) {
  final dynamic entry = _mapSetting("walletPlans")[walletPk];
  if (entry is Map && entry["sum"] is num) {
    return (entry["sum"] as num).toDouble();
  }
  return 0;
}

Future<void> setWalletPlannedSum(String walletPk, double sum) async {
  Map<String, dynamic> plans = _mapSetting("walletPlans");
  if (sum <= 0) {
    plans.remove(walletPk);
  } else {
    plans[walletPk] = {"sum": sum};
  }
  await updateSettings("walletPlans", plans, updateGlobalState: false);
}

bool walletHasPlan(EnvelopeBalances balances) {
  return balances.envelopes
      .any((e) => getEnvelopePlan(e.envelopePk).kind != EnvelopeKind.none);
}

List<PlanLine> planLinesOf(EnvelopeBalances balances) {
  return [
    for (Envelope envelope in balances.envelopes)
      PlanLine(
        pk: envelope.envelopePk,
        kind: getEnvelopePlan(envelope.envelopePk).kind,
        amount: getEnvelopePlan(envelope.envelopePk).amount,
        balance: balances.balanceOf(envelope.envelopePk),
        targetAmount: envelope.targetAmount,
        targetDate: envelope.targetDate,
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

  /// Минусов быть не должно: если в подгруппе не хватает, деньги берутся из
  /// других подгрупп (сначала «Непредвиденное»), затем из свободных.
  Future<void> fixNegativeEnvelopes(String walletPk) async {
    for (int round = 0; round < 20; round++) {
      EnvelopeBalances balances = await getEnvelopeBalances(walletPk);
      List<PlanLine> lines = planLinesOf(balances);
      PlanLine? negative;
      for (PlanLine line in lines) {
        if (line.balance < -0.0001) {
          negative = line;
          break;
        }
      }
      if (negative == null) return;
      List<PlanMove> moves = coverShortage(
        lines: lines,
        pk: negative.pk,
        shortage: -negative.balance,
        free: balances.free,
      );
      if (moves.isEmpty) return; // денег больше нигде нет
      await _applyMoves(walletPk, moves);
    }
  }

  /// Календарный месяц закончился: остатки текущих строк уходят в «Непредвиденное».
  Future<void> sweepEnvelopesIfMonthChanged(String walletPk) async {
    Map<String, dynamic> sweeps = _mapSetting("envelopeSweep");
    String nowKey = _monthKey(DateTime.now());
    String? last = sweeps[walletPk]?.toString();
    if (last == nowKey) return;
    if (last != null) {
      EnvelopeBalances balances = await getEnvelopeBalances(walletPk);
      await _applyMoves(walletPk, sweepMonthEnd(lines: planLinesOf(balances)));
    }
    sweeps[walletPk] = nowKey;
    await updateSettings("envelopeSweep", sweeps, updateGlobalState: false);
  }

  /// Привести подгруппы счёта в порядок: перенос остатков и закрытие минусов.
  Future<void> prepareEnvelopes(String walletPk) async {
    await sweepEnvelopesIfMonthChanged(walletPk);
    await fixNegativeEnvelopes(walletPk);
  }
}
