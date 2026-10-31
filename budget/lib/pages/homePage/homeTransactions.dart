import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/transactionFilters.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/transactionEntries.dart';
import 'package:budget/widgets/transactionEntry/transactionEntry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class HomeTransactions extends StatelessWidget {
  const HomeTransactions({
    super.key,
    required this.selectedSlidingSelector,
  });
  final int selectedSlidingSelector;
  @override
  Widget build(BuildContext context) {
    // Локальная версия: вкладка 4 = «Предстоящие» (неоплаченные),
    // остальные вкладки показывают только совершённые операции
    final bool isUpcomingTab = selectedSlidingSelector == 4;
    if (isUpcomingTab) {
      return HomeUpcomingList(selectedSlidingSelector: selectedSlidingSelector);
    }
    int numberOfFutureDays = appStateSettings["futureTransactionDaysHomePage"];
    SearchFilters searchFilters = SearchFilters(
      paidStatus: [PaidStatus.paid],
      expenseIncome:
          appStateSettings["homePageTransactionsListIncomeAndExpenseOnly"] ==
                  true
              ? [
                  if (selectedSlidingSelector == 2) ExpenseIncome.expense,
                  if (selectedSlidingSelector == 3) ExpenseIncome.income
                ]
              : [],
      positiveCashFlow:
          appStateSettings["homePageTransactionsListIncomeAndExpenseOnly"] ==
                  false
              ? selectedSlidingSelector == 2
                  ? false
                  : selectedSlidingSelector == 3
                      ? true
                      : null
              : null,
    );
    return TransactionEntries(
      showNumberOfDaysUntilForFutureDates: true,
      renderType: TransactionEntriesRenderType.implicitlyAnimatedNonSlivers,
      showNoResults: false,
      // Берём запас в полгода, чтобы набралось хотя бы 5 последних операций
      DateTime.now().justDay(monthOffset: -6),
      // До конца сегодняшнего дня и дальше (оплаченные с будущей датой)
      DateTime.now().justDay(dayOffset: numberOfFutureDays),
      dateDividerColor: Colors.transparent,
      useHorizontalPaddingConstrained: false,
      pastDaysLimitToShow: 7,
      limitPerDay: 50,
      searchFilters: searchFilters,
      enableFutureTransactionsCollapse: false,
    );
  }
}

// Локальная версия: вкладка «Предстоящие» на главной.
// Неоплаченные платежи от ближайших (и просроченных) к дальним, с датами.
class HomeUpcomingList extends StatelessWidget {
  const HomeUpcomingList({super.key, required this.selectedSlidingSelector});
  final int selectedSlidingSelector;

  @override
  Widget build(BuildContext context) {
    String locale = context.locale.toString();
    return StreamBuilder<List<Transaction>>(
      stream: database.watchAllOverdueUpcomingTransactions(null),
      builder: (context, snapshot) {
        List<Transaction> list = (snapshot.data ?? [])
            .where((t) => selectedSlidingSelector == 2
                ? !t.income
                : selectedSlidingSelector == 3
                    ? t.income
                    : true)
            .toList();
        list.sort((a, b) => a.dateCreated.compareTo(b.dateCreated));
        if (list.length > 30) list = list.sublist(0, 30);
        if (list.isEmpty) {
          return Padding(
            padding: const EdgeInsetsDirectional.symmetric(vertical: 25),
            child: Center(
              child: Text(
                "Предстоящих транзакций нет",
                style:
                    TextStyle(color: Theme.of(context).colorScheme.outline),
              ),
            ),
          );
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (int i = 0; i < list.length; i++) ...[
              if (i == 0 ||
                  list[i].dateCreated.justDay() !=
                      list[i - 1].dateCreated.justDay())
                Padding(
                  padding: const EdgeInsetsDirectional.only(
                      start: 20, top: 10, bottom: 4),
                  child: Text(
                    DateFormat.MMMMEEEEd(locale)
                        .format(list[i].dateCreated)
                        .capitalizeFirst,
                    style: TextStyle(
                        fontSize: 14, fontWeight: FontWeight.bold),
                  ),
                ),
              TransactionEntry(
                key: ValueKey(list[i].transactionPk),
                openPage: AddTransactionPage(
                  transaction: list[i],
                  routesToPopAfterDelete: RoutesToPopAfterDelete.One,
                ),
                transaction: list[i],
                listID: "HomeUpcoming",
              ),
            ],
          ],
        );
      },
    );
  }
}
