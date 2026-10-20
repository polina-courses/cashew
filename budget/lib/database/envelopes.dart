// Локальная версия: подгруппы счёта («конверты») — запросы к базе.
//
// Как считается остаток:
//   остаток подгруппы = Σ перемещений в неё − Σ перемещений из неё + Σ её трат
//                       (траты хранятся с минусом, учитываются только оплаченные)
//   свободные деньги  = баланс счёта − Σ остатков подгрупп
//
// Пополнение счёта само по себе попадает в свободные, а распределение по
// подгруппам — это перемещения «свободные → подгруппа».

import 'dart:async';

import 'package:budget/database/tables.dart';
import 'package:drift/drift.dart';

class EnvelopeBalances {
  EnvelopeBalances({
    required this.envelopes,
    required this.balances,
    required this.walletTotal,
  });

  final List<Envelope> envelopes;
  final Map<String, double> balances;
  final double walletTotal;

  double balanceOf(String envelopePk) => balances[envelopePk] ?? 0;

  double get allocated {
    double total = 0;
    for (Envelope envelope in envelopes) total += balanceOf(envelope.envelopePk);
    return total;
  }

  double get free => walletTotal - allocated;

  double get percentTotal {
    double total = 0;
    for (Envelope envelope in envelopes) total += envelope.percent;
    return total;
  }
}

extension EnvelopeQueries on FinanceDatabase {
  Stream<List<Envelope>> watchEnvelopes(String walletPk) {
    return (select(envelopes)
          ..where((e) => e.walletFk.equals(walletPk))
          ..orderBy([(e) => OrderingTerm.asc(e.order)]))
        .watch();
  }

  Future<List<Envelope>> getEnvelopes(String walletPk) {
    return (select(envelopes)
          ..where((e) => e.walletFk.equals(walletPk))
          ..orderBy([(e) => OrderingTerm.asc(e.order)]))
        .get();
  }

  Future<Envelope?> getEnvelopeOrNull(String envelopePk) {
    return (select(envelopes)..where((e) => e.envelopePk.equals(envelopePk)))
        .getSingleOrNull();
  }

  Future<void> createEnvelope({
    required String walletPk,
    required String name,
    required double percent,
  }) async {
    int count = (await getEnvelopes(walletPk)).length;
    await into(envelopes).insert(EnvelopesCompanion.insert(
      walletFk: walletPk,
      name: name.trim(),
      percent: Value(percent),
      order: count,
    ));
  }

  Future<void> updateEnvelope(Envelope envelope) async {
    await into(envelopes).insertOnConflictUpdate(envelope);
  }

  /// Удаляет подгруппу: её остаток возвращается в свободные деньги счёта,
  /// траты остаются, но уже без подгруппы.
  Future<void> deleteEnvelope(Envelope envelope) async {
    await transaction(() async {
      await (delete(envelopeMoves)
            ..where((m) =>
                m.fromEnvelopeFk.equals(envelope.envelopePk) |
                m.toEnvelopeFk.equals(envelope.envelopePk)))
          .go();
      await (update(transactions)
            ..where((t) => t.envelopeFk.equals(envelope.envelopePk)))
          .write(TransactionsCompanion(envelopeFk: Value(null)));
      await (delete(envelopes)
            ..where((e) => e.envelopePk.equals(envelope.envelopePk)))
          .go();
    });
  }

  /// Перемещение денег. null — свободные деньги счёта.
  Future<void> addEnvelopeMove({
    required String walletPk,
    required String? fromEnvelopePk,
    required String? toEnvelopePk,
    required double amount,
    String? sourceTransactionPk,
  }) async {
    if (amount == 0 || fromEnvelopePk == toEnvelopePk) return;
    await into(envelopeMoves).insert(EnvelopeMovesCompanion.insert(
      walletFk: walletPk,
      fromEnvelopeFk: Value(fromEnvelopePk),
      toEnvelopeFk: Value(toEnvelopePk),
      amount: amount,
      sourceTransactionFk: Value(sourceTransactionPk),
    ));
  }

  /// Распределение пополнения: несколько перемещений «свободные → подгруппа».
  Future<void> distributeToEnvelopes({
    required String walletPk,
    required Map<String, double> amounts,
    String? sourceTransactionPk,
  }) async {
    await transaction(() async {
      for (MapEntry<String, double> entry in amounts.entries) {
        if (entry.value == 0) continue;
        await addEnvelopeMove(
          walletPk: walletPk,
          fromEnvelopePk: null,
          toEnvelopePk: entry.key,
          amount: entry.value,
          sourceTransactionPk: sourceTransactionPk,
        );
      }
    });
  }

