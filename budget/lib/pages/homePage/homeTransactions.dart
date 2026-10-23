import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/transactionFilters.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/transactionEntries.dart';
import 'package:flutter/material.dart';

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
    SearchFilters searchFilters = SearchFilters(
      paidStatus: [isUpcomingTab ? PaidStatus.notPaid : PaidStatus.paid],
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
      key: ValueKey(isUpcomingTab),
      renderType: TransactionEntriesRenderType.implicitlyAnimatedNonSlivers,
      showNoResults: isUpcomingTab,
      noResultsMessage: "Предстоящих транзакций нет",
      DateTime.now().justDay(monthOffset: -1),
      isUpcomingTab
          ? DateTime.now().justDay(dayOffset: 90)
          : DateTime.now().justDay(),
      dateDividerColor: Colors.transparent,
      useHorizontalPaddingConstrained: false,
      pastDaysLimitToShow: isUpcomingTab ? null : 7,
      limitPerDay: 50,
      searchFilters: searchFilters,
      enableFutureTransactionsCollapse: false,
    );
  }
}
