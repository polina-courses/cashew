import 'package:budget/colors.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/struct/utilities.dart';
import 'package:budget/widgets/button.dart';
import 'package:budget/widgets/envelopes.dart' show envelopeDate;
import 'package:budget/widgets/fab.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/widgets/framework/pageFramework.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textInput.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

/// Локальная версия: вкладка «ЖКХ».
class UtilitiesPage extends StatefulWidget {
  const UtilitiesPage({super.key});

  @override
  State<UtilitiesPage> createState() => _UtilitiesPageState();
}

class _UtilitiesPageState extends State<UtilitiesPage> {
  List<UtilityItem> items = [];

  @override
  void initState() {
    super.initState();
    items = utilitiesFromSettings(appStateSettings["utilities"]);
  }

  Future<void> save() async {
    await updateSettings("utilities", utilitiesToSettings(items),
        updateGlobalState: false);
    if (mounted) setState(() {});
  }

  String money(double v) =>
      convertToMoney(Provider.of<AllWallets>(context, listen: false), v);

  Future<void> addItem() async {
    UtilityItem item = UtilityItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(), name: "");
    dynamic r = await openBottomSheet(
        context, _UtilityEditSheet(item: item, isNew: true),
        popupWithKeyboard: true);
    if (r == "save") {
      items.add(item);
      await save();
    }
  }

  Future<void> editItem(UtilityItem item) async {
    dynamic r = await openBottomSheet(
        context, _UtilityEditSheet(item: item, isNew: false),
        popupWithKeyboard: true);
    if (r == "save") {
      await save();
    } else if (r == "delete") {
      items.removeWhere((i) => i.id == item.id);
      await save();
    }
  }

  Future<void> togglePaid(UtilityItem item) async {
    DateTime now = DateTime.now();
    if (item.isPaid(now)) {
      item.unmarkPaid();
      await save();
      return;
    }
    dynamic r = await openBottomSheet(
        context, _UtilityPaySheet(item: item, money: money),
        popupWithKeyboard: true);
    if (r is double) {
      item.markPaid(r, now);
      await save();
    }
  }

  @override
  Widget build(BuildContext context) {
    DateTime now = DateTime.now();
    Color light = getColor(context, "textLight");
    double left = utilitiesLeftToPay(items, now);
    int paidCount = items.where((i) => i.isPaid(now)).length;
    return PageFramework(
      horizontalPaddingConstrained: true,
      dragDownToDismiss: true,
      title: "ЖКХ",
      floatingActionButton: AnimateFABDelayed(
        fab: AddFAB(tooltip: "Добавить пункт", onTap: addItem),
      ),
      listWidgets: [
        if (items.isEmpty)
          Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 20, vertical: 30),
            child: TextFont(
              text: "Добавьте пункты (свет, вода, газ…) кнопкой «+». "
                  "Оплата отмечается раз в месяц и сама сбрасывается 1 числа.",
              fontSize: 15,
              maxLines: 5,
              textColor: light,
            ),
          )
        else
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(20, 6, 20, 10),
            child: Row(
              children: [
                Expanded(
                  child: TextFont(
                    text: "Оплачено $paidCount из ${items.length}",
                    fontSize: 15,
                    textColor: light,
                  ),
                ),
                if (left > 0)
                  TextFont(
                    text: "осталось " + money(left),
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    textColor: getColor(context, "expenseAmount"),
                  ),
              ],
            ),
          ),
        for (UtilityItem item in items) _row(context, item, now, light),
        SizedBox(height: 80),
      ],
    );
  }

  Widget _row(BuildContext context, UtilityItem item, DateTime now, Color light) {
    bool paid = item.isPaid(now);
    String? info;
    if (paid) {
      info = "оплачено " +
          (item.paidOn == null ? "" : envelopeDate(item.paidOn!)) +
          (item.paidAmount > 0 ? " · " + money(item.paidAmount) : "");
    }
    return Tappable(
      color: Colors.transparent,
      borderRadius: 10,
      onTap: () => editItem(item),
      child: Padding(
        padding: const EdgeInsetsDirectional.symmetric(
            horizontal: 12, vertical: 6),
        child: Row(
          children: [
            IconButton(
              tooltip: paid ? "Снять отметку" : "Отметить оплату",
              icon: Icon(
                paid
                    ? Icons.check_circle_rounded
                    : Icons.radio_button_unchecked_rounded,
                color: paid ? getColor(context, "incomeAmount") : light,
              ),
              onPressed: () => togglePaid(item),
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  TextFont(text: item.name, fontSize: 16, maxLines: 2),
                  if (info != null)
                    TextFont(text: info, fontSize: 13, textColor: light),
                  if (item.credit > 0)
                    Text(
                      "переплата " + money(item.credit),
                      style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: getColor(context, "incomeAmount")),
                    ),
                  if (item.credit < 0)
                    Text(
                      "недоплата " + money(-item.credit),
                      style: TextStyle(
                          fontSize: 13,
                          fontStyle: FontStyle.italic,
                          color: getColor(context, "expenseAmount")),
                    ),
                ],
              ),
            ),
            if (item.amount > 0)
              TextFont(
                text: paid ? money(item.amount) : money(item.due()),
                fontSize: 16,
                fontWeight: FontWeight.bold,
                textColor: paid ? light : null,
              ),
          ],
        ),
      ),
    );
  }
}

