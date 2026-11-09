// Локальная версия: хранение плана подгрупп (в настройках приложения, без
// изменения схемы БД) и применение плана к реальным остаткам.
//
//   envelopePlans: {envelopePk: {"p": "high|medium|low"}}  — приоритет
//   envelopeMeta:  {envelopePk: {"c": categoryPk, "t": true}} — категория и «временная» (со сроком)
//   envelopeBase:  {envelopePk: {"m": "2026-11", "b": 1000}} — остаток на начало месяца (для целей)
//   envelopeSweep: {walletPk: "2026-10"}  — последний месяц, за который сделан перенос остатков
//
// Платежи подгруппы — это неоплаченные расходы календаря с этой подгруппой.

import 'dart:math';

import 'package:budget/database/envelopes.dart';
import 'package:budget/database/tables.dart';
import 'package:drift/drift.dart';
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

class ScheduledInfo {
  double scheduled = 0; // платежи, которые предстоят в этом месяце
  double longRequired = 0; // копилка под редкие и будущие платежи
  // платежи, под которые копим: (сумма, сколько месяцев осталось копить, включая этот)
  List<(double, int)> accrualItems = [];
  DateTime? accrualDue; // ближайший срок
}

/// Длительность периода повтора в месяцах (для недель и дней — меньше месяца).
double _periodMonths(Transaction t) {
  int p = (t.periodLength ?? 1) < 1 ? 1 : (t.periodLength ?? 1);
  switch (t.reoccurrence) {
    case BudgetReoccurence.yearly:
      return 12.0 * p;
    case BudgetReoccurence.monthly:
      return p.toDouble();
    default:
      return 0.25 * p;
  }
}

/// Платежи календаря по подгруппам счёта: что ещё предстоит в этом месяце
/// (неоплаченные, в том числе просроченные, и расчётные повторы) и сколько
/// должно лежать к концу месяца под редкие платежи.
Future<Map<String, ScheduledInfo>> getScheduledForMonth(
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
  Map<String, ScheduledInfo> result = {};
  // Месяц, когда платёж впервые попал в расчёт (чтобы делить сумму по месяцам)
  Map<String, int> starts = {
    for (MapEntry<String, dynamic> e in _mapSetting("scheduleStart").entries)
      if (e.value is num) e.key: (e.value as num).toInt()
  };
  bool startsChanged = false;
  ScheduledInfo infoOf(Transaction t) =>
      result.putIfAbsent(t.envelopeFk!, () => ScheduledInfo());

  for (Transaction t in items) {
    double amount = t.amount.abs();
    bool repeats = t.type == TransactionSpecialType.repetitive ||
        t.type == TransactionSpecialType.subscription;
    if (t.dateCreated.isBefore(monthEnd)) infoOf(t).scheduled += amount;
    bool rare = repeats &&
        _periodMonths(t) > 1 &&
        (t.endDate == null || !t.endDate!.isBefore(t.dateCreated));
    if ((!repeats || rare) && !t.dateCreated.isBefore(monthEnd)) {
      // Разовый или редкий платёж (раз в 3/6/12 месяцев) в будущем месяце:
      // копим равными долями по месяцам с того месяца, когда он появился
      int nowIdx = today.year * 12 + today.month;
      int dueIdx = t.dateCreated.year * 12 + t.dateCreated.month;
      int firstIdx = starts[t.transactionPk] ?? nowIdx;
      if (starts[t.transactionPk] == null) {
        starts[t.transactionPk] = nowIdx;
        startsChanged = true;
      }
      int parts = max(1, dueIdx - firstIdx);
      int k = nowIdx - firstIdx + 1;
      ScheduledInfo info = infoOf(t);
      info.longRequired += amount * min(1.0, k / parts);
      info.accrualItems.add((amount, max(1, parts - k + 1)));
      if (info.accrualDue == null || t.dateCreated.isBefore(info.accrualDue!)) {
        info.accrualDue = t.dateCreated;
      }
      continue;
    }
    if (!repeats) continue;
    if (t.createdAnotherFutureTransaction == true) continue;
    for (int n = 1; n <= 400; n++) {
      DateTime? date = _occurrenceDate(t, n);
      if (date == null || !date.isBefore(monthEnd)) break;
      if (t.endDate != null && t.endDate!.isBefore(date)) break;
      if (date.isBefore(todayStart)) continue;
      infoOf(t).scheduled += amount;
    }
  }
  if (startsChanged) {
    await updateSettings("scheduleStart", starts, updateGlobalState: false);
  }
  return result;
}

