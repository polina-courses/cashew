// Локальная версия: экран «Пополнить счета категорий».
// Деньги приходят на общий счёт; здесь они раскладываются по счетам категорий
// (Дети, Продукты…) по приоритетам подгрупп: зарплата закрывает 2/3 потребности,
// аванс — всё оставшееся. Кнопка делает переводы и раскладку по подгруппам.

import 'package:budget/colors.dart';
import 'package:budget/database/envelopePlanStore.dart';
import 'package:budget/database/envelopes.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addWalletPage.dart';
import 'package:budget/struct/categoryAccounts.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/envelopePlan.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/envelopes.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/globalSnackbar.dart';
import 'package:budget/widgets/openSnackbar.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

class _TopUpAccount {
  _TopUpAccount(this.wallet, this.balances, this.lines, this.suggested);
  final TransactionWallet wallet;
  final EnvelopeBalances balances;
  final List<PlanLine> lines;
  final Map<String, double> suggested; // по подгруппам
  double get suggestedTotal => suggested.values.fold(0.0, (a, b) => a + b);
  double get need => lines.fold(0.0, (a, l) => a + l.need);
}

Future openTopUpSheet(BuildContext context,
    {TransactionWallet? source, double? incomeAmount}) async {
  List<TransactionWallet> all = await database.getAllWallets();
  TransactionWallet? from = source;
  if (from == null) {
    for (TransactionWallet w in all) {
      if (w.walletPk == appStateSettings["selectedWalletPk"]) from = w;
    }
  }
  if (from == null) return;
  List<TransactionWallet> targets = (await getCategoryWallets())
      .where((w) => w.walletPk != from!.walletPk)
      .toList();
  if (targets.isEmpty) {
    openSnackbar(SnackbarMessage(
      title: "Пока нет счетов категорий",
      description: "Они появятся сами, когда вы добавите расход в категории.",
      icon: Icons.info_outline_rounded,
    ));
    return;
  }
  EnvelopeBalances fromBalances =
      await database.getEnvelopeBalances(from.walletPk);
  double available = incomeAmount ?? fromBalances.walletTotal;
  if (available < 0) available = 0;

  List<EnvelopeBalances> balancesList = [];
  List<List<PlanLine>> linesList = [];
  for (TransactionWallet w in targets) {
    await database.prepareEnvelopes(w.walletPk);
    EnvelopeBalances b = await database.getEnvelopeBalances(w.walletPk);
    Map<String, ScheduledInfo> scheduled =
        await getScheduledForMonth(database, w.walletPk);
    balancesList.add(b);
    linesList.add(planLinesOf(b, scheduled));
  }
  PlanResult result = planDeposit(
    lines: [for (List<PlanLine> l in linesList) ...l],
    deposit: available,
    share: receiptShare(DateTime.now()),
    decimals: from.decimals,
  );
  List<_TopUpAccount> accounts = [
    for (int i = 0; i < targets.length; i++)
      _TopUpAccount(targets[i], balancesList[i], linesList[i], {
        for (PlanLine l in linesList[i]) l.pk: result.amounts[l.pk] ?? 0,
      }),
  ];
  return openBottomSheet(
    context,
    _TopUpSheet(
      from: from,
      available: available,
      accounts: accounts,
      shortfall: result.shortfall,
    ),
    popupWithKeyboard: true,
    fullSnap: true,
  );
}

class _TopUpSheet extends StatefulWidget {
  const _TopUpSheet({
    required this.from,
    required this.available,
    required this.accounts,
    required this.shortfall,
  });
  final TransactionWallet from;
  final double available;
  final List<_TopUpAccount> accounts;
  final double shortfall;

  @override
  State<_TopUpSheet> createState() => _TopUpSheetState();
}

class _TopUpSheetState extends State<_TopUpSheet> {
  late Map<String, TextEditingController> controllers = {
    for (_TopUpAccount a in widget.accounts)
      a.wallet.walletPk: TextEditingController(
          text: a.suggestedTotal <= 0
              ? ""
              : formatNumberForInput(a.suggestedTotal, decimals)),
  };
  bool saving = false;

  int get decimals => widget.from.decimals;

  @override
  void dispose() {
    for (TextEditingController c in controllers.values) c.dispose();
    super.dispose();
  }