  /// Удаляет распределения, сделанные из удалённых пополнений.
  Future<void> deleteEnvelopeMovesOfTransactions(
      List<String> transactionPks) async {
    if (transactionPks.isEmpty) return;
    await (delete(envelopeMoves)
          ..where((m) => m.sourceTransactionFk.isIn(transactionPks)))
        .go();
  }

  /// При удалении счёта удаляем его подгруппы и перемещения.
  Future<void> deleteEnvelopesOfWallet(String walletPk) async {
    await (delete(envelopeMoves)..where((m) => m.walletFk.equals(walletPk)))
        .go();
    await (delete(envelopes)..where((e) => e.walletFk.equals(walletPk))).go();
  }

  Stream<double> _watchWalletTotal(String walletPk) {
    final total = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([total])
      ..where(transactions.walletFk.equals(walletPk) &
          transactions.paid.equals(true));
    return query.map((row) => row.read(total) ?? 0).watchSingle();
  }

  Stream<Map<String, double>> _watchEnvelopeSpending(String walletPk) {
    final total = transactions.amount.sum();
    final query = selectOnly(transactions)
      ..addColumns([transactions.envelopeFk, total])
      ..where(transactions.walletFk.equals(walletPk) &
          transactions.paid.equals(true) &
          transactions.envelopeFk.isNotNull())
      ..groupBy([transactions.envelopeFk]);
    return query.watch().map((rows) {
      Map<String, double> result = {};
      for (TypedResult row in rows) {
        String? envelopePk = row.read(transactions.envelopeFk);
        if (envelopePk == null) continue;
        result[envelopePk] = row.read(total) ?? 0;
      }
      return result;
    });
  }

  Stream<List<EnvelopeMove>> _watchEnvelopeMoves(String walletPk) {
    return (select(envelopeMoves)..where((m) => m.walletFk.equals(walletPk)))
        .watch();
  }

  /// Подгруппы счёта с остатками; обновляется при любом изменении данных.
  Stream<EnvelopeBalances> watchEnvelopeBalances(String walletPk) {
    return _combineLatest4<List<Envelope>, List<EnvelopeMove>,
        Map<String, double>, double, EnvelopeBalances>(
      watchEnvelopes(walletPk),
      _watchEnvelopeMoves(walletPk),
      _watchEnvelopeSpending(walletPk),
      _watchWalletTotal(walletPk),
      (envelopeList, moves, spending, walletTotal) {
        Map<String, double> balances = {};
        for (Envelope envelope in envelopeList) {
          balances[envelope.envelopePk] = spending[envelope.envelopePk] ?? 0;
        }
        for (EnvelopeMove move in moves) {
          if (move.toEnvelopeFk != null &&
              balances.containsKey(move.toEnvelopeFk)) {
            balances[move.toEnvelopeFk!] =
                balances[move.toEnvelopeFk!]! + move.amount;
          }
          if (move.fromEnvelopeFk != null &&
              balances.containsKey(move.fromEnvelopeFk)) {
            balances[move.fromEnvelopeFk!] =
                balances[move.fromEnvelopeFk!]! - move.amount;
          }
        }
        return EnvelopeBalances(
          envelopes: envelopeList,
          balances: balances,
          walletTotal: walletTotal,
        );
      },
    );
  }

  Future<EnvelopeBalances> getEnvelopeBalances(String walletPk) {
    return watchEnvelopeBalances(walletPk).first;
  }
}

Stream<R> _combineLatest4<A, B, C, D, R>(
  Stream<A> a,
  Stream<B> b,
  Stream<C> c,
  Stream<D> d,
  R Function(A a, B b, C c, D d) combine,
) {
  late StreamController<R> controller;
  List<StreamSubscription> subscriptions = [];
  A? lastA;
  B? lastB;
  C? lastC;
  D? lastD;
  bool hasA = false, hasB = false, hasC = false, hasD = false;

  void emit() {
    if (hasA && hasB && hasC && hasD) {
      controller.add(combine(lastA as A, lastB as B, lastC as C, lastD as D));
    }
  }

  controller = StreamController<R>(
    onListen: () {
      subscriptions = [
        a.listen((v) {
          lastA = v;
          hasA = true;
          emit();
        }, onError: controller.addError),
        b.listen((v) {
          lastB = v;
          hasB = true;
          emit();
        }, onError: controller.addError),
        c.listen((v) {
          lastC = v;
          hasC = true;
          emit();
        }, onError: controller.addError),
        d.listen((v) {
          lastD = v;
          hasD = true;
          emit();
        }, onError: controller.addError),
      ];
    },
    onCancel: () async {
      for (StreamSubscription subscription in subscriptions) {
        await subscription.cancel();
      }
    },
  );
  return controller.stream;
}