/// Остаток подгруппы на начало месяца (запоминается при первом открытии в месяце).
double _baseOf(String envelopePk, double fallback) {
  final dynamic m = _mapSetting("envelopeBase")[envelopePk];
  if (m is Map && m["m"] == _monthKey(DateTime.now()) && m["b"] is num) {
    return (m["b"] as num).toDouble();
  }
  return fallback;
}

/// Цель со сроком: сколько должно лежать к концу этого месяца
/// (остаток на начало месяца + ежемесячный взнос). 0, если срока нет.
double goalRequiredOf(Envelope envelope, double balance) {
  if ((envelope.targetAmount ?? 0) <= 0 || envelope.targetDate == null) {
    return 0;
  }
  double target = envelope.targetAmount!;
  double base = min(_baseOf(envelope.envelopePk, balance), target);
  DateTime now = DateTime.now();
  DateTime date = envelope.targetDate!;
  int months =
      max(1, (date.year - now.year) * 12 + date.month - now.month + 1);
  return min(target, base + (target - base) / months);
}

/// Сколько откладывать в месяц на редкие платежи с учётом уже лежащих денег.
double _accrualMonthly(ScheduledInfo? info, double balance) {
  if (info == null || info.accrualItems.isEmpty) return 0;
  double total = info.accrualItems.fold(0.0, (sum, i) => sum + i.$1);
  // деньги под ближайшие платежи этого месяца в копилку не входят
  double saved = max(0.0, balance - info.scheduled);
  double left = max(0.0, 1 - saved / total);
  double monthly = 0;
  for ((double, int) item in info.accrualItems) {
    monthly += item.$1 * left / item.$2;
  }
  return monthly;
}

List<PlanLine> planLinesOf(
    EnvelopeBalances balances, Map<String, ScheduledInfo> scheduled) {
  return [
    for (Envelope envelope in balances.envelopes)
      PlanLine(
        pk: envelope.envelopePk,
        balance: balances.balanceOf(envelope.envelopePk),
        priority: getEnvelopePriority(envelope.envelopePk),
        scheduled: scheduled[envelope.envelopePk]?.scheduled ?? 0,
        longRequired: scheduled[envelope.envelopePk]?.longRequired ?? 0,
        accrualMonthly: _accrualMonthly(
            scheduled[envelope.envelopePk],
            balances.balanceOf(envelope.envelopePk)),
        accrualDue: scheduled[envelope.envelopePk]?.accrualDue,
        goalRequired:
            goalRequiredOf(envelope, balances.balanceOf(envelope.envelopePk)),
        hasGoal: (envelope.targetAmount ?? 0) > 0,
        wish: ((envelope.targetAmount ?? 0) > 0 && envelope.targetDate == null)
            ? max(0.0,
                envelope.targetAmount! - balances.balanceOf(envelope.envelopePk))
            : 0,
      ),
  ];
}

String? getEnvelopeCategoryPk(String envelopePk) {
  final dynamic m = _mapSetting("envelopeMeta")[envelopePk];
  return m is Map ? m["c"]?.toString() : null;
}