  double amountOf(_TopUpAccount a) =>
      roundToDecimals(
          parseEnvelopeNumber(controllers[a.wallet.walletPk]!.text) ?? 0,
          decimals);

  double get total =>
      widget.accounts.fold(0.0, (sum, a) => sum + max0(amountOf(a)));

  double max0(double v) => v < 0 ? 0 : v;

  Future<void> save() async {
    if (saving || total <= 0 || total > widget.available + 0.005) return;
    setState(() => saving = true);
    for (_TopUpAccount a in widget.accounts) {
      double amount = max0(amountOf(a));
      if (amount <= 0) continue;
      DateTime now = DateTime.now();
      String note = "Пополнение счёта категории\n" +
          widget.from.name +
          " → " +
          a.wallet.name;
      String? toPk = await createCorrectionTransaction(
        amount,
        a.wallet,
        note: note,
        dateTime: now.add(Duration(seconds: 1)),
        title: a.wallet.name + " " + "transfer-in".tr(),
      );
      await createCorrectionTransaction(
        -amount,
        widget.from,
        note: note,
        dateTime: now,
        pairedTransactionFk: toPk,
        title: widget.from.name + " " + "transfer-out".tr(),
      );
      // Раскладка по подгруппам пропорционально предложенному
      double suggested = a.suggestedTotal;
      if (suggested > 0) {
        double factor = amount / suggested;
        double used = 0;
        Map<String, double> parts = {};
        for (MapEntry<String, double> e in a.suggested.entries) {
          double part = roundToDecimals(e.value * factor, decimals);
          if (used + part > amount) part = roundToDecimals(amount - used, decimals);
          if (part > 0) {
            parts[e.key] = part;
            used += part;
          }
        }
        await database.distributeToEnvelopes(
            walletPk: a.wallet.walletPk, amounts: parts);
      }
    }
    if (mounted) popRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    bool over = total > widget.available + 0.005;
    return PopupFramework(
      title: "Пополнить счета категорий",
      subtitle: widget.from.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFont(
            text: "Есть на счёте: " +
                envelopeMoney(context, widget.from, widget.available),
            fontSize: 14,
            textColor: getColor(context, "textLight"),
          ),
          SizedBox(height: 10),
          for (_TopUpAccount a in widget.accounts)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFont(
                            text: a.wallet.name, fontSize: 16, maxLines: 1),
                        TextFont(
                          text: a.need > 0
                              ? "Нужно добавить: " +
                                  envelopeMoney(context, a.wallet, a.need)
                              : "Пополнение не нужно",
                          fontSize: 12,
                          textColor: getColor(context, "textLight"),
                        ),
                        for (PlanLine line in a.lines.where((l) =>
                            (a.suggested[l.pk] ?? 0) > 0))
                          TextFont(
                            text: "  " +
                                a.balances.envelopes
                                    .firstWhere((e) => e.envelopePk == line.pk)
                                    .name +
                                ": " +
                                envelopeMoney(
                                    context, a.wallet, a.suggested[line.pk]!),
                            fontSize: 12,
                            maxLines: 1,
                            textColor: getColor(context, "textLight"),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextInput(
                      labelText: "Перевести",
                      controller: controllers[a.wallet.walletPk],
                      padding: EdgeInsetsDirectional.zero,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
            ),
          if (widget.shortfall > 0)
            TextFont(
              text: "Не хватает " +
                  envelopeMoney(context, widget.from, widget.shortfall) +
                  " до потребностей на этот месяц",
              fontSize: 14,
              maxLines: 2,
              textColor: getColor(context, "expenseAmount"),
            ),
          TextFont(
            text: over
                ? "Переводите больше, чем есть: " +
                    envelopeMoney(context, widget.from, total)
                : "Всего переводим: " +
                    envelopeMoney(context, widget.from, total),
            fontSize: 14,
            maxLines: 2,
            textColor: over
                ? getColor(context, "expenseAmount")
                : getColor(context, "textLight"),
          ),
          SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: Button(
                  label: "Не сейчас",
                  expandedLayout: true,
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  textColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  onTap: () => popRoute(context),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Button(
                  label: "Перевести",
                  expandedLayout: true,
                  disabled: over || total <= 0 || saving,
                  onTap: save,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
