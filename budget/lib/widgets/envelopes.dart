// Локальная версия: подгруппы счёта («конверты») — интерфейс.

import 'dart:math';
import 'package:budget/colors.dart';
import 'package:budget/database/envelopePlanStore.dart';
import 'package:budget/database/envelopes.dart';
import 'package:budget/struct/envelopePlan.dart';
import 'package:budget/struct/envelopeCard.dart';
import 'package:budget/struct/categoryAccounts.dart';
import 'package:budget/widgets/designTokens.dart';
import 'package:budget/widgets/categoryTopUp.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/widgets/util/showDatePicker.dart';
import 'package:drift/drift.dart' show Value;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// ---------------------------------------------------------------------------
// Общие помощники

double? parseEnvelopeNumber(String text) {
  String cleaned = text
      .replaceAll(" ", "")
      .replaceAll(" ", "")
      .replaceAll("%", "")
      .replaceAll(",", ".")
      .trim();
  if (cleaned.isEmpty) return 0;
  return double.tryParse(cleaned);
}

double roundToDecimals(double value, int decimals) {
  double factor = 1;
  for (int i = 0; i < decimals; i++) factor *= 10;
  return (value * factor).roundToDouble() / factor;
}

String formatNumberForInput(double value, int decimals) {
  double rounded = roundToDecimals(value, decimals);
  if (rounded == rounded.roundToDouble()) return rounded.round().toString();
  return rounded.toStringAsFixed(decimals);
}

String envelopeMoney(BuildContext context, TransactionWallet wallet,
    double amount) {
  return convertToMoney(
    Provider.of<AllWallets>(context, listen: false),
    amount,
    currencyKey: wallet.currency,
    decimals: wallet.decimals,
  );
}

Color envelopeAmountColor(BuildContext context, double amount) {
  if (amount < 0) return getColor(context, "expenseAmount");
  return getColor(context, "black");
}

// ---------------------------------------------------------------------------
// Цель подгруппы: сумма и/или дата, расчёт рекомендуемого пополнения

class EnvelopeGoal {
  EnvelopeGoal({
    required this.targetAmount,
    required this.targetDate,
    required this.balance,
  });
  final double? targetAmount;
  final DateTime? targetDate;
  final double balance;

  bool get hasGoal => targetAmount != null || targetDate != null;
  bool get hasAmount => targetAmount != null && targetAmount! > 0;

  double get remaining {
    if (!hasAmount) return 0;
    double left = targetAmount! - balance;
    return left > 0 ? left : 0;
  }

  bool get reached => hasAmount && remaining <= 0;

  double get progress {
    if (!hasAmount) return 0;
    double value = balance / targetAmount!;
    if (value < 0) return 0;
    if (value > 1) return 1;
    return value;
  }

  /// Дней до даты (сегодня = 0). null — дата не задана.
  int? get daysLeft {
    if (targetDate == null) return null;
    DateTime now = DateTime.now();
    DateTime today = DateTime(now.year, now.month, now.day);
    DateTime target =
        DateTime(targetDate!.year, targetDate!.month, targetDate!.day);
    return target.difference(today).inDays;
  }

  /// Сколько месяцев осталось (не меньше 1), если до даты больше месяца.
  int? get monthsLeft {
    int? days = daysLeft;
    if (days == null || days < 31) return null;
    int months = (days / 30.4375).round();
    return months < 1 ? 1 : months;
  }

  /// Рекомендуемое пополнение в месяц.
  double? get monthlyRecommended {
    if (!hasAmount || reached) return null;
    int? months = monthsLeft;
    if (months == null) return null;
    return remaining / months;
  }
}

EnvelopeGoal envelopeGoalOf(Envelope envelope, double balance) {
  return EnvelopeGoal(
    targetAmount: envelope.targetAmount,
    targetDate: envelope.targetDate,
    balance: balance,
  );
}

String envelopeDate(DateTime date) {
  return getWordedDateShort(date, includeYear: true, showTodayTomorrow: false);
}

/// Строка прогресса: «6 000 из 9 000 · к 20 янв. 2027 г.»
String? envelopeGoalProgressText(
    BuildContext context, TransactionWallet wallet, EnvelopeGoal goal) {
  if (!goal.hasGoal) return null;
  List<String> parts = [];
  if (goal.hasAmount) {
    parts.add(envelopeMoney(context, wallet, goal.balance) +
        " из " +
        envelopeMoney(context, wallet, goal.targetAmount!));
  }
  if (goal.targetDate != null) {
    parts.add("к " + envelopeDate(goal.targetDate!));
  }
  return parts.join(" · ");
}

/// Подсказка: сколько откладывать, достигнута ли цель, не прошёл ли срок.
String? envelopeGoalHintText(
    BuildContext context, TransactionWallet wallet, EnvelopeGoal goal) {
  if (!goal.hasAmount) return null;
  if (goal.reached) return "Цель достигнута";
  String remaining = envelopeMoney(context, wallet, goal.remaining);
  int? days = goal.daysLeft;
  if (days == null) return "Осталось накопить " + remaining;
  if (days < 0) return "Срок прошёл, не хватает " + remaining;
  if (days == 0) return "Срок сегодня, не хватает " + remaining;
  double? monthly = goal.monthlyRecommended;
  if (monthly == null) {
    return "До даты " + days.toString() + " дн., нужно ещё " + remaining;
  }
  return "Откладывайте ≈ " +
      envelopeMoney(context, wallet, monthly) +
      " в месяц (осталось " +
      goal.monthsLeft.toString() +
      " мес.)";
}

Color envelopeGoalHintColor(BuildContext context, EnvelopeGoal goal) {
  if (goal.reached) return getColor(context, "incomeAmount");
  int? days = goal.daysLeft;
  if (days != null && days <= 0) return getColor(context, "expenseAmount");
  return getColor(context, "textLight");
}

// ---------------------------------------------------------------------------
// Блок на странице счёта

class WalletEnvelopesSection extends StatelessWidget {
  const WalletEnvelopesSection({required this.wallet, super.key});
  final TransactionWallet wallet;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EnvelopeBalances>(
      stream: database.watchEnvelopeBalances(wallet.walletPk),
      builder: (context, snapshot) {
        EnvelopeBalances? data = snapshot.data;
        if (data == null) return SizedBox.shrink();
        // денег на счёте меньше, чем в подгруппах (например, обнулили счёт)
        if (data.free < -0.005) {
          Future.microtask(
              () => database.shrinkEnvelopesToWallet(wallet.walletPk));
        } else if (data.free > 0.005) {
          // деньги вернулись на счёт: возвращаем ранее снятое с подгрупп
          Future.microtask(
              () => database.restoreShrunkEnvelopes(wallet.walletPk));
        }
        return Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 13),
          child: data.envelopes.isEmpty
              ? _sectionCard(
                  context,
                  _EmptyEnvelopes(wallet: wallet),
                  padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 15, vertical: 12),
                )
              : _EnvelopesList(wallet: wallet, data: data),
        );
      },
    );
  }
}

/// Белая карточка секции (как в макете: скругление 20).
Widget _sectionCard(BuildContext context, Widget child,
    {EdgeInsetsGeometry padding =
        const EdgeInsetsDirectional.symmetric(horizontal: 16, vertical: 4)}) {
  return Container(
    decoration: BoxDecoration(
      color: getColor(context, "lightDarkAccentHeavyLight"),
      boxShadow: boxShadowCheck(boxShadowGeneral(context)),
      borderRadius: BorderRadiusDirectional.circular(20),
    ),
    padding: padding,
    child: child,
  );
}

String envelopeDayMonth(DateTime date) {
  return getWordedDateShort(date, includeYear: false, showTodayTomorrow: false);
}

class _EmptyEnvelopes extends StatelessWidget {
  const _EmptyEnvelopes({required this.wallet});
  final TransactionWallet wallet;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        TextFont(
          text: "Подгруппы счёта",
          fontSize: 18,
          fontWeight: FontWeight.bold,
        ),
        SizedBox(height: 5),
        TextFont(
          text:
              "Разделите деньги счёта на части: например, корм, лекарства, игрушки. Траты с этого счёта будут списываться из выбранной подгруппы.",
          fontSize: 14,
          maxLines: 5,
          textColor: getColor(context, "textLight"),
        ),
        SizedBox(height: 10),
        Button(
          label: "Добавить подгруппу",
          icon: Icons.add_rounded,
          onTap: () => openEnvelopeEditor(context, wallet: wallet),
        ),
      ],
    );
  }
}

