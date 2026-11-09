// Локальная версия: новая главная — общая сумма, «Отложить на счета»,
// ближайшие платежи. Шестерёнка справа вверху ведёт в «Ещё и настройки».

import 'package:budget/colors.dart';
import 'package:budget/database/envelopes.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/homePage/homePageTopUpSummary.dart';
import 'package:budget/pages/settingsPage.dart';
import 'package:budget/pages/transactionFilters.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

GlobalKey<NewHomePageState> newHomePageStateKey = GlobalKey();

const List<String> _monthsShort = [
  "янв", "фев", "мар", "апр", "май", "июн",
  "июл", "авг", "сен", "окт", "ноя", "дек"
];

class NewHomePage extends StatefulWidget {
  const NewHomePage({Key? key}) : super(key: key);

  @override
  State<NewHomePage> createState() => NewHomePageState();
}

class NewHomePageState extends State<NewHomePage> {
  GlobalKey<PageFrameworkState> pageState = GlobalKey();

  void scrollToTop() => pageState.currentState?.scrollToTop();
  void refreshState() => setState(() {});

  @override
  Widget build(BuildContext context) {
    return PageFramework(
      key: pageState,
      title: "Главная",
      backButton: false,
      horizontalPaddingConstrained: true,
      actions: [
        IconButton(
          tooltip: "Ещё и настройки",
          icon: Icon(Icons.settings_outlined),
          onPressed: () =>
              pushRoute(context, MoreActionsPage(showBackButton: true)),
        ),
      ],
      listWidgets: [
        HomeHeroCard(),
        HomePageTopUpSummary(),
        HomeUpcomingList(),
        SizedBox(height: 90),
      ],
    );
  }
}

class HomeHeroCard extends StatelessWidget {
  const HomeHeroCard({super.key});

  Future<double> _allocated() async {
    double sum = 0;
    for (TransactionWallet w in await database.getAllWallets()) {
      EnvelopeBalances b = await database.getEnvelopeBalances(w.walletPk);
      for (Envelope e in b.envelopes) {
        double v = b.balanceOf(e.envelopePk);
        if (v > 0) sum += v;
      }
    }
    return sum;
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    String money(double v) => convertToMoney(allWallets, v);
    const Color green = Color(0xFF1F7A5A);
    Widget stat(String label, String value) => Expanded(
          child: Container(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white.withOpacity(0.14),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFont(
                    text: label,
                    fontSize: 13,
                    textColor: Colors.white.withOpacity(0.9),
                    maxLines: 1),
                SizedBox(height: 2),
                TextFont(
                    text: value,
                    fontSize: 17,
                    fontWeight: FontWeight.w600,
                    textColor: Colors.white,
                    maxLines: 1,
                    autoSizeText: true),
              ],
            ),
          ),
        );
    return StreamBuilder<List<EnvelopeMove>>(
      stream: database.select(database.envelopeMoves).watch(),
      builder: (context, _) => StreamBuilder<TotalWithCount?>(
        stream: database.watchTotalWithCountOfWallet(
          isIncome: null,
          allWallets: allWallets,
          searchFilters: SearchFilters(walletPks: []),
        ),
        builder: (context, snap) => FutureBuilder<double>(
          future: _allocated(),
          builder: (context, alloc) {
            double total = snap.data?.total ?? 0;
            double allocated = alloc.data ?? 0;
            double free = total - allocated;
            return Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 13, vertical: 7),
              child: Container(
                padding: const EdgeInsetsDirectional.all(20),
                decoration: BoxDecoration(
                  color: green,
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFont(
                        text: "Всего на всех счетах",
                        fontSize: 14,
                        textColor: Colors.white.withOpacity(0.9)),
                    SizedBox(height: 6),
                    TextFont(
                      text: money(total),
                      fontSize: 36,
                      fontWeight: FontWeight.bold,
                      textColor: Colors.white,
                      maxLines: 1,
                      autoSizeText: true,
                    ),
                    SizedBox(height: 14),
                    Row(
                      children: [
                        stat("Свободно", money(free)),
                        SizedBox(width: 12),
                        stat("В подгруппах", money(allocated)),
                      ],
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class HomeUpcomingList extends StatelessWidget {
  const HomeUpcomingList({super.key});

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    Color light = getColor(context, "textLight");
    return StreamBuilder<List<Transaction>>(
      stream: database.watchAllUpcomingTransactions(null),
      builder: (context, snapshot) {
        List<Transaction> list = (snapshot.data ?? []).take(4).toList();
        if (list.isEmpty) return SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.symmetric(
              horizontal: 13, vertical: 7),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.only(start: 4, bottom: 8),
                child: TextFont(
                    text: "Ближайшие платежи",
                    fontSize: 17,
                    fontWeight: FontWeight.w600),
              ),
              Container(
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: getColor(context, "lightDarkAccentHeavyLight"),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  children: [
                    for (int i = 0; i < list.length; i++)
                      _UpcomingRow(
                        transaction: list[i],
                        first: i == 0,
                        walletName:
                            allWallets.indexedByPk[list[i].walletFk]?.name ?? "",
                        light: light,
                        money: (v) => convertToMoney(allWallets, v),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _UpcomingRow extends StatelessWidget {
  const _UpcomingRow({
    required this.transaction,
    required this.first,
    required this.walletName,
    required this.light,
    required this.money,
  });
  final Transaction transaction;
  final bool first;
  final String walletName;
  final Color light;
  final String Function(double) money;

  @override
  Widget build(BuildContext context) {
    DateTime d = transaction.dateCreated;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(top: BorderSide(color: getColor(context, "dividerColor"))),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: getColor(context, "canvasContainer"),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                TextFont(
                    text: d.day.toString(),
                    fontSize: 17,
                    fontWeight: FontWeight.bold),
                TextFont(text: _monthsShort[d.month - 1], fontSize: 12, textColor: light),
              ],
            ),
          ),
          SizedBox(width: 12),
          Expanded(
            child: FutureBuilder<TransactionCategory?>(
              future: database.getCategoryInstanceOrNull(transaction.categoryFk),
              builder: (context, snap) {
                String title = transaction.name.trim().isNotEmpty
                    ? transaction.name.trim()
                    : (snap.data?.name ?? "");
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    TextFont(text: title, fontSize: 16, maxLines: 2),
                    TextFont(
                        text: walletName,
                        fontSize: 14,
                        textColor: light,
                        maxLines: 1),
                  ],
                );
              },
            ),
          ),
          SizedBox(width: 12),
          TextFont(
            text: (transaction.income ? "+" : "−") +
                money(transaction.amount.abs()),
            fontSize: 16,
            fontWeight: FontWeight.w600,
            maxLines: 1,
          ),
        ],
      ),
    );
  }
}