class _UtilityPaySheet extends StatefulWidget {
  const _UtilityPaySheet({required this.item, required this.money});
  final UtilityItem item;
  final String Function(double) money;

  @override
  State<_UtilityPaySheet> createState() => _UtilityPaySheetState();
}

class _UtilityPaySheetState extends State<_UtilityPaySheet> {
  late TextEditingController controller = TextEditingController(
      text: widget.item.amount > 0
          ? _num(widget.item.due())
          : "");

  @override
  void dispose() {
    controller.dispose();
    super.dispose();
  }

  void submit() {
    double? v = getAmountFromString(controller.text);
    if (v == null || v <= 0) return;
    popRoute(context, v);
  }

  @override
  Widget build(BuildContext context) {
    Color light = getColor(context, "textLight");
    return PopupFramework(
      title: widget.item.name,
      child: Column(
        children: [
          TextInput(
            labelText: "Сколько оплачено",
            controller: controller,
            autoFocus: true,
            numbersOnly: true,
            padding: EdgeInsetsDirectional.zero,
            onSubmitted: (_) => submit(),
          ),
          if (widget.item.amount > 0) ...[
            SizedBox(height: 8),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextFont(
                text: widget.item.credit > 0
                    ? "Обычно " +
                        widget.money(widget.item.amount) +
                        ", переплата " +
                        widget.money(widget.item.credit) +
                        " уже учтена. Если заплатите больше, разница уйдёт в переплату."
                    : "Обычно " +
                        widget.money(widget.item.amount) +
                        ". Если заплатите больше, разница уйдёт в переплату.",
                fontSize: 13,
                maxLines: 4,
                textColor: light,
              ),
            ),
          ],
          SizedBox(height: 14),
          Button(label: "Оплачено", expandedLayout: true, onTap: submit),
        ],
      ),
    );
  }
}

String _num(double v) =>
    v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toStringAsFixed(2);

class _UtilityEditSheet extends StatefulWidget {
  const _UtilityEditSheet({required this.item, required this.isNew});
  final UtilityItem item;
  final bool isNew;

  @override
  State<_UtilityEditSheet> createState() => _UtilityEditSheetState();
}

class _UtilityEditSheetState extends State<_UtilityEditSheet> {
  late TextEditingController name =
      TextEditingController(text: widget.item.name);
  late TextEditingController amount = TextEditingController(
      text: widget.item.amount > 0 ? _num(widget.item.amount) : "");
  late TextEditingController credit = TextEditingController(
      text: widget.item.credit != 0 ? _num(widget.item.credit) : "");

  @override
  void dispose() {
    name.dispose();
    amount.dispose();
    credit.dispose();
    super.dispose();
  }

  void submit() {
    String n = name.text.trim();
    if (n.isEmpty) return;
    widget.item.name = n;
    widget.item.amount = getAmountFromString(amount.text) ?? 0;
    widget.item.credit = getAmountFromString(credit.text) ?? 0;
    popRoute(context, "save");
  }

  @override
  Widget build(BuildContext context) {
    return PopupFramework(
      title: widget.isNew ? "Новый пункт" : "Пункт ЖКХ",
      child: Column(
        children: [
          TextInput(
            labelText: "Название (например, Свет)",
            controller: name,
            autoFocus: widget.isNew,
            padding: EdgeInsetsDirectional.zero,
            textCapitalization: TextCapitalization.sentences,
          ),
          SizedBox(height: 10),
          TextInput(
            labelText: "Обычная сумма за месяц (можно пусто)",
            controller: amount,
            numbersOnly: true,
            padding: EdgeInsetsDirectional.zero,
          ),
          SizedBox(height: 10),
          TextInput(
            labelText: "Переплата сейчас (минус — недоплата)",
            controller: credit,
            padding: EdgeInsetsDirectional.zero,
            keyboardType: TextInputType.numberWithOptions(
                decimal: true, signed: true),
          ),
          SizedBox(height: 14),
          Row(
            children: [
              if (!widget.isNew)
                Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Button(
                    label: "Удалить",
                    color: Theme.of(context).colorScheme.errorContainer,
                    textColor: Theme.of(context).colorScheme.onErrorContainer,
                    onTap: () => popRoute(context, "delete"),
                  ),
                ),
              Expanded(
                child: Button(
                    label: "Сохранить", expandedLayout: true, onTap: submit),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
