// Локальная версия: календарь предстоящих платежей.
// Показывает неоплаченные запланированные, повторяющиеся и подписочные платежи
// по неделям или месяцам. По клику на дату — список платежей этого дня.

import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/struct/currencyFunctions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/navigationSidebar.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/transactionEntry/transactionEntry.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

class UpcomingCalendarPage extends StatefulWidget {
  const UpcomingCalendarPage({required this.enableBackButton, Key? key})
      : super(key: key);
  final bool enableBackButton;

  @override
  State<UpcomingCalendarPage> createState() => UpcomingCalendarPageState();
}

DateTime calendarDayOnly(DateTime date) =>
    DateTime(date.year, date.month, date.day);

class UpcomingCalendarPageState extends State<UpcomingCalendarPage> {
  GlobalKey<PageFrameworkState> pageState = GlobalKey();
  final String pageId = "UpcomingCalendar";

  late final Stream<List<Transaction>> upcomingStream =
      database.watchAllOverdueUpcomingTransactions(null);

  DateTime focusedDay = calendarDayOnly(DateTime.now());
  // null — показываем весь период (неделю/месяц), иначе только выбранный день
  DateTime? selectedDay;
  bool weekMode = true;

  void scrollToTop() {
    pageState.currentState?.scrollToTop();
  }

  void goToPrevious() {
    setState(() {
      selectedDay = null;
      focusedDay = weekMode
          ? DateTime(focusedDay.year, focusedDay.month, focusedDay.day - 7)
          : DateTime(focusedDay.year, focusedDay.month - 1, 1);
    });
  }

  void goToNext() {
    setState(() {
      selectedDay = null;
      focusedDay = weekMode
          ? DateTime(focusedDay.year, focusedDay.month, focusedDay.day + 7)
          : DateTime(focusedDay.year, focusedDay.month + 1, 1);
    });
  }

