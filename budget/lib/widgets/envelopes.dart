// Локальная версия: подгруппы счёта («конверты») — интерфейс.

import 'package:budget/colors.dart';
import 'package:budget/database/envelopes.dart';
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
        return Padding(
          padding: const EdgeInsetsDirectional.only(bottom: 13),
          child: Container(
            decoration: BoxDecoration(
              color: getColor(context, "lightDarkAccentHeavyLight"),
              boxShadow: boxShadowCheck(boxShadowGeneral(context)),
              borderRadius: BorderRadiusDirectional.circular(15),
            ),
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 15, vertical: 12),
            child: data.envelopes.isEmpty
                ? _EmptyEnvelopes(wallet: wallet)
                : _EnvelopesList(wallet: wallet, data: data),
          ),
        );
      },
    );
  }
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

class _EnvelopesList extends StatelessWidget {
  const _EnvelopesList({required this.wallet, required this.data});
  final TransactionWallet wallet;
  final EnvelopeBalances data;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFont(
                text: "Подгруппы счёта",
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            IconButton(
              tooltip: "Добавить подгруппу",
              icon: Icon(Icons.add_rounded),
              onPressed: () => openEnvelopeEditor(context, wallet: wallet),
            ),
          ],
        ),
        for (Envelope envelope in data.envelopes)
          Tappable(
            color: Colors.transparent,
            borderRadius: 10,
            onTap: () =>
                openEnvelopeEditor(context, wallet: wallet, envelope: envelope),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        TextFont(
                          text: envelope.name,
                          fontSize: 16,
                          maxLines: 1,
                        ),
                        if (envelope.percent > 0)
                          TextFont(
                            text: "доля " +
                                formatNumberForInput(envelope.percent, 1) +
                                "%",
                            fontSize: 12,
                            textColor: getColor(context, "textLight"),
                          ),
                        _EnvelopeGoalLines(
                          wallet: wallet,
                          goal: envelopeGoalOf(
                              envelope, data.balanceOf(envelope.envelopePk)),
                        ),
                      ],
                    ),
                  ),
                  TextFont(
                    text: envelopeMoney(
                        context, wallet, data.balanceOf(envelope.envelopePk)),
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    textColor: envelopeAmountColor(
                        context, data.balanceOf(envelope.envelopePk)),
                  ),
                ],
              ),
            ),
          ),
        Divider(),
        Row(
          children: [
            Expanded(
              child: TextFont(
                text: "Свободно",
                fontSize: 16,
                textColor: getColor(context, "textLight"),
              ),
            ),
            TextFont(
              text: envelopeMoney(context, wallet, data.free),
              fontSize: 16,
              fontWeight: FontWeight.bold,
              textColor: envelopeAmountColor(context, data.free),
            ),
          ],
        ),
        if (data.percentTotal > 100.0001)
          Padding(
            padding: const EdgeInsetsDirectional.only(top: 6),
            child: TextFont(
              text: "Сумма долей больше 100% (" +
                  formatNumberForInput(data.percentTotal, 1) +
                  "%). Поправьте доли подгрупп.",
              fontSize: 13,
              maxLines: 3,
              textColor: getColor(context, "expenseAmount"),
            ),
          ),
        SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: Button(
                label: "Распределить",
                expandedLayout: true,
                onTap: () => openDistributeSheet(
                  context,
                  wallet: wallet,
                  amount: data.free > 0 ? data.free : 0,
                  title: "Распределить свободные",
                ),
              ),
            ),
            SizedBox(width: 8),
            Expanded(
              child: Button(
                label: "Переложить",
                expandedLayout: true,
                color: Theme.of(context).colorScheme.secondaryContainer,
                textColor: Theme.of(context).colorScheme.onSecondaryContainer,
                onTap: () => openEnvelopeTransferSheet(context, wallet: wallet),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _EnvelopeGoalLines extends StatelessWidget {
  const _EnvelopeGoalLines({required this.wallet, required this.goal});
  final TransactionWallet wallet;
  final EnvelopeGoal goal;

  @override
  Widget build(BuildContext context) {
    if (!goal.hasGoal) return SizedBox.shrink();
    String? progress = envelopeGoalProgressText(context, wallet, goal);
    String? hint = envelopeGoalHintText(context, wallet, goal);
    return Padding(
      padding: const EdgeInsetsDirectional.only(top: 3, end: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (progress != null)
            TextFont(
              text: progress,
              fontSize: 12,
              maxLines: 2,
              textColor: getColor(context, "textLight"),
            ),
          if (goal.hasAmount)
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(vertical: 4),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: goal.progress,
                  minHeight: 5,
                  backgroundColor:
                      Theme.of(context).colorScheme.secondaryContainer,
                  color: goal.reached
                      ? getColor(context, "incomeAmount")
                      : Theme.of(context).colorScheme.primary,
                ),
              ),
            ),
          if (hint != null)
            TextFont(
              text: hint,
              fontSize: 12,
              maxLines: 2,
              textColor: envelopeGoalHintColor(context, goal),
            ),
        ],
      ),
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
    super.dispose();
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
    if (widget.envelope == null) {
      await database.createEnvelope(
        walletPk: widget.wallet.walletPk,
        name: name,
        percent: percent,
        targetAmount: parsedTarget,
        targetDate: targetDate,
      );
    } else {
      await database.updateEnvelope(widget.envelope!.copyWith(
        name: name,
        percent: percent,
        targetAmount: Value(parsedTarget),
        targetDate: Value(targetDate),
      ));
    }
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
          SizedBox(height: 10),
          TextInput(
            labelText: "Доля при пополнении, % (необязательно)",
            controller: percentController,
            padding: EdgeInsetsDirectional.zero,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
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

Future openDistributeSheet(
  BuildContext context, {
  required TransactionWallet wallet,
  required double amount,
  String? sourceTransactionPk,
  String title = "Распределить пополнение",
}) async {
  EnvelopeBalances balances =
      await database.getEnvelopeBalances(wallet.walletPk);
  List<Envelope> envelopeList = balances.envelopes;
  if (envelopeList.isEmpty) return;
  return openBottomSheet(
    context,
    DistributeSheet(
      wallet: wallet,
      envelopes: envelopeList,
      balances: balances,
      amount: amount,
      sourceTransactionPk: sourceTransactionPk,
      title: title,
    ),
    popupWithKeyboard: false,
    fullSnap: true,
  );
}

class DistributeSheet extends StatefulWidget {
  const DistributeSheet({
    required this.wallet,
    required this.envelopes,
    required this.balances,
    required this.amount,
    required this.sourceTransactionPk,
    required this.title,
    super.key,
  });
  final TransactionWallet wallet;
  final List<Envelope> envelopes;
  final EnvelopeBalances balances;
  final double amount;
  final String? sourceTransactionPk;
  final String title;

  @override
  State<DistributeSheet> createState() => _DistributeSheetState();
}

class _DistributeSheetState extends State<DistributeSheet> {
  // Суммы храним всегда в деньгах; в режиме % поля показывают долю от суммы
  late Map<String, double> amounts;
  late Map<String, TextEditingController> controllers;
  late TextEditingController totalController;
  late double total = roundToDecimals(widget.amount, widget.wallet.decimals);
  bool percentMode = false;

  int get decimals => widget.wallet.decimals;

  @override
  void initState() {
    super.initState();
    totalController =
        TextEditingController(text: formatNumberForInput(total, decimals));
    amounts = {};
    for (Envelope envelope in widget.envelopes) {
      amounts[envelope.envelopePk] =
          roundToDecimals(total * envelope.percent / 100, decimals);
    }
    controllers = {};
    for (Envelope envelope in widget.envelopes) {
      controllers[envelope.envelopePk] = TextEditingController();
    }
    fillControllers();
  }

  @override
  void dispose() {
    totalController.dispose();
    for (TextEditingController controller in controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  void fillControllers() {
    for (Envelope envelope in widget.envelopes) {
      double value = amounts[envelope.envelopePk] ?? 0;
      String text;
      if (percentMode) {
        text = total == 0
            ? ""
            : formatNumberForInput(value / total * 100, 1);
      } else {
        text = value == 0 ? "" : formatNumberForInput(value, decimals);
      }
      controllers[envelope.envelopePk]!.text = text;
    }
  }

  void onFieldChanged(Envelope envelope, String text) {
    double value = parseEnvelopeNumber(text) ?? 0;
    setState(() {
      amounts[envelope.envelopePk] = percentMode
          ? roundToDecimals(total * value / 100, decimals)
          : value;
    });
  }

  void onTotalChanged(String text) {
    double newTotal = parseEnvelopeNumber(text) ?? 0;
    setState(() {
      // При смене суммы пересчитываем по долям по умолчанию
      total = newTotal;
      for (Envelope envelope in widget.envelopes) {
        amounts[envelope.envelopePk] =
            roundToDecimals(total * envelope.percent / 100, decimals);
      }
      fillControllers();
    });
  }

  double get distributed {
    double sum = 0;
    for (double value in amounts.values) sum += value;
    return sum;
  }

  double get remainder => roundToDecimals(total - distributed, decimals);

  Future<void> save() async {
    Map<String, double> cleaned = {};
    for (MapEntry<String, double> entry in amounts.entries) {
      if (entry.value != 0) cleaned[entry.key] = entry.value;
    }
    await database.distributeToEnvelopes(
      walletPk: widget.wallet.walletPk,
      amounts: cleaned,
      sourceTransactionPk: widget.sourceTransactionPk,
    );
    popRoute(context);
  }

  @override
  Widget build(BuildContext context) {
    bool overDistributed = remainder < 0;
    return PopupFramework(
      title: widget.title,
      subtitle: widget.wallet.name,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextInput(
            labelText: "Сумма к распределению",
            controller: totalController,
            padding: EdgeInsetsDirectional.zero,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            onChanged: onTotalChanged,
          ),
          SizedBox(height: 10),
          SegmentedButton<bool>(
            segments: [
              ButtonSegment(value: false, label: Text("В деньгах")),
              ButtonSegment(value: true, label: Text("В процентах")),
            ],
            selected: {percentMode},
            onSelectionChanged: (selection) {
              setState(() {
                percentMode = selection.first;
                fillControllers();
              });
            },
          ),
          SizedBox(height: 10),
          for (Envelope envelope in widget.envelopes)
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
                          text: percentMode
                              ? envelopeMoney(context, widget.wallet,
                                  amounts[envelope.envelopePk] ?? 0)
                              : (total == 0
                                  ? ""
                                  : formatNumberForInput(
                                          (amounts[envelope.envelopePk] ?? 0) /
                                              total *
                                              100,
                                          1) +
                                      "%"),
                          fontSize: 12,
                          textColor: getColor(context, "textLight"),
                        ),
                        Builder(builder: (context) {
                          double? monthly = envelopeGoalOf(
                                  envelope,
                                  widget.balances
                                      .balanceOf(envelope.envelopePk))
                              .monthlyRecommended;
                          if (monthly == null) return SizedBox.shrink();
                          return TextFont(
                            text: "рекомендуется ≈ " +
                                envelopeMoney(context, widget.wallet, monthly) +
                                "/мес",
                            fontSize: 12,
                            maxLines: 2,
                            textColor: Theme.of(context).colorScheme.primary,
                          );
                        }),
                      ],
                    ),
                  ),
                  SizedBox(width: 10),
                  Expanded(
                    flex: 2,
                    child: TextInput(
                      labelText: percentMode ? "%" : "Сумма",
                      controller: controllers[envelope.envelopePk],
                      padding: EdgeInsetsDirectional.zero,
                      keyboardType:
                          TextInputType.numberWithOptions(decimal: true),
                      onChanged: (text) => onFieldChanged(envelope, text),
                    ),
                  ),
                ],
              ),
            ),
          SizedBox(height: 5),
          TextFont(
            text: overDistributed
                ? "Распределено больше суммы на " +
                    envelopeMoney(context, widget.wallet, -remainder)
                : "Останется свободными: " +
                    envelopeMoney(context, widget.wallet, remainder),
            fontSize: 15,
            maxLines: 2,
            textColor: overDistributed
                ? getColor(context, "expenseAmount")
                : getColor(context, "textLight"),
          ),
          SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: Button(
                  label: "Не распределять",
                  expandedLayout: true,
                  color: Theme.of(context).colorScheme.secondaryContainer,
                  textColor: Theme.of(context).colorScheme.onSecondaryContainer,
                  onTap: () => popRoute(context),
                ),
              ),
              SizedBox(width: 8),
              Expanded(
                child: Button(
                  label: "Распределить",
                  expandedLayout: true,
                  disabled: overDistributed,
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
    super.key,
  });
  final TransactionWallet wallet;
  final String? selectedEnvelopePk;
  final Function(String envelopePk) onSelected;
  // Редактируемая трата: её сумма уже учтена в остатке, при показе возвращаем
  final Transaction? editingTransaction;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<EnvelopeBalances>(
      stream: database.watchEnvelopeBalances(wallet.walletPk),
      builder: (context, snapshot) {
        EnvelopeBalances? data = snapshot.data;
        if (data == null || data.envelopes.isEmpty) return SizedBox.shrink();
        return Padding(
          padding: const EdgeInsetsDirectional.only(
              start: 15, end: 15, bottom: 8, top: 2),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFont(
                text: "Из подгруппы",
                fontSize: 13,
                textColor: getColor(context, "textLight"),
              ),
              SizedBox(height: 4),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
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

/// Окно выбора подгруппы — для обязательного выбора перед сохранением траты.
Future<String?> pickEnvelope(
    BuildContext context, TransactionWallet wallet) async {
  EnvelopeBalances data = await database.getEnvelopeBalances(wallet.walletPk);
  if (data.envelopes.isEmpty) return null;
  dynamic result = await openBottomSheet(
    context,
    PopupFramework(
      title: "Из какой подгруппы?",
      subtitle: wallet.name,
      child: Column(
        children: [
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