/// Значок приоритета: три столбика, закрашено 3 / 2 / 1.
/// Значок приоритета из трёх столбиков: высокий — красный, средний — жёлтый,
/// низкий — серый; невключённые столбики бледные.
class EnvelopePriorityIcon extends StatelessWidget {
  const EnvelopePriorityIcon(this.priority, {super.key});
  final EnvelopePriority priority;

  @override
  Widget build(BuildContext context) {
    int level = priorityLevel(priority);
    Color on = AppTokens.priorityColor(priority);
    Color off = getColor(context, "textLight").withOpacity(0.25);
    List<double> heights = [7, 12, 17];
    return Tooltip(
      message: "Приоритет: " + envelopePriorityLabel(priority).toLowerCase(),
      child: SizedBox(
        width: 22,
        height: 22,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            for (int i = 0; i < 3; i++)
              Padding(
                padding: EdgeInsetsDirectional.only(end: i < 2 ? 3 : 0),
                child: Container(
                  width: 4,
                  height: heights[i],
                  decoration: BoxDecoration(
                    color: i < level ? on : off,
                    borderRadius: BorderRadius.circular(1),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.label, this.value);
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsetsDirectional.only(end: 6),
      padding: const EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.secondaryContainer.withOpacity(0.7),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextFont(
              text: label + " ",
              fontSize: 12,
              textColor: getColor(context, "textLight")),
          TextFont(text: value, fontSize: 12, fontWeight: FontWeight.bold),
        ],
      ),
    );
  }
}

/// Компактно: 📅 лежит / нужно → не хватает (красным), ниже ЗП и аванс.
class EnvelopeNeedLines extends StatelessWidget {
  const EnvelopeNeedLines({required this.wallet, required this.line, super.key});
  final TransactionWallet wallet;
  final PlanLine line;

  @override
  Widget build(BuildContext context) {
    double required = line.scheduled + line.longRequired + line.goalRequired;
    if (required <= 0 && line.wish <= 0) return SizedBox.shrink();
    Color light = getColor(context, "textLight");
    String money(double v) => envelopeMoney(context, wallet, v);
    if (required <= 0) {
      // цель без срока: копим по возможности
      return Padding(
        padding: const EdgeInsetsDirectional.only(top: 4),
        child: Row(children: [
          Icon(Icons.savings_outlined, size: 14, color: light),
          SizedBox(width: 5),
          TextFont(
              text: "осталось " + money(line.wish),
              fontSize: 13,
              textColor: light),
        ]),
      );
    }
    var split = splitNeed(line.need, DateTime.now());
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // лежит / нужно (+ галочка, если хватает)
          Row(
            children: [
              Icon(Icons.calendar_month_rounded, size: 14, color: light),
              SizedBox(width: 5),
              Flexible(
                child: TextFont(
                  text: money(max(0.0, line.balance)) + " / " + money(required),
                  fontSize: 13,
                  textColor: light,
                  maxLines: 2,
                ),
              ),
              if (line.need <= 0) ...[
                SizedBox(width: 4),
                Icon(Icons.check_rounded,
                    size: 16, color: getColor(context, "incomeAmount")),
              ],
            ],
          ),
          if (line.need > 0)
            // всё остальное переносится на новые строки, а не налезает
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 4),
              child: Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                runSpacing: 4,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(end: 6),
                    child: Text.rich(
                      TextSpan(children: [
                        TextSpan(
                          text: "пополнить на ",
                          style: TextStyle(
                              fontSize: 13,
                              fontStyle: FontStyle.italic,
                              color: light.withOpacity(0.7)),
                        ),
                        TextSpan(
                          text: money(line.need),
                          style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.bold,
                              color: getColor(context, "expenseAmount")),
                        ),
                      ]),
                    ),
                  ),
                  if (DateTime.now().day > 25)
                    _Chip("Сейчас", money(line.need))
                  else ...[
                    if (split.$1 > 0) _Chip("ЗП", money(split.$1)),
                    _Chip("Ав", money(split.$2)),
                  ],
                  if (line.accrualDue != null)
                    TextFont(
                      text: "до " + envelopeDate(line.accrualDue!),
                      fontSize: 12,
                      textColor: light,
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _CategoryHeader extends StatelessWidget {
  const _CategoryHeader(
      {required this.wallet, required this.categoryPk, required this.need});
  final TransactionWallet wallet;
  final String? categoryPk;
  final double need;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 10, bottom: 2),
      child: Row(
        children: [
          Expanded(
            child: categoryPk == null
                ? TextFont(
                    text: "Без категории",
                    fontSize: 14,
                    fontWeight: FontWeight.bold,
                    textColor: getColor(context, "textLight"))
                : FutureBuilder<TransactionCategory?>(
                    future: database.getCategoryInstanceOrNull(categoryPk!),
                    builder: (context, snapshot) => TextFont(
                      text: snapshot.data?.name ?? "",
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      textColor: getColor(context, "textLight"),
                    ),
                  ),
          ),
          if (need > 0)
            TextFont(
              text: "нужно " + envelopeMoney(context, wallet, need),
              fontSize: 12,
              fontWeight: FontWeight.bold,
              textColor: getColor(context, "expenseAmount"),
            ),
        ],
      ),
    );
  }
}

/// Сводка вверху счёта: сколько лежит и сколько нужно добавить (с ЗП и аванса).
class _NeedSummary extends StatelessWidget {
  const _NeedSummary(
      {required this.wallet, required this.total, required this.need});
  final TransactionWallet wallet;
  final double total;
  final double need;

  String shareLabel(PayShare share) {
    switch (share.kind) {
      case PayKind.salary:
        return "С зарплаты, " + envelopeDayMonth(share.date);
      case PayKind.advance:
        return "С аванса, " + envelopeDayMonth(share.date);
      case PayKind.now:
        return "Нужно сейчас";
    }
  }

  @override
  Widget build(BuildContext context) {
    Color light = getColor(context, "textLight");
    String money(double v) => envelopeMoney(context, wallet, v);
    List<PayShare> shares = payShares(need, DateTime.now());
    Widget needBox;
    if (need > 0.005) {
      needBox = Container(
        decoration: BoxDecoration(
          color: AppTokens.danger.withOpacity(0.10),
          borderRadius: BorderRadius.circular(14),
        ),
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: TextFont(
                    text: "Нужно добавить",
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    textColor: getColor(context, "expenseAmount"),
                  ),
                ),
                SizedBox(width: 12),
                TextFont(
                  text: money(need),
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  maxLines: 1,
                  textColor: getColor(context, "expenseAmount"),
                ),
              ],
            ),
            SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (int i = 0; i < 2; i++) ...[
                  if (i == 1) SizedBox(width: 8),
                  Expanded(
                    child: i < shares.length
                        ? Container(
                            decoration: BoxDecoration(
                              color:
                                  getColor(context, "lightDarkAccentHeavyLight"),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            padding: const EdgeInsetsDirectional.symmetric(
                                horizontal: 10, vertical: 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                TextFont(
                                  text: shareLabel(shares[i]),
                                  fontSize: 13,
                                  maxLines: 2,
                                  textColor: light,
                                ),
                                SizedBox(height: 2),
                                TextFont(
                                  text: money(shares[i].amount),
                                  fontSize: 17,
                                  fontWeight: FontWeight.w600,
                                  maxLines: 1,
                                ),
                              ],
                            ),
                          )
                        : SizedBox.shrink(),
                  ),
                ],
              ],
            ),
          ],
        ),
      );
    } else {
      needBox = Container(
        decoration: BoxDecoration(
          color: AppTokens.accent.withOpacity(0.12),
          borderRadius: BorderRadius.circular(14),
        ),
        padding:
            const EdgeInsetsDirectional.symmetric(horizontal: 14, vertical: 12),
        child: Row(
          children: [
            Icon(Icons.check_rounded,
                size: 20, color: getColor(context, "incomeAmount")),
            SizedBox(width: 8),
            Expanded(
              child: TextFont(
                text: "На этот месяц денег хватает",
                fontSize: 15,
                fontWeight: FontWeight.w600,
                maxLines: 2,
                textColor: getColor(context, "incomeAmount"),
              ),
            ),
          ],
        ),
      );
    }
    return _sectionCard(
      context,
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFont(
              text: "На счёте сейчас",
              fontSize: 14,
              textAlign: TextAlign.start,
              textColor: light),
          SizedBox(height: 4),
          TextFont(
            text: money(total),
            fontSize: 34,
            fontWeight: FontWeight.bold,
            textAlign: TextAlign.start,
            maxLines: 1,
          ),
          SizedBox(height: 16),
          needBox,
        ],
      ),
      padding: const EdgeInsetsDirectional.all(20),
    );
  }
}

