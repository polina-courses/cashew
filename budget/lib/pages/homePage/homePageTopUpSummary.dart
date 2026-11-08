// Локальная версия: сводка на «Обзоре» — сколько нужно отложить на счета
// категорий с ЗП и с аванса, и общая сумма по всем счетам.

import 'package:budget/colors.dart';
import 'package:budget/database/envelopePlanStore.dart';
import 'package:budget/database/envelopes.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/struct/categoryAccounts.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/envelopePlan.dart';
import 'package:budget/widgets/envelopes.dart';
import 'package:budget/widgets/categoryTopUp.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';

class _AccountNeed {
  _AccountNeed(this.wallet, this.need);
  final TransactionWallet wallet;
  final double need;
}

/// Сколько нужно добавить на каждый счёт категории (с учётом уже лежащих денег).
Future<List<_AccountNeed>> _loadNeeds() async {
  List<_AccountNeed> result = [];
  for (TransactionWallet wallet in await getCategoryWallets()) {
    EnvelopeBalances balances =
        await database.getEnvelopeBalances(wallet.walletPk);
    if (balances.envelopes.isEmpty) continue;
    Map<String, ScheduledInfo> scheduled =
        await getScheduledForMonth(database, wallet.walletPk);
    double need =
        planLinesOf(balances, scheduled).fold(0.0, (sum, l) => sum + l.need);
    result.add(_AccountNeed(wallet, need));
  }
  return result;
}

class HomePageTopUpSummary extends StatelessWidget {
  const HomePageTopUpSummary({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<EnvelopeMove>>(
      stream: database.select(database.envelopeMoves).watch(),
      builder: (context, _) => StreamBuilder<List<Transaction>>(
        stream: database.watchAllUpcomingTransactions(null),
        builder: (context, __) => FutureBuilder<List<_AccountNeed>>(
          future: _loadNeeds(),
          builder: (context, snapshot) {
            List<_AccountNeed> needs = snapshot.data ?? [];
            if (needs.isEmpty) return SizedBox.shrink();
            DateTime now = DateTime.now();
            double total = needs.fold(0.0, (s, n) => s + n.need);
            double totalSalary = 0, totalAdvance = 0;
            for (_AccountNeed n in needs) {
              var parts = splitNeed(n.need, now);
              totalSalary += parts.$1;
              totalAdvance += parts.$2;
            }
            bool beforeSalary = now.day <= 12;
            TransactionWallet first = needs.first.wallet;
            String money(double v, TransactionWallet w) =>
                envelopeMoney(context, w, v);
            Widget cell(String text,
                {bool head = false,
                bool bold = false,
                bool left = false,
                bool light = false}) {
              return Padding(
                padding: EdgeInsetsDirectional.only(
                    start: left ? 0 : 12, top: 3, bottom: 3),
                child: Align(
                  alignment: left
                      ? AlignmentDirectional.centerStart
                      : AlignmentDirectional.centerEnd,
                  child: left
                      ? TextFont(
                          text: text,
                          fontSize: head ? 12 : 14,
                          fontWeight:
                              head || bold ? FontWeight.bold : FontWeight.normal,
                          textColor: head ? getColor(context, "textLight") : null,
                          maxLines: 1,
                        )
                      : FittedBox(
                          fit: BoxFit.scaleDown,
                          child: TextFont(
                            text: text,
                            fontSize: head ? 12 : 14,
                            fontWeight: head || bold
                                ? FontWeight.bold
                                : FontWeight.normal,
                            textColor: head || light
                                ? getColor(context, "textLight")
                                : null,
                            maxLines: 1,
                          ),
                        ),
                ),
              );
            }

            return Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 13, vertical: 7),
              child: Tappable(
                color: Theme.of(context)
                    .colorScheme
                    .secondaryContainer
                    .withOpacity(0.5),
                borderRadius: 15,
                onTap: () => openTopUpSheet(context),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 15, vertical: 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFont(
                        text: "Нужно отложить на счета категорий",
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                        maxLines: 2,
                      ),
                      SizedBox(height: 8),
                      Table(
                        columnWidths: const {
                          0: FlexColumnWidth(),
                          1: IntrinsicColumnWidth(),
                          2: IntrinsicColumnWidth(),
                          3: IntrinsicColumnWidth(),
                        },
                        defaultVerticalAlignment:
                            TableCellVerticalAlignment.middle,
                        children: [
                          TableRow(children: [
                            cell("Счёт", head: true, left: true),
                            cell("ЗП", head: true),
                            cell("Ав", head: true),
                            cell("Итого", head: true),
                          ]),
                          for (_AccountNeed n in needs)
                            () {
                              var parts = splitNeed(n.need, now);
                              bool ok = n.need <= 0;
                              return TableRow(children: [
                                cell(n.wallet.name, left: true),
                                cell(ok || parts.$1 <= 0
                                    ? "–"
                                    : money(parts.$1, n.wallet)),
                                cell(ok ? "–" : money(parts.$2, n.wallet)),
                                cell(ok ? "хватает" : money(n.need, n.wallet),
                                    bold: !ok, light: ok),
                              ]);
                            }(),
                          TableRow(
                            decoration: BoxDecoration(
                              border: Border(
                                top: BorderSide(
                                    color: getColor(context, "dividerColor"),
                                    width: 1),
                              ),
                            ),
                            children: [
                              cell("Всего", bold: true, left: true),
                              cell(totalSalary <= 0
                                  ? "–"
                                  : money(totalSalary, first), bold: true),
                              cell(totalAdvance <= 0
                                  ? "–"
                                  : money(totalAdvance, first), bold: true),
                              cell(total <= 0 ? "ничего" : money(total, first),
                                  bold: true),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
