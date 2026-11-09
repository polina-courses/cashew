// Локальная версия: вкладка «Счета» — карточки счетов с суммой и тем,
// сколько нужно добавить. Нажатие открывает счёт с подгруппами.

import 'package:budget/colors.dart';
import 'package:budget/database/envelopePlanStore.dart';
import 'package:budget/database/envelopes.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addWalletPage.dart';
import 'package:budget/pages/settingsPage.dart';
import 'package:budget/pages/transactionFilters.dart';
import 'package:budget/pages/walletDetailsPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/envelopePlan.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

GlobalKey<WalletsTabPageState> walletsTabPageStateKey = GlobalKey();

class WalletsTabPage extends StatefulWidget {
  const WalletsTabPage({Key? key}) : super(key: key);

  @override
  State<WalletsTabPage> createState() => WalletsTabPageState();
}

class WalletsTabPageState extends State<WalletsTabPage> {
  GlobalKey<PageFrameworkState> pageState = GlobalKey();

  void scrollToTop() => pageState.currentState?.scrollToTop();
  void refreshState() => setState(() {});

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    return PageFramework(
      key: pageState,
      title: "Счета",
      backButton: false,
      horizontalPaddingConstrained: true,
      actions: [
        IconButton(
          tooltip: "Добавить счёт",
          icon: Icon(Icons.add_rounded),
          onPressed: () => pushRoute(
              context,
              AddWalletPage(
                  routesToPopAfterDelete: RoutesToPopAfterDelete.None)),
        ),
        IconButton(
          tooltip: "Ещё и настройки",
          icon: Icon(Icons.settings_outlined),
          onPressed: () =>
              pushRoute(context, MoreActionsPage(showBackButton: true)),
        ),
      ],
      listWidgets: [
        for (TransactionWallet wallet in allWallets.list)
          _WalletCard(wallet: wallet),
        SizedBox(height: 90),
      ],
    );
  }
}

class _WalletCard extends StatelessWidget {
  const _WalletCard({required this.wallet});
  final TransactionWallet wallet;

  Future<double> _need() async {
    EnvelopeBalances balances =
        await database.getEnvelopeBalances(wallet.walletPk);
    if (balances.envelopes.isEmpty) return 0;
    Map<String, ScheduledInfo> scheduled =
        await getScheduledForMonth(database, wallet.walletPk);
    return planLinesOf(balances, scheduled).fold(0.0, (sum, l) => sum + l.need);
  }

  @override
  Widget build(BuildContext context) {
    AllWallets allWallets = Provider.of<AllWallets>(context);
    String money(double v) => convertToMoney(allWallets, v,
        currencyKey: wallet.currency, decimals: wallet.decimals);
    return StreamBuilder<List<EnvelopeMove>>(
      stream: database.select(database.envelopeMoves).watch(),
      builder: (context, _) => StreamBuilder<TotalWithCount?>(
        stream: database.watchTotalWithCountOfWallet(
          isIncome: null,
          allWallets: allWallets,
          searchFilters: SearchFilters(walletPks: [wallet.walletPk]),
        ),
        builder: (context, snap) => FutureBuilder<double>(
          future: _need(),
          builder: (context, needSnap) {
            double balance = snap.data?.total ?? 0;
            double need = needSnap.data ?? 0;
            return Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 13, vertical: 6),
              child: Tappable(
                color: getColor(context, "lightDarkAccentHeavyLight"),
                borderRadius: 20,
                onTap: () =>
                    pushRoute(context, WalletDetailsPage(wallet: wallet)),
                child: Padding(
                  padding: const EdgeInsetsDirectional.all(16),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            TextFont(
                                text: wallet.name,
                                fontSize: 18,
                                fontWeight: FontWeight.w600,
                                maxLines: 2),
                            if (need > 0) ...[
                              SizedBox(height: 4),
                              TextFont(
                                text: "нужно добавить " + money(need),
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                textColor: getColor(context, "expenseAmount"),
                                maxLines: 2,
                              ),
                            ],
                          ],
                        ),
                      ),
                      SizedBox(width: 12),
                      TextFont(
                        text: money(balance),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        maxLines: 1,
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