/// Одна подгруппа: значок приоритета, название слева (до двух строк), сумма
/// справа; ниже полоска, короткая строка и доли ЗП / аванс.
class _EnvelopeRow extends StatelessWidget {
  const _EnvelopeRow({
    required this.wallet,
    required this.envelope,
    required this.line,
    required this.balance,
    required this.showTopBorder,
  });
  final TransactionWallet wallet;
  final Envelope envelope;
  final PlanLine line;
  final double balance;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context) {
    Color light = getColor(context, "textLight");
    String money(double v) => envelopeMoney(context, wallet, v);
    EnvelopePriority priority = getEnvelopePriority(envelope.envelopePk);
    EnvelopeGoal goal = envelopeGoalOf(envelope, balance);
    EnvelopeCardInfo info =
        envelopeCardInfo(line, targetAmount: envelope.targetAmount);

    // короткая строка-пояснение
    String? note;
    String own = (envelope.note ?? "").trim();
    if (own.isNotEmpty) {
      note = own;
    } else if (goal.hasGoal) {
      List<String> parts = [];
      if (goal.hasAmount) parts.add("цель " + money(goal.targetAmount!));
      if (goal.targetDate != null) {
        parts.add("к " + envelopeDate(goal.targetDate!));
      }
      note = parts.join(" ");
    } else if (line.accrualDue != null) {
      note = "копим до " + envelopeDate(line.accrualDue!);
    } else if (info.required > 0) {
      note = "в этом месяце нужно " + money(info.required);
    } else if (line.wish > 0) {
      note = "копим по возможности";
    }
    if (envelope.percent > 0) {
      String share = "доля " + formatNumberForInput(envelope.percent, 1) + "%";
      note = note == null ? share : note + " · " + share;
    }

    // состояние справа от пояснения
    String stateText = "";
    Color stateColor = light;
    switch (info.state) {
      case EnvelopeCardState.short:
        stateText = "ещё " + money(info.amount);
        stateColor = getColor(context, "expenseAmount");
        break;
      case EnvelopeCardState.enough:
        stateText = "хватает";
        stateColor = getColor(context, "incomeAmount");
        break;
      case EnvelopeCardState.saving:
        double? monthly = goal.monthlyRecommended;
        stateText = monthly != null
            ? money(monthly) + " в месяц"
            : "осталось " + money(max(0.0, info.amount - balance));
        stateColor = getColor(context, "black");
        break;
      case EnvelopeCardState.none:
        break;
    }

    Color barColor = info.state == EnvelopeCardState.enough
        ? AppTokens.accent
        : AppTokens.priorityColor(priority);
    List<PayShare> shares = payShares(line.need, DateTime.now());

    return Container(
      decoration: BoxDecoration(
        border: showTopBorder
            ? Border(
                top: BorderSide(
                    color: Theme.of(context).dividerColor.withOpacity(0.5)))
            : null,
      ),
      child: Tappable(
        color: Colors.transparent,
        borderRadius: 10,
        onTap: () =>
            openEnvelopeEditor(context, wallet: wallet, envelope: envelope),
        child: Padding(
          padding: const EdgeInsetsDirectional.symmetric(vertical: 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsetsDirectional.only(top: 1),
                    child: EnvelopePriorityIcon(priority),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    child: TextFont(
                      text: envelope.name,
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      textAlign: TextAlign.start,
                      maxLines: 2,
                    ),
                  ),
                  if (isTemporaryEnvelope(envelope.envelopePk))
                    Padding(
                      padding: const EdgeInsetsDirectional.only(start: 6),
                      child: Tooltip(
                        message: "Временная, пока есть платежи",
                        child: Icon(Icons.hourglass_bottom_rounded,
                            size: 14, color: light),
                      ),
                    ),
                  SizedBox(width: 10),
                  TextFont(
                    text: money(balance),
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    maxLines: 1,
                    textColor: envelopeAmountColor(context, balance),
                  ),
                ],
              ),
              SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: info.progress,
                  minHeight: 8,
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  color: barColor,
                ),
              ),
              if (note != null || stateText.isNotEmpty) ...[
                SizedBox(height: 8),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: TextFont(
                        text: note ?? "",
                        fontSize: 14,
                        textAlign: TextAlign.start,
                        maxLines: 2,
                        textColor: light,
                      ),
                    ),
                    if (stateText.isNotEmpty) ...[
                      SizedBox(width: 12),
                      TextFont(
                        text: stateText,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        maxLines: 1,
                        textColor: stateColor,
                      ),
                    ],
                  ],
                ),
              ],
              if (shares.isNotEmpty) ...[
                SizedBox(height: 8),
                Row(
                  children: [
                    for (int i = 0; i < 2; i++) ...[
                      if (i == 1) SizedBox(width: 8),
                      Expanded(
                        child: i < shares.length
                            ? Container(
                                decoration: BoxDecoration(
                                  color: Theme.of(context)
                                      .colorScheme
                                      .secondaryContainer
                                      .withOpacity(0.5),
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: const EdgeInsetsDirectional.symmetric(
                                    horizontal: 10, vertical: 6),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    TextFont(
                                      text: shares[i].kind == PayKind.salary
                                          ? "ЗП"
                                          : shares[i].kind == PayKind.advance
                                              ? "Аванс"
                                              : "Сейчас",
                                      fontSize: 13,
                                      textColor: light,
                                    ),
                                    SizedBox(width: 6),
                                    TextFont(
                                      text: money(shares[i].amount),
                                      fontSize: 15,
                                      fontWeight: FontWeight.w600,
                                      maxLines: 1,
                                    ),
                                  ],
                                ),
                              )
                            : SizedBox.shrink(),
                      ),
                    ],
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _EnvelopesList extends StatelessWidget {
  const _EnvelopesList({required this.wallet, required this.data});
  final TransactionWallet wallet;
  final EnvelopeBalances data;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Map<String, ScheduledInfo>>(
      future: getScheduledForMonth(database, wallet.walletPk),
      builder: (context, snapshot) =>
          buildList(context, snapshot.data ?? <String, ScheduledInfo>{}),
    );
  }

  Widget buildList(BuildContext context, Map<String, ScheduledInfo> scheduled) {
    List<PlanLine> lines = planLinesOf(data, scheduled);
    PlanLine lineOf(Envelope e) => lines.firstWhere((l) => l.pk == e.envelopePk);
    double totalNeed =
        lines.fold<double>(0, (double sum, PlanLine l) => sum + l.need);
    // Подгруппы по категориям: сначала сгруппированные, затем без категории
    List<String?> categoryOrder = [];
    for (Envelope e in data.envelopes) {
      String? c = getEnvelopeCategoryPk(e.envelopePk);
      if (!categoryOrder.contains(c)) categoryOrder.add(c);
    }
    categoryOrder.sort((a, b) => (a == null ? 1 : 0) - (b == null ? 1 : 0));
    List<Envelope> sorted = [
      for (String? c in categoryOrder)
        ...data.envelopes
            .where((e) => getEnvelopeCategoryPk(e.envelopePk) == c)
    ];
    // заголовки категорий нужны, только если категорий несколько
    bool manyCategories = categoryOrder.length > 1;
    List<Widget> rows = [];
    for (int i = 0; i < sorted.length; i++) {
      Envelope envelope = sorted[i];
      String? category = getEnvelopeCategoryPk(envelope.envelopePk);
      bool firstOfCategory = sorted.indexWhere(
              (e) => getEnvelopeCategoryPk(e.envelopePk) == category) ==
          i;
      if (manyCategories && firstOfCategory) {
        rows.add(_CategoryHeader(
          wallet: wallet,
          categoryPk: category,
          need: sorted
              .where((e) => getEnvelopeCategoryPk(e.envelopePk) == category)
              .fold<double>(0, (sum, e) => sum + lineOf(e).need),
        ));
      }
      rows.add(_EnvelopeRow(
        wallet: wallet,
        envelope: envelope,
        line: lineOf(envelope),
        balance: data.balanceOf(envelope.envelopePk),
        showTopBorder: i > 0 && !(manyCategories && firstOfCategory),
      ));
    }
    Color light = getColor(context, "textLight");
    String mainPk = mainWalletPk(
        Provider.of<AllWallets>(context, listen: false).list);
    bool canTopUp = totalNeed > 0.005 && wallet.walletPk != mainPk;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _NeedSummary(
            wallet: wallet, total: data.walletTotal, need: totalNeed),
        SizedBox(height: 16),
        Padding(
          padding: const EdgeInsetsDirectional.symmetric(horizontal: 4),
          child: Row(
            children: [
              Expanded(
                child: TextFont(
                  text: "Подгруппы",
                  fontSize: 17,
                  fontWeight: FontWeight.w600,
                  textAlign: TextAlign.start,
                ),
              ),
              Tappable(
                color: AppTokens.accentSoft,
                borderRadius: 12,
                onTap: () => openEnvelopeEditor(context, wallet: wallet),
                child: Container(
                  height: 40,
                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 14),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.add_rounded,
                          size: 18, color: AppTokens.accentDark),
                      SizedBox(width: 6),
                      TextFont(
                        text: "Добавить",
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        textColor: AppTokens.accentDark,
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        SizedBox(height: 10),
        _sectionCard(
          context,
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...rows,
              Tappable(
                color: Colors.transparent,
                borderRadius: 10,
                onTap: () => openBottomSheet(
                    context, EnvelopeArchiveSheet(wallet: wallet),
                    popupWithKeyboard: false),
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
                  child: TextFont(
                    text: "Архив подгрупп",
                    fontSize: 14,
                    textAlign: TextAlign.start,
                    textColor: light,
                  ),
                ),
              ),
              Divider(height: 1),
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(vertical: 12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFont(
                        text: "Свободно",
                        fontSize: 16,
                        textAlign: TextAlign.start,
                        textColor: light,
                      ),
                    ),
                    TextFont(
                      text: envelopeMoney(context, wallet, data.free),
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      maxLines: 1,
                      textColor: envelopeAmountColor(context, data.free),
                    ),
                  ],
                ),
              ),
              if (data.percentTotal > 100.0001)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 12),
                  child: TextFont(
                    text: "Сумма долей больше 100% (" +
                        formatNumberForInput(data.percentTotal, 1) +
                        "%). Поправьте доли подгрупп.",
                    fontSize: 13,
                    maxLines: 3,
                    textAlign: TextAlign.start,
                    textColor: getColor(context, "expenseAmount"),
                  ),
                ),
            ],
          ),
        ),
        SizedBox(height: 16),
        if (canTopUp) ...[
          Tappable(
            color: AppTokens.accent,
            borderRadius: 16,
            onTap: () => openTopUpSheet(context),
            child: Container(
              height: 52,
              alignment: Alignment.center,
              child: TextFont(
                text: "Пополнить на " + envelopeMoney(context, wallet, totalNeed),
                fontSize: 17,
                fontWeight: FontWeight.w600,
                maxLines: 1,
                textColor: Colors.white,
              ),
            ),
          ),
          SizedBox(height: 10),
        ],
        Button(
          label: "Переложить и изменить подгруппы",
          expandedLayout: true,
          onTap: () => openEnvelopeTableSheet(context, wallet: wallet),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Добавление / изменение / удаление подгруппы

Future openEnvelopeEditor(BuildContext context,
    {required TransactionWallet wallet, Envelope? envelope}) {
  return openBottomSheet(
    context,
    EnvelopeEditor(wallet: wallet, envelope: envelope),
    popupWithKeyboard: true,
  );
}

class EnvelopeEditor extends StatefulWidget {
  const EnvelopeEditor({required this.wallet, this.envelope, super.key});
  final TransactionWallet wallet;
  final Envelope? envelope;

  @override
  State<EnvelopeEditor> createState() => _EnvelopeEditorState();
}

class _EnvelopeEditorState extends State<EnvelopeEditor> {
  late TextEditingController nameController =
      TextEditingController(text: widget.envelope?.name ?? "");
  late TextEditingController percentController = TextEditingController(
      text: widget.envelope == null || widget.envelope!.percent == 0
          ? ""
          : formatNumberForInput(widget.envelope!.percent, 1));
  late TextEditingController targetController = TextEditingController(
      text: widget.envelope?.targetAmount == null
          ? ""
          : formatNumberForInput(
              widget.envelope!.targetAmount!, widget.wallet.decimals));
  late DateTime? targetDate = widget.envelope?.targetDate;
  late EnvelopePriority priority = widget.envelope == null
      ? EnvelopePriority.medium
      : getEnvelopePriority(widget.envelope!.envelopePk);
  late TextEditingController noteController =
      TextEditingController(text: widget.envelope?.note ?? "");
  double currentBalance = 0;
  String? error;

  @override
  void initState() {
    super.initState();
    if (widget.envelope != null) {
      database.getEnvelopeBalances(widget.wallet.walletPk).then((balances) {
        if (!mounted) return;
        setState(() {
          currentBalance = balances.balanceOf(widget.envelope!.envelopePk);
        });
      });
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    percentController.dispose();
    targetController.dispose();
    noteController.dispose();
    super.dispose();
  }

  String? get noteText {
    String text = noteController.text.trim();
    return text.isEmpty ? null : text;
  }

  double? get parsedTarget {
    double? value = parseEnvelopeNumber(targetController.text);
    if (value == null || value <= 0) return null;
    return value;
  }

  Future<void> pickTargetDate() async {
    DateTime initial =
        targetDate ?? DateTime.now().add(Duration(days: 30));
    DateTime? picked = await showCustomDatePicker(context, initial);
    if (picked != null) {
      setState(() {
        targetDate = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Future<void> save() async {
    String name = nameController.text.trim();
    double? percent = parseEnvelopeNumber(percentController.text);
    if (name.isEmpty) {
      setState(() => error = "Введите название");
      return;
    }
    if (percent == null || percent < 0 || percent > 100) {
      setState(() => error = "Доля — число от 0 до 100");
      return;
    }
    double? target = parseEnvelopeNumber(targetController.text);
    if (target == null || target < 0) {
      setState(() => error = "Целевая сумма — положительное число");
      return;
    }
    List<Envelope> others = (await database.getEnvelopes(widget.wallet.walletPk))
        .where((e) => e.envelopePk != widget.envelope?.envelopePk)
        .toList();
    double othersPercent = 0;
    for (Envelope e in others) othersPercent += e.percent;
    if (othersPercent + percent > 100.0001) {
      setState(() => error = "Сумма долей будет больше 100%: у остальных уже " +
          formatNumberForInput(othersPercent, 1) +
          "%");
      return;
    }
    String savedPk;
    if (widget.envelope == null) {
      await database.createEnvelope(
        walletPk: widget.wallet.walletPk,
        name: name,
        percent: percent,
        targetAmount: parsedTarget,
        targetDate: targetDate,
        note: noteText,
      );
      savedPk = (await database.getEnvelopes(widget.wallet.walletPk))
          .last
          .envelopePk;
    } else {
      savedPk = widget.envelope!.envelopePk;
      await database.updateEnvelope(widget.envelope!.copyWith(
        name: name,
        percent: percent,
        targetAmount: Value(parsedTarget),
        targetDate: Value(targetDate),
        note: Value(noteText),
      ));
    }
    await setEnvelopePriority(savedPk, priority);
    popRoute(context);
  }

  Future<void> deleteEnvelope() async {
    Envelope envelope = widget.envelope!;
    EnvelopeBalances balances =
        await database.getEnvelopeBalances(widget.wallet.walletPk);
    double balance = balances.balanceOf(envelope.envelopePk);
    bool? confirmed = await openPopup<bool>(
      context,
      title: "Удалить «${envelope.name}»?",
      description: (balance != 0
              ? "Остаток " +
                  envelopeMoney(context, widget.wallet, balance) +
                  " вернётся в свободные деньги счёта. "
              : "") +
          "Траты из этой подгруппы останутся, но без подгруппы.",
      icon: Icons.delete_outline_rounded,
      onSubmitLabel: "Удалить",
      onSubmit: () => popRoute(context, true),
      onCancelLabel: "Отмена",
      onCancel: () => popRoute(context, false),
    );
    if (confirmed != true) return;
    await database.deleteEnvelope(envelope);
    popRoute(context);
  }

  Future<void> archiveThis() async {
    Envelope envelope = widget.envelope!;
    bool? confirmed = await openPopup<bool>(
      context,
      title: "Убрать «${envelope.name}» в архив?",
      description:
          "Остаток вернётся в свободные деньги. Неоплаченные платежи останутся в календаре без подгруппы, прошлые траты сохранятся. Из архива подгруппу можно вернуть.",
      icon: Icons.archive_outlined,
      onSubmitLabel: "В архив",
      onSubmit: () => popRoute(context, true),
      onCancelLabel: "Отмена",
      onCancel: () => popRoute(context, false),
    );
    if (confirmed != true) return;
    await database.archiveEnvelope(envelope);
    popRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: widget.envelope == null ? "Новая подгруппа" : "Подгруппа",
      subtitle: widget.wallet.name,
      child: Column(
        children: [
          TextInput(
            labelText: "Название, например «Корм»",
            controller: nameController,
            autoFocus: widget.envelope == null,
            padding: EdgeInsetsDirectional.zero,
            textCapitalization: TextCapitalization.sentences,
          ),
          SizedBox(height: 14),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextFont(
              text: "Приоритет пополнения",
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 6),
          Wrap(
            spacing: 8,
            children: [
              for (EnvelopePriority p in EnvelopePriority.values)
                ChoiceChip(
                  label: Text(envelopePriorityLabel(p)),
                  selected: priority == p,
                  onSelected: (_) => setState(() => priority = p),
                ),
            ],
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: TextFont(
              text:
                  "Платежи подгруппы берутся из календаря: выберите эту подгруппу при добавлении расхода.",
              fontSize: 12,
              maxLines: 3,
              textColor: getColor(context, "textLight"),
            ),
          ),
          SizedBox(height: 10),
          TextInput(
            labelText: "Доля при пополнении, % (необязательно)",
            controller: percentController,
            padding: EdgeInsetsDirectional.zero,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
          ),
          SizedBox(height: 10),
          TextInput(
            labelText: "Заметка (необязательно)",
            controller: noteController,
            padding: EdgeInsetsDirectional.zero,
            minLines: 2,
            maxLines: 6,
            keyboardType: TextInputType.multiline,
            textCapitalization: TextCapitalization.sentences,
          ),
          SizedBox(height: 18),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextFont(
              text: "Цель (необязательно)",
              fontSize: 15,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 8),
          TextInput(
            labelText: "Накопить сумму",
            controller: targetController,
            padding: EdgeInsetsDirectional.zero,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            onChanged: (_) => setState(() {}),
          ),
          SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Button(
                  label: targetDate == null
                      ? "Выбрать дату"
                      : "К дате: " + envelopeDate(targetDate!),
                  icon: Icons.event_rounded,
                  expandedLayout: true,
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  textColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  onTap: pickTargetDate,
                ),
              ),
              if (targetDate != null)
                IconButton(
                  tooltip: "Убрать дату",
                  icon: Icon(Icons.close_rounded),
                  onPressed: () => setState(() => targetDate = null),
                ),
            ],
          ),
          Builder(builder: (context) {
            EnvelopeGoal goal = EnvelopeGoal(
              targetAmount: parsedTarget,
              targetDate: targetDate,
              balance: currentBalance,
            );
            String? hint = envelopeGoalHintText(context, widget.wallet, goal);
            if (hint == null) return SizedBox.shrink();
            return Padding(
              padding: const EdgeInsetsDirectional.only(top: 10),
              child: Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextFont(
                  text: hint,
                  fontSize: 14,
                  maxLines: 3,
                  textColor: envelopeGoalHintColor(context, goal),
                ),
              ),
            );
          }),
          if (error != null)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 10),
              child: TextFont(
                text: error!,
                fontSize: 14,
                maxLines: 3,
                textColor: getColor(context, "expenseAmount"),
              ),
            ),
          SizedBox(height: 15),
          Row(
            children: [
              if (widget.envelope != null) ...[
                Expanded(
                  child: Button(
                    label: "В архив",
                    expandedLayout: true,
                    color: Theme.of(context).colorScheme.secondaryContainer,
                    textColor:
                        Theme.of(context).colorScheme.onSecondaryContainer,
                    onTap: archiveThis,
                  ),
                ),
                SizedBox(width: 8),
                Expanded(
                  child: Button(
                    label: "Удалить",
                    expandedLayout: true,
                    color: Theme.of(context).colorScheme.errorContainer,
                    textColor: Theme.of(context).colorScheme.onErrorContainer,
                    onTap: deleteEnvelope,
                  ),
                ),
                SizedBox(width: 8),
              ],
              Expanded(
                child: Button(
                  label: "Сохранить",
                  expandedLayout: true,
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

// ---------------------------------------------------------------------------
// Распределение денег по подгруппам (пополнение или свободный остаток)

// Подсказки в окне распределения: что уже лежит, сколько нужно и к какому сроку
Widget envelopeDistributeHint(
    BuildContext context, TransactionWallet wallet, EnvelopeGoal goal) {
  List<String> lines = [];
  if (goal.balance != 0 || goal.hasGoal) {
    lines.add("Уже в подгруппе: " + envelopeMoney(context, wallet, goal.balance));
  }
  if (goal.hasAmount) {
    lines.add(goal.reached
        ? "Цель " + envelopeMoney(context, wallet, goal.targetAmount!) + " достигнута"
        : "Нужно всего " +
            envelopeMoney(context, wallet, goal.targetAmount!) +
            ", осталось " +
            envelopeMoney(context, wallet, goal.remaining));
  }
  if (goal.targetDate != null) {
    lines.add("Срок: до " + envelopeDate(goal.targetDate!));
  }
  double? monthly = goal.monthlyRecommended;
  if (lines.isEmpty && monthly == null) return SizedBox.shrink();
  return Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      for (String line in lines)
        TextFont(
          text: line,
          fontSize: 12,
          maxLines: 2,
          textColor: getColor(context, "textLight"),
        ),
      if (monthly != null)
        TextFont(
          text: "Откладывать ≈ " +
              envelopeMoney(context, wallet, monthly) +
              " в месяц",
          fontSize: 12,
          maxLines: 2,
          textColor: Theme.of(context).colorScheme.primary,
        ),
    ],
  );
}

// ---------------------------------------------------------------------------
// Единое окно подгрупп: распределить свободные, переложить, изменить суммы

// Открывает таблицу подгрупп счёта. После пополнения передаём сумму пополнения.
Future openEnvelopeTableSheet(BuildContext context,
    {required TransactionWallet wallet,
    double? incomeAmount,
    String? sourceTransactionPk}) async {
  await database.prepareEnvelopes(wallet.walletPk);
  EnvelopeBalances balances =
      await database.getEnvelopeBalances(wallet.walletPk);
  if (balances.envelopes.isEmpty) return;
  return openBottomSheet(
    context,
    EnvelopeTableSheet(
      wallet: wallet,
      balances: balances,
      incomeAmount: incomeAmount,
      sourceTransactionPk: sourceTransactionPk,
      scheduled: await getScheduledForMonth(database, wallet.walletPk),
    ),
    popupWithKeyboard: true,
    fullSnap: true,
  );
}

// Совместимость: окно после пополнения счёта
Future openDistributeSheet(
  BuildContext context, {
  required TransactionWallet wallet,
  required double amount,
  String? sourceTransactionPk,
  String title = "Распределить пополнение",
}) {
  return openEnvelopeTableSheet(
    context,
    wallet: wallet,
    incomeAmount: amount,
    sourceTransactionPk: sourceTransactionPk,
  );
}

class EnvelopeTableSheet extends StatefulWidget {
  const EnvelopeTableSheet({
    required this.wallet,
    required this.balances,
    this.incomeAmount,
    this.sourceTransactionPk,
    this.scheduled = const {},
    super.key,
  });
  final TransactionWallet wallet;
  final EnvelopeBalances balances;
  final Map<String, ScheduledInfo> scheduled; // платежи календаря на месяц по подгруппам
  final double? incomeAmount;
  final String? sourceTransactionPk;

  @override
  State<EnvelopeTableSheet> createState() => _EnvelopeTableSheetState();
}

class _EnvelopeTableSheetState extends State<EnvelopeTableSheet> {
  late Map<String, double> values; // новые суммы подгрупп
  late Map<String, TextEditingController> controllers;
  double planShortfall = 0;
  bool planApplied = false;

  int get decimals => widget.wallet.decimals;

  double oldOf(Envelope envelope) =>
      roundToDecimals(widget.balances.balanceOf(envelope.envelopePk), decimals);

  List<PlanLine> get planLines =>
      planLinesOf(widget.balances, widget.scheduled);

  bool get hasPlan => planLines.any((l) => l.need > 0 || l.wish > 0);

  // Деньги, которые раскладываем: пополнение или все свободные
  double get amountToSplit {
    double deposit = widget.incomeAmount ?? widget.balances.free;
    return max(0.0, min(deposit, max(0.0, widget.balances.free)));
  }

  // Заполнить суммы по потребности и приоритету (их можно поправить руками)
  void applyPlan() {
    PlanResult result = planDeposit(
      lines: planLines,
      deposit: amountToSplit,
      share: receiptShare(DateTime.now()),
      decimals: decimals,
    );
    setState(() {
      for (Envelope envelope in widget.balances.envelopes) {
        setValue(envelope.envelopePk,
            oldOf(envelope) + (result.amounts[envelope.envelopePk] ?? 0));
      }
      planShortfall = result.shortfall;
      planApplied = true;
    });
  }

  @override
  void initState() {
    super.initState();
    values = {};
    controllers = {};
    for (Envelope envelope in widget.balances.envelopes) {
      double current = oldOf(envelope);
      values[envelope.envelopePk] = current;
      controllers[envelope.envelopePk] = TextEditingController(
          text: current == 0 ? "" : formatNumberForInput(current, decimals));
    }
    // После пополнения сразу подставляем раскладку по плану
    if (widget.incomeAmount != null && hasPlan) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) applyPlan();
      });
    }
  }

  @override
  void dispose() {
    for (TextEditingController controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void setValue(String envelopePk, double value) {
    values[envelopePk] = roundToDecimals(value < 0 ? 0.0 : value, decimals);
    controllers[envelopePk]!.text = values[envelopePk] == 0
        ? ""
        : formatNumberForInput(values[envelopePk]!, decimals);
  }

  void setControllerText(String envelopePk, double value) {
    controllers[envelopePk]!.text =
        value == 0 ? "" : formatNumberForInput(value, decimals);
  }

  // Правка суммы одной подгруппы. Прибавка берётся сначала из свободных денег,
  // остаток — поровну у других подгрупп (кто сколько может отдать). Уменьшение
  // возвращает деньги в свободные. Сумма всех денег счёта не меняется.
  void applyNewValue(String envelopePk, double target,
      {bool updateOwnText = true}) {
    double current = values[envelopePk] ?? 0;
    double wanted = roundToDecimals(max(0.0, target), decimals);
    double delta = roundToDecimals(wanted - current, decimals);
    if (delta <= 0) {
      values[envelopePk] = wanted;
      if (updateOwnText) setControllerText(envelopePk, wanted);
      return;
    }
    double fromFree = min(delta, max(0.0, freeAfter));
    double need = roundToDecimals(delta - fromFree, decimals);
    int guard = 0;
    while (need > 0 && guard < 200) {
      guard++;
      List<String> others = values.keys
          .where((k) => k != envelopePk && (values[k] ?? 0) > 0)
          .toList();
      if (others.isEmpty) break;
      double share = need / others.length;
      for (String other in others) {
        double take = min(share, values[other]!);
        take = roundToDecimals(take, decimals);
        if (take <= 0) continue;
        values[other] = roundToDecimals(values[other]! - take, decimals);
        need = roundToDecimals(need - take, decimals);
        setControllerText(other, values[other]!);
      }
    }
    double actualDelta = roundToDecimals(delta - max(0.0, need), decimals);
    values[envelopePk] = roundToDecimals(current + actualDelta, decimals);
    if (updateOwnText || actualDelta < delta) {
      setControllerText(envelopePk, values[envelopePk]!);
    }
  }

  void onChanged(Envelope envelope, String text) {
    double value = parseEnvelopeNumber(text) ?? 0;
    setState(() {
      applyNewValue(envelope.envelopePk, value, updateOwnText: false);
    });
  }

  // Кнопки «+» и «−»: шаг 100
  void stepValue(Envelope envelope, double step) {
    setState(() {
      double current = values[envelope.envelopePk] ?? 0;
      applyNewValue(envelope.envelopePk, current + step);
    });
  }

  // Заполнить свободные деньги по долям подгрупп
  void fillByPercent() {
    setState(() {
      double free = widget.balances.free;
      for (Envelope envelope in widget.balances.envelopes) {
        setValue(envelope.envelopePk,
            oldOf(envelope) + free * envelope.percent / 100);
      }
    });
  }

  // Свободные деньги после правки: счёт не меняется, меняется только распределение
  double get freeAfter {
    double oldSum = 0;
    double newSum = 0;
    for (Envelope envelope in widget.balances.envelopes) {
      oldSum += oldOf(envelope);
      newSum += values[envelope.envelopePk] ?? 0;
    }
    return roundToDecimals(widget.balances.free + oldSum - newSum, decimals);
  }

  bool get hasChanges {
    for (Envelope envelope in widget.balances.envelopes) {
      if ((values[envelope.envelopePk] ?? 0) != oldOf(envelope)) return true;
    }
    return false;
  }

  // Изменения раскладываем на перемещения: сначала уменьшенные подгруппы отдают деньги
  // увеличенным (переложить), остаток берётся из свободных или возвращается в них.
  Future<void> save() async {
    if (freeAfter < 0 || !hasChanges) return;
    Map<String, double> take = {};
    Map<String, double> give = {};
    for (Envelope envelope in widget.balances.envelopes) {
      double delta = roundToDecimals(
          (values[envelope.envelopePk] ?? 0) - oldOf(envelope), decimals);
      if (delta < 0) take[envelope.envelopePk] = -delta;
      if (delta > 0) give[envelope.envelopePk] = delta;
    }
    for (MapEntry<String, double> receiver in give.entries) {
      double need = receiver.value;
      for (MapEntry<String, double> source in take.entries) {
        if (need <= 0) break;
        double available = source.value;
        if (available <= 0) continue;
        double moved = min(need, available);
        await database.addEnvelopeMove(
          walletPk: widget.wallet.walletPk,
          fromEnvelopePk: source.key,
          toEnvelopePk: receiver.key,
          amount: moved,
        );
        take[source.key] = roundToDecimals(available - moved, decimals);
        need = roundToDecimals(need - moved, decimals);
      }
      if (need > 0) {
        // Остаток — из свободных денег (пополнение или новые деньги)
        await database.addEnvelopeMove(
          walletPk: widget.wallet.walletPk,
          fromEnvelopePk: null,
          toEnvelopePk: receiver.key,
          amount: need,
          sourceTransactionPk: widget.sourceTransactionPk,
        );
      }
    }
    for (MapEntry<String, double> leftover in take.entries) {
      if (leftover.value <= 0) continue;
      // Остаток, который не ушёл в другие подгруппы, возвращаем в свободные
      await database.addEnvelopeMove(
        walletPk: widget.wallet.walletPk,
        fromEnvelopePk: leftover.key,
        toEnvelopePk: null,
        amount: leftover.value,
      );
    }
    popRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    bool overFree = freeAfter < 0;
    bool hasPercents = widget.balances.envelopes.any((e) => e.percent > 0);
    return PopupFramework(
      title: widget.incomeAmount != null
          ? "Пополнение " +
              envelopeMoney(context, widget.wallet, widget.incomeAmount!)
          : "Подгруппы счёта",
      subtitle: widget.wallet.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextFont(
            text: "Свободно сейчас: " +
                envelopeMoney(context, widget.wallet, widget.balances.free),
            fontSize: 14,
            textColor: getColor(context, "textLight"),
          ),
          if (hasPlan) ...[
            SizedBox(height: 8),
            Button(
              label: "Заполнить по календарю и приоритетам",
              expandedLayout: true,
              onTap: applyPlan,
            ),
          ],
          if (planApplied && planShortfall > 0)
            Padding(
              padding: const EdgeInsetsDirectional.only(top: 6),
              child: TextFont(
                text: "Не хватает " +
                    envelopeMoney(context, widget.wallet, planShortfall) +
                    " до потребности на месяц",
                fontSize: 14,
                maxLines: 2,
                textColor: getColor(context, "expenseAmount"),
              ),
            ),
          if (hasPercents) ...[
            SizedBox(height: 8),
            Button(
              label: "Заполнить по долям",
              expandedLayout: true,
              color: Theme.of(context).colorScheme.secondaryContainer,
              textColor: Theme.of(context).colorScheme.onSecondaryContainer,
              onTap: fillByPercent,
            ),
          ],
          SizedBox(height: 10),
          for (Envelope envelope in widget.balances.envelopes)
            Padding(
              padding: const EdgeInsetsDirectional.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFont(text: envelope.name, fontSize: 16, maxLines: 1),
                        TextFont(
                          text: "Сейчас: " +
                              envelopeMoney(
                                  context, widget.wallet, oldOf(envelope)),
                          fontSize: 12,
                          textColor: getColor(context, "textLight"),
                        ),
                        EnvelopeNeedLines(
                            wallet: widget.wallet,
                            line: planLines
                                .firstWhere((l) => l.pk == envelope.envelopePk)),
                        if (envelopeGoalProgressText(
                                context,
                                widget.wallet,
                                envelopeGoalOf(envelope, oldOf(envelope))) !=
                            null)
                          TextFont(
                            text: envelopeGoalProgressText(
                                context,
                                widget.wallet,
                                envelopeGoalOf(envelope, oldOf(envelope)))!,
                            fontSize: 12,
                            maxLines: 2,
                            textColor: getColor(context, "textLight"),
                          ),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  IconButton(
                    tooltip: "Уменьшить на 100",
                    onPressed: () => stepValue(envelope, -100),
                    icon: Icon(Icons.remove_rounded),
                  ),
                  Expanded(
                    flex: 2,
                    child: TextInput(
                      labelText: "Новая сумма",
                      controller: controllers[envelope.envelopePk],
                      padding: EdgeInsetsDirectional.zero,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      onChanged: (text) => onChanged(envelope, text),
                    ),
                  ),
                  IconButton(
                    tooltip: "Увеличить на 100",
                    onPressed: () => stepValue(envelope, 100),
                    icon: Icon(Icons.add_rounded),
                  ),
                ],
              ),
            ),
          SizedBox(height: 5),
          TextFont(
            text: overFree
                ? "Не хватает свободных денег на " +
                    envelopeMoney(context, widget.wallet, -freeAfter)
                : "Останется свободными: " +
                    envelopeMoney(context, widget.wallet, freeAfter),
            fontSize: 15,
            maxLines: 2,
            textColor: overFree
                ? getColor(context, "expenseAmount")
                : getColor(context, "textLight"),
          ),
          SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: Button(
                  label: "Выйти без изменений",
                  expandedLayout: true,
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  textColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  onTap: () => popRoute(context),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Button(
                  label: "Сохранить",
                  expandedLayout: true,
                  disabled: overFree || !hasChanges,
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

// ---------------------------------------------------------------------------
// Перекладывание между подгруппами

Future openEnvelopeTransferSheet(BuildContext context,
    {required TransactionWallet wallet}) {
  return openBottomSheet(
    context,
    EnvelopeTransferSheet(wallet: wallet),
    popupWithKeyboard: true,
  );
}

class EnvelopeTransferSheet extends StatefulWidget {
  const EnvelopeTransferSheet({required this.wallet, super.key});
  final TransactionWallet wallet;

  @override
  State<EnvelopeTransferSheet> createState() => _EnvelopeTransferSheetState();
}

// Ключ «свободных денег» в выпадающих списках
const String freeMoneyKey = "__free__";
// «Новая подгруппа» при создании расхода (создаётся при сохранении)
const String newEnvelopeKey = "__new__";

class _EnvelopeTransferSheetState extends State<EnvelopeTransferSheet> {
  String? fromKey;
  String? toKey;
  TextEditingController amountController = TextEditingController();
  String? error;

  @override
  void dispose() {
    amountController.dispose();
    super.dispose();
  }

  String? keyToPk(String? key) => key == freeMoneyKey ? null : key;

  Future<void> save() async {
    double? amount = parseEnvelopeNumber(amountController.text);
    if (fromKey == null || toKey == null) {
      setState(() => error = "Выберите, откуда и куда переложить");
      return;
    }
    if (fromKey == toKey) {
      setState(() => error = "Выберите разные подгруппы");
      return;
    }
    if (amount == null || amount <= 0) {
      setState(() => error = "Введите сумму больше нуля");
      return;
    }
    await database.addEnvelopeMove(
      walletPk: widget.wallet.walletPk,
      fromEnvelopePk: keyToPk(fromKey),
      toEnvelopePk: keyToPk(toKey),
      amount: amount,
    );
    popRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EnvelopeBalances>(
      stream: database.watchEnvelopeBalances(widget.wallet.walletPk),
      builder: (context, snapshot) {
        EnvelopeBalances? data = snapshot.data;
        List<DropdownMenuItem<String>> items = [
          DropdownMenuItem(
            value: freeMoneyKey,
            child: Text("Свободные" +
                (data == null
                    ? ""
                    : " · " + envelopeMoney(context, widget.wallet, data.free))),
          ),
          if (data != null)
            for (Envelope envelope in data.envelopes)
              DropdownMenuItem(
                value: envelope.envelopePk,
                child: Text(envelope.name +
                    " · " +
                    envelopeMoney(context, widget.wallet,
                        data.balanceOf(envelope.envelopePk))),
              ),
        ];
        return PopupFramework(
          title: "Переложить",
          subtitle: widget.wallet.name,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              DropdownButtonFormField<String>(
                value: fromKey,
                isExpanded: true,
                decoration: InputDecoration(labelText: "Откуда"),
                items: items,
                onChanged: (value) => setState(() => fromKey = value),
              ),
              SizedBox(height: 10),
              DropdownButtonFormField<String>(
                value: toKey,
                isExpanded: true,
                decoration: InputDecoration(labelText: "Куда"),
                items: items,
                onChanged: (value) => setState(() => toKey = value),
              ),
              SizedBox(height: 10),
              TextInput(
                labelText: "Сумма",
                controller: amountController,
                padding: EdgeInsetsDirectional.zero,
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              if (error != null)
                Padding(
                  padding: const EdgeInsetsDirectional.only(top: 10),
                  child: TextFont(
                    text: error!,
                    fontSize: 14,
                    maxLines: 3,
                    textColor: getColor(context, "expenseAmount"),
                  ),
                ),
              SizedBox(height: 15),
              Button(label: "Переложить", onTap: save),
            ],
          ),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Выбор подгруппы при добавлении траты

class SelectEnvelopeChips extends StatelessWidget {
  const SelectEnvelopeChips({
    required this.wallet,
    required this.selectedEnvelopePk,
    required this.onSelected,
    required this.editingTransaction,
    this.newEnvelopeName,
    super.key,
  });
  final TransactionWallet wallet;
  final String? selectedEnvelopePk;
  final Function(String envelopePk) onSelected;
  final String? newEnvelopeName; // название новой подгруппы (если выбрана)
  // Редактируемая трата: её сумма уже учтена в остатке, при показе возвращаем
  final Transaction? editingTransaction;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EnvelopeBalances>(
      stream: database.watchEnvelopeBalances(wallet.walletPk),
      builder: (context, snapshot) {
        EnvelopeBalances? data = snapshot.data;
        if (data == null) return SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(
              start: 15, end: 15, bottom: 8, top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFont(
                text: "Подгруппа для траты",
                fontSize: 13,
                textColor: getColor(context, "textLight"),
              ),
              SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  ChoiceChip(
                    avatar: Icon(Icons.add_rounded, size: 18),
                    label: Text(selectedEnvelopePk == newEnvelopeKey &&
                            (newEnvelopeName ?? "").isNotEmpty
                        ? "Новая: " + newEnvelopeName!
                        : "Новая подгруппа"),
                    selected: selectedEnvelopePk == newEnvelopeKey,
                    onSelected: (_) => onSelected(newEnvelopeKey),
                  ),
                  // Локальная версия: списать из свободных денег счёта
                  ChoiceChip(
                    label: Text("Свободные · " +
                        envelopeMoney(context, wallet, freeExcludingEditing(data))),
                    selected: selectedEnvelopePk == freeMoneyKey,
                    onSelected: (_) => onSelected(freeMoneyKey),
                  ),
                  for (Envelope envelope in data.envelopes)
                    ChoiceChip(
                      label: Text(envelope.name +
                          " · " +
                          envelopeMoney(
                            context,
                            wallet,
                            balanceExcludingEditing(data, envelope),
                          )),
                      selected: selectedEnvelopePk == envelope.envelopePk,
                      onSelected: (_) => onSelected(envelope.envelopePk),
                    ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  double freeExcludingEditing(EnvelopeBalances data) =>
      freeBalanceExcludingEditing(data, editingTransaction);

  double balanceExcludingEditing(EnvelopeBalances data, Envelope envelope) {
    double balance = data.balanceOf(envelope.envelopePk);
    Transaction? editing = editingTransaction;
    if (editing != null &&
        editing.paid &&
        editing.envelopeFk == envelope.envelopePk) {
      balance -= editing.amount;
    }
    return balance;
  }
}

/// Свободные деньги без учёта редактируемой траты (её сумма уже вычтена из баланса).
double freeBalanceExcludingEditing(
    EnvelopeBalances data, Transaction? editing) {
  double free = data.free;
  if (editing != null &&
      editing.paid &&
      editing.envelopeFk == null &&
      editing.walletFk == data.walletPk) {
    free -= editing.amount;
  }
  return free;
}

/// Окно выбора подгруппы — для обязательного выбора перед сохранением траты.
/// Возвращает envelopePk или freeMoneyKey («Свободные»).
Future<String?> pickEnvelope(
    BuildContext context, TransactionWallet wallet) async {
  EnvelopeBalances data = await database.getEnvelopeBalances(wallet.walletPk);
  dynamic result = await openBottomSheet(
    context,
    PopupFramework(
      title: "В какую подгруппу?",
      subtitle: wallet.name,
      child: Column(
        children: [
          Tappable(
            color: Colors.transparent,
            borderRadius: 10,
            onTap: () => popRoute(context, newEnvelopeKey),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  vertical: 12, horizontal: 5),
              child: TextFont(
                  text: "＋ Новая подгруппа", fontSize: 17, maxLines: 1),
            ),
          ),
          Tappable(
            color: Colors.transparent,
            borderRadius: 10,
            onTap: () => popRoute(context, freeMoneyKey),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  vertical: 12, horizontal: 5),
              child: Row(
                children: [
                  Expanded(
                    child: TextFont(
                        text: "Свободные", fontSize: 17, maxLines: 1),
                  ),
                  TextFont(
                    text: envelopeMoney(context, wallet, data.free),
                    fontSize: 16,
                    textColor: envelopeAmountColor(context, data.free),
                  ),
                ],
              ),
            ),
          ),
          for (Envelope envelope in data.envelopes)
            Tappable(
              color: Colors.transparent,
              borderRadius: 10,
              onTap: () => popRoute(context, envelope.envelopePk),
              child: Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                    vertical: 12, horizontal: 5),
                child: Row(
                  children: [
                    Expanded(
                      child: TextFont(
                          text: envelope.name, fontSize: 17, maxLines: 1),
                    ),
                    TextFont(
                      text: envelopeMoney(
                          context, wallet, data.balanceOf(envelope.envelopePk)),
                      fontSize: 16,
                      textColor: envelopeAmountColor(
                          context, data.balanceOf(envelope.envelopePk)),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    ),
  );
  if (result is String) return result;
  return null;
}


// ---------------------------------------------------------------------------
// Архив подгрупп

class EnvelopeArchiveSheet extends StatefulWidget {
  const EnvelopeArchiveSheet({required this.wallet, super.key});
  final TransactionWallet wallet;

  @override
  State<EnvelopeArchiveSheet> createState() => _EnvelopeArchiveSheetState();
}

class _EnvelopeArchiveSheetState extends State<EnvelopeArchiveSheet> {
  Future<List<Envelope>> load() async {
    return (await database
            .getEnvelopesIncludingArchived(widget.wallet.walletPk))
        .where((e) => isEnvelopeArchived(e.envelopePk))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: "Архив подгрупп",
      subtitle: widget.wallet.name,
      child: FutureBuilder<List<Envelope>>(
        future: load(),
        builder: (context, snapshot) {
          List<Envelope> list = snapshot.data ?? [];
          if (list.isEmpty) {
            return TextFont(
              text: "В архиве пусто",
              fontSize: 14,
              textColor: getColor(context, "textLight"),
            );
          }
          return Column(
            children: [
              for (Envelope envelope in list)
                Padding(
                  padding: const EdgeInsetsDirectional.only(bottom: 8),
                  child: Row(
                    children: [
                      Expanded(
                        child: TextFont(
                            text: envelope.name, fontSize: 16, maxLines: 1),
                      ),
                      Button(
                        label: "Вернуть",
                        onTap: () async {
                          await database.restoreEnvelope(envelope);
                          setState(() {});
                        },
                      ),
                    ],
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}


/// Спрашивает название новой подгруппы. Возвращает null, если отменили.
Future<({String name, EnvelopePriority priority})?> askNewEnvelopeName(
    BuildContext context, String suggested,
    {EnvelopePriority priority = EnvelopePriority.medium}) async {
  dynamic result = await openBottomSheet(
    context,
    _NewEnvelopeNameSheet(suggested: suggested, priority: priority),
    popupWithKeyboard: true,
  );
  if (result is List && result.length == 2) {
    return (name: result[0] as String, priority: result[1] as EnvelopePriority);
  }
  return null;
}

class _NewEnvelopeNameSheet extends StatefulWidget {
  const _NewEnvelopeNameSheet({required this.suggested, required this.priority});
  final String suggested;
  final EnvelopePriority priority;

  @override
  State<_NewEnvelopeNameSheet> createState() => _NewEnvelopeNameSheetState();
}

class _NewEnvelopeNameSheetState extends State<_NewEnvelopeNameSheet> {
  late TextEditingController controller =
      TextEditingController(text: widget.suggested);
  late EnvelopePriority priority = widget.priority;

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    String name = controller.text.trim();
    if (name.isEmpty) return;
    popRoute(context, [name, priority]);
  }

  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: "Новая подгруппа",
      child: Column(
        children: [
          TextInput(
            labelText: "Название подгруппы",
            controller: controller,
            autoFocus: true,
            padding: EdgeInsetsDirectional.zero,
            textCapitalization: TextCapitalization.sentences,
            onSubmitted: (_) => submit(),
          ),
          SizedBox(height: 12),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: TextFont(
                text: "Приоритет пополнения",
                fontSize: 13,
                textColor: getColor(context, "textLight")),
          ),
          SizedBox(height: 6),
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Wrap(
              spacing: 8,
              children: [
                for (EnvelopePriority p in EnvelopePriority.values)
                  ChoiceChip(
                    label: Text(envelopePriorityLabel(p)),
                    selected: priority == p,
                    onSelected: (_) => setState(() => priority = p),
                  ),
              ],
            ),
          ),
          SizedBox(height: 15),
          Button(
            label: "Создать",
            expandedLayout: true,
            onTap: submit,
          ),
        ],
      ),
    );
  }
}