bool isTemporaryEnvelope(String envelopePk) {
  final dynamic m = _mapSetting("envelopeMeta")[envelopePk];
  return m is Map && m["t"] == true;
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

  /// Локальная версия: все счета только в рублях.
  Future<void> forceAllWalletsRuble() async {
    await (update(wallets)
          ..where((w) => w.currency.isNull() | w.currency.equals("rub").not()))
        .write(WalletsCompanion(currency: Value("rub")));
  }

  /// Баланс счёта уменьшили (например, обнулили), а в подгруппах деньги
  /// остались: снимаем излишек с подгрупп, чтобы сумма сошлась со счётом.
  /// Снятое запоминаем: если деньги на счёте вернутся (например, удалили
  /// ошибочную трату), подгруппы пополнятся обратно (restoreShrunkEnvelopes).
  /// Если счёт ушёл в минус, подгруппы не трогаем: это ошибка, а не обнуление.
  Future<void> shrinkEnvelopesToWallet(String walletPk) async {
    EnvelopeBalances balances = await getEnvelopeBalances(walletPk);
    if (balances.free >= -0.005) return;
    if (balances.walletTotal < 0) return;
    Map<String, double> take = shrinkToWallet(
        lines: planLinesOf(balances, {}), walletTotal: balances.walletTotal);
    Map<String, dynamic> ledger = _mapSetting("envelopeShrunk");
    Map<String, dynamic> mine =
        Map<String, dynamic>.from((ledger[walletPk] as Map?) ?? {});
    for (MapEntry<String, double> e in take.entries) {
      await addEnvelopeMove(
        walletPk: walletPk,
        fromEnvelopePk: e.key,
        toEnvelopePk: null,
        amount: e.value,
      );
      mine[e.key] = ((mine[e.key] as num?)?.toDouble() ?? 0) + e.value;
    }
    if (take.isNotEmpty) {
      ledger[walletPk] = mine;
      await updateSettings("envelopeShrunk", ledger, updateGlobalState: false);
    }
  }

  /// Разово: подхватить снятия, сделанные версиями до учёта (сборки 120–126),
  /// чтобы их тоже можно было вернуть.
  Future<void> importLegacyShrinks() async {
    if (appStateSettings["envelopeShrinkLegacyDone"] == true) return;
    final DateTime cutoff = DateTime.utc(2026, 11, 8, 16, 0);
    List<EnvelopeMove> moves = await (select(envelopeMoves)
          ..where((m) =>
              m.fromEnvelopeFk.isNotNull() &
              m.toEnvelopeFk.isNull() &
              m.sourceTransactionFk.isNull() &
              m.dateCreated.isBiggerOrEqualValue(cutoff.toLocal())))
        .get();
    Map<String, dynamic> ledger = _mapSetting("envelopeShrunk");
    for (EnvelopeMove m in moves) {
      Map<String, dynamic> mine =
          Map<String, dynamic>.from((ledger[m.walletFk] as Map?) ?? {});
      mine[m.fromEnvelopeFk!] =
          ((mine[m.fromEnvelopeFk!] as num?)?.toDouble() ?? 0) + m.amount;
      ledger[m.walletFk] = mine;
    }
    await updateSettings("envelopeShrunk", ledger, updateGlobalState: false);
    await updateSettings("envelopeShrinkLegacyDone", true,
        updateGlobalState: false);
  }

  /// Деньги на счёте снова есть, а подгруппы ранее были урезаны: возвращаем
  /// снятое из свободных денег (сначала подгруппам с высоким приоритетом).
  Future<void> restoreShrunkEnvelopes(String walletPk) async {
    await importLegacyShrinks();
    Map<String, dynamic> ledger = _mapSetting("envelopeShrunk");
    Map<String, dynamic>? mine =
        ledger[walletPk] == null
            ? null
            : Map<String, dynamic>.from(ledger[walletPk] as Map);
    if (mine == null || mine.isEmpty) return;
    EnvelopeBalances balances = await getEnvelopeBalances(walletPk);
    double free = balances.free;
    if (free <= 0.005) return;
    List<String> order = mine.keys.toList()
      ..sort((a, b) => getEnvelopePriority(a).index
          .compareTo(getEnvelopePriority(b).index));
    Set<String> existing = balances.envelopes.map((e) => e.envelopePk).toSet();
    for (String envelopePk in order) {
      double owed = (mine[envelopePk] as num).toDouble();
      if (!existing.contains(envelopePk)) {
        mine.remove(envelopePk);
        continue;
      }
      double give = takeFromFree(owed, free);
      if (give <= 0) continue;
      await addEnvelopeMove(
        walletPk: walletPk,
        fromEnvelopePk: null,
        toEnvelopePk: envelopePk,
        amount: give,
      );
      free -= give;
      if (owed - give <= 0.005) {
        mine.remove(envelopePk);
      } else {
        mine[envelopePk] = owed - give;
      }
    }
    ledger[walletPk] = mine;
    await updateSettings("envelopeShrunk", ledger, updateGlobalState: false);
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

  /// Подгруппа для периодического расхода: ищем по названию и категории,
  /// иначе создаём. Подгруппа «со сроком» временная, без срока — постоянная.
  Future<String> ensureScheduleEnvelope({
    required String walletPk,
    required String name,
    required String categoryPk,
    required bool temporary,
    EnvelopePriority priority = EnvelopePriority.medium,
  }) async {
    Map<String, dynamic> meta = _mapSetting("envelopeMeta");
    String wanted = name.trim();
    for (Envelope e in await getEnvelopes(walletPk)) {
      final dynamic m = meta[e.envelopePk];
      if (m is Map &&
          m["c"] == categoryPk &&
          e.name.trim().toLowerCase() == wanted.toLowerCase()) {
        if (!temporary && m["t"] == true) {
          meta[e.envelopePk] = {"c": categoryPk, "t": false};
          await updateSettings("envelopeMeta", meta, updateGlobalState: false);
        }
        return e.envelopePk;
      }
    }
    await createEnvelope(walletPk: walletPk, name: wanted, percent: 0);
    String pk = (await getEnvelopes(walletPk)).last.envelopePk;
    meta[pk] = {"c": categoryPk, "t": temporary};
    await updateSettings("envelopeMeta", meta, updateGlobalState: false);
    await setEnvelopePriority(pk, priority);
    return pk;
  }

  /// Временные подгруппы, по которым не осталось платежей, уходят в архив.
  Future<void> removeFinishedTemporaryEnvelopes(String walletPk) async {
    Map<String, dynamic> meta = _mapSetting("envelopeMeta");
    for (Envelope e in await getEnvelopes(walletPk)) {
      final dynamic m = meta[e.envelopePk];
      if (m is! Map || m["t"] != true) continue;
      List<Transaction> left = await (select(transactions)
            ..where((t) =>
                t.envelopeFk.equals(e.envelopePk) &
                t.paid.equals(false) &
                t.skipPaid.equals(false) &
                (t.type.equals(TransactionSpecialType.upcoming.index) |
                    t.type.equals(TransactionSpecialType.repetitive.index) |
                    t.type.equals(TransactionSpecialType.subscription.index)))
            ..limit(1))
          .get();
      if (left.isNotEmpty) continue;
      await archiveEnvelope(e);
    }
  }

  /// В архив: остаток уходит в «Свободные», неоплаченные платежи остаются в
  /// календаре без подгруппы. Прошлые траты и история сохраняются.
  Future<void> archiveEnvelope(Envelope envelope) async {
    EnvelopeBalances balances = await getEnvelopeBalances(envelope.walletFk);
    double balance = balances.balanceOf(envelope.envelopePk);
    if (balance > 0) {
      await addEnvelopeMove(
        walletPk: envelope.walletFk,
        fromEnvelopePk: envelope.envelopePk,
        toEnvelopePk: null,
        amount: balance,
      );
    }
    await (update(transactions)
          ..where((t) =>
              t.envelopeFk.equals(envelope.envelopePk) &
              t.paid.equals(false)))
        .write(TransactionsCompanion(envelopeFk: Value(null)));
    Map<String, dynamic> meta = _mapSetting("envelopeMeta");
    final dynamic old = meta[envelope.envelopePk];
    meta[envelope.envelopePk] = {
      "c": old is Map ? old["c"] : null,
      "t": old is Map ? old["t"] == true : false,
      "a": true,
    };
    await updateSettings("envelopeMeta", meta, updateGlobalState: false);
  }

  Future<void> restoreEnvelope(Envelope envelope) async {
    Map<String, dynamic> meta = _mapSetting("envelopeMeta");
    final dynamic old = meta[envelope.envelopePk];
    meta[envelope.envelopePk] = {
      "c": old is Map ? old["c"] : null,
      "t": false,
      "a": false,
    };
    await updateSettings("envelopeMeta", meta, updateGlobalState: false);
    // обновить потоки данных
    await addEnvelopeMove(
      walletPk: envelope.walletFk,
      fromEnvelopePk: null,
      toEnvelopePk: envelope.envelopePk,
      amount: 0.0001,
    );
    await addEnvelopeMove(
      walletPk: envelope.walletFk,
      fromEnvelopePk: envelope.envelopePk,
      toEnvelopePk: null,
      amount: 0.0001,
    );
  }

  /// Остаток на начало месяца запоминаем при первом открытии в месяце.
  Future<void> snapshotEnvelopeBases(String walletPk) async {
    Map<String, dynamic> base = _mapSetting("envelopeBase");
    String key = _monthKey(DateTime.now());
    EnvelopeBalances balances = await getEnvelopeBalances(walletPk);
    bool changed = false;
    for (Envelope e in balances.envelopes) {
      final dynamic m = base[e.envelopePk];
      if (m is Map && m["m"] == key) continue;
      base[e.envelopePk] = {"m": key, "b": balances.balanceOf(e.envelopePk)};
      changed = true;
    }
    if (changed) {
      await updateSettings("envelopeBase", base, updateGlobalState: false);
    }
  }

  /// Привести подгруппы счёта в порядок: перенос остатков и закрытие минусов.
  Future<void> prepareEnvelopes(String walletPk) async {
    await removeFinishedTemporaryEnvelopes(walletPk);
    await sweepEnvelopesIfMonthChanged(walletPk);
    await shrinkEnvelopesToWallet(walletPk);
    await restoreShrunkEnvelopes(walletPk);
    await fixNegativeEnvelopes(walletPk);
    await snapshotEnvelopeBases(walletPk);
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