  // Клетки сетки: 7 дней недели или все клетки месяца.
  // null — пустая клетка до первого и после последнего дня месяца.
  List<DateTime?> visibleCells() {
    if (weekMode) {
      DateTime start = DateTime(focusedDay.year, focusedDay.month,
          focusedDay.day - (focusedDay.weekday - 1));
      return List.generate(
          7, (i) => DateTime(start.year, start.month, start.day + i));
    }
    DateTime first = DateTime(focusedDay.year, focusedDay.month, 1);
    int leading = first.weekday - 1;
    int daysInMonth = DateTime(first.year, first.month + 1, 0).day;
    int total = ((leading + daysInMonth + 6) ~/ 7) * 7;
    return List.generate(total, (i) {
      int dayNumber = i - leading + 1;
      if (dayNumber < 1 || dayNumber > daysInMonth) return null;
      return DateTime(first.year, first.month, dayNumber);
    });
  }

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      key: pageState,
      title: "calendar".tr(),
      backButton: widget.enableBackButton,
      dragDownToDismiss: widget.enableBackButton,
      horizontalPaddingConstrained: enableDoubleColumn(context) == false,
      listID: pageId,
      slivers: [
        StreamBuilder<List<Transaction>>(
          stream: upcomingStream,
          builder: (context, snapshot) {
            Map<DateTime, List<Transaction>> byDay = {};
            for (Transaction transaction in snapshot.data ?? []) {
              byDay
                  .putIfAbsent(
                      calendarDayOnly(transaction.dateCreated), () => [])
                  .add(transaction);
            }
            return SliverToBoxAdapter(child: buildBody(context, byDay));
          },
        ),
      ],
    );
  }

  Widget buildBody(BuildContext context, Map<DateTime, List<Transaction>> byDay) {
    String locale = context.locale.toString();
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    List<DateTime?> cells = visibleCells();
    DateTime periodStart = cells.firstWhere((d) => d != null)!;
    DateTime periodEnd = cells.lastWhere((d) => d != null)!;

    // Платежи периода в порядке от ближайших к дальним.
    // Просроченные (дата раньше сегодняшней) вынесены в отдельный блок.
    DateTime todayStart = calendarDayOnly(DateTime.now());
    List<Transaction> periodTransactions = [];
    List<Transaction> overdueTransactions = [];
    for (DateTime day in byDay.keys) {
      if (day.isBefore(todayStart)) {
        overdueTransactions.addAll(byDay[day]!);
        continue;
      }
      if (day.isBefore(periodStart) || day.isAfter(periodEnd)) continue;
      periodTransactions.addAll(byDay[day]!);
    }
    periodTransactions
        .sort((a, b) => a.dateCreated.compareTo(b.dateCreated));
    overdueTransactions
        .sort((a, b) => a.dateCreated.compareTo(b.dateCreated));

    AllWallets allWallets = Provider.of<AllWallets>(context);
    double plannedExpenses = 0;
    double plannedIncome = 0;
    for (Transaction t in periodTransactions) {
      double amount = t.amount.abs() *
          amountRatioToPrimaryCurrencyGivenPk(allWallets, t.walletFk);
      if (t.income)
        plannedIncome += amount;
      else
        plannedExpenses += amount;
    }
    String periodWord = weekMode ? "На неделе" : "В месяце";
    String summaryExpenses = plannedExpenses > 0
        ? "$periodWord запланировано трат на сумму ${convertToMoney(allWallets, plannedExpenses)}"
        : (weekMode
            ? "На неделе трат не запланировано"
            : "В месяце трат не запланировано");

    double overdueExpenses = 0;
    for (Transaction t in overdueTransactions) {
      if (t.income) continue;
      overdueExpenses += t.amount.abs() *
          amountRatioToPrimaryCurrencyGivenPk(allWallets, t.walletFk);
    }

    List<Transaction> shownTransactions = selectedDay == null
        ? periodTransactions
        : (byDay[selectedDay] ?? const <Transaction>[]).toList();

    String title;
    if (weekMode) {
      title =
          "${DateFormat.MMMd(locale).format(cells.first!)} – ${DateFormat.MMMd(locale).format(cells.last!)}";
    } else {
      title = DateFormat.yMMMM(locale).format(focusedDay).capitalizeFirst;
    }

    List<Widget> rows = [];
    for (int start = 0; start < cells.length; start += 7) {
      rows.add(Row(
        children: [
          for (DateTime? day in cells.sublist(start, start + 7))
            Expanded(
              child: day == null
                  ? SizedBox(height: 54)
                  : buildDayCell(
                      context,
                      day: day,
                      count: byDay[day]?.length ?? 0,
                      selected: day == selectedDay,
                    ),
            ),
        ],
      ));
    }

    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 13),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(height: 10),
          SegmentedButton<bool>(
            showSelectedIcon: false,
            segments: [
              ButtonSegment<bool>(value: false, label: Text("month".tr())),
              ButtonSegment<bool>(value: true, label: Text("week".tr())),
            ],
            selected: {weekMode},
            onSelectionChanged: (Set<bool> selection) {
              setState(() {
                weekMode = selection.first;
                selectedDay = null;
              });
            },
          ),
          SizedBox(height: 10),
          Row(
            children: [
              IconButton(
                onPressed: goToPrevious,
                icon: Icon(Icons.chevron_left_rounded),
              ),
              Expanded(
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
                ),
              ),
              IconButton(
                onPressed: goToNext,
                icon: Icon(Icons.chevron_right_rounded),
              ),
            ],
          ),
          Row(
            children: [
              for (int i = 0; i < 7; i++)
                Expanded(
                  child: Center(
                    child: Text(
                      DateFormat.E(locale)
                          .format(DateTime(2024, 1, 1 + i))
                          .capitalizeFirst,
                      style: TextStyle(
                        fontSize: 12,
                        color: colorScheme.outline,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          SizedBox(height: 4),
          ...rows,
          SizedBox(height: 14),
          Container(
            padding: EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: colorScheme.secondaryContainer.withOpacity(0.5),
              borderRadius: BorderRadius.circular(15),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  summaryExpenses,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
                ),
                if (plannedIncome > 0) ...[
                  SizedBox(height: 4),
                  Text(
                    "Ожидается поступлений на сумму ${convertToMoney(allWallets, plannedIncome)}",
                    style: TextStyle(fontSize: 14),
                  ),
                ],
              ],
            ),
          ),
          if (selectedDay == null && overdueTransactions.isNotEmpty) ...[
            SizedBox(height: 14),
            Text(
              "Просрочено — нужно оплатить или отменить",
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: getColor(context, "unPaidOverdue"),
              ),
            ),
            if (overdueExpenses > 0)
              Padding(
                padding: const EdgeInsetsDirectional.only(top: 2),
                child: Text(
                  "Не оплачено на сумму ${convertToMoney(allWallets, overdueExpenses)}",
                  style: TextStyle(fontSize: 13, color: colorScheme.outline),
                ),
              ),
            ...buildDatedList(overdueTransactions, locale),
          ],
          if (selectedDay != null) ...[
            SizedBox(height: 6),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: () => setState(() => selectedDay = null),
                child: Text(
                    "Показать весь ${weekMode ? "период недели" : "месяц"}"),
              ),
            ),
          ],
          if (shownTransactions.isEmpty) ...[
            SizedBox(height: 18),
            Center(
              child: Text(
                "Запланированных платежей нет",
                style: TextStyle(color: colorScheme.outline),
              ),
            ),
            SizedBox(height: 30),
          ] else ...[
            if (selectedDay == null && overdueTransactions.isNotEmpty) ...[
              SizedBox(height: 18),
              Text(
                weekMode ? "Запланировано на неделю" : "Запланировано на месяц",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold),
              ),
            ],
            ...buildDatedList(shownTransactions, locale),
            SizedBox(height: 30),
          ],
        ],
      ),
    );
  }

  // Список платежей с заголовком-датой перед каждым днём
  List<Widget> buildDatedList(List<Transaction> list, String locale) {
    return [
      for (int i = 0; i < list.length; i++) ...[
        if (i == 0 ||
            calendarDayOnly(list[i].dateCreated) !=
                calendarDayOnly(list[i - 1].dateCreated)) ...[
          SizedBox(height: 14),
          Text(
            DateFormat.MMMMEEEEd(locale)
                .format(list[i].dateCreated)
                .capitalizeFirst,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 6),
        ],
        TransactionEntry(
          key: ValueKey(list[i].transactionPk),
          openPage: AddTransactionPage(
            transaction: list[i],
            routesToPopAfterDelete: RoutesToPopAfterDelete.One,
          ),
          transaction: list[i],
          listID: pageId,
        ),
      ],
    ];
  }

  Widget buildDayCell(BuildContext context,
      {required DateTime day, required int count, required bool selected}) {
    ColorScheme colorScheme = Theme.of(context).colorScheme;
    bool isToday = calendarDayOnly(DateTime.now()) == day;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () {
        setState(() {
          selectedDay = selectedDay == day ? null : day;
        });
      },
      child: SizedBox(
        height: 54,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 34,
              height: 34,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: selected ? colorScheme.primary : null,
                border: isToday && !selected
                    ? Border.all(color: colorScheme.primary, width: 1.5)
                    : null,
              ),
              child: Text(
                day.day.toString(),
                style: TextStyle(
                  fontWeight:
                      selected || isToday ? FontWeight.bold : FontWeight.normal,
                  color: selected ? colorScheme.onPrimary : null,
                ),
              ),
            ),
            SizedBox(height: 3),
            Container(
              width: 5,
              height: 5,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: count > 0
                    ? getColor(context, "unPaidUpcoming")
                    : Colors.transparent,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
