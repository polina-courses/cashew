// Локальная версия: счёт категории. Категория расходов и счёт — почти одна
// сущность: у каждой категории (например, «Дети») свой счёт, внутри него
// подгруппы (например, «Репетиторы»).

import 'package:budget/database/tables.dart';
import 'package:budget/struct/categoryWalletLinks.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/struct/settings.dart';

/// Счёт категории: связанный, либо счёт с таким же названием, либо новый
/// (название = категория, валюта как у основного счёта).
Future<TransactionWallet> ensureCategoryWallet(
    TransactionCategory category) async {
  List<TransactionWallet> all = await database.getAllWallets();
  String? linked = getCategoryWalletLinks()[category.categoryPk];
  for (TransactionWallet w in all) {
    if (w.walletPk == linked) return w;
  }
  String wanted = category.name.trim().toLowerCase();
  for (TransactionWallet w in all) {
    if (w.name.trim().toLowerCase() == wanted) {
      await setCategoryWalletLink(category.categoryPk, w.walletPk);
      return w;
    }
  }
  TransactionWallet base = all.firstWhere(
      (w) => w.walletPk == appStateSettings["selectedWalletPk"],
      orElse: () => all.first);
  int rowId = await database.createOrUpdateWallet(
    TransactionWallet(
      walletPk: "-1",
      name: category.name.trim(),
      colour: category.colour ?? base.colour,
      dateCreated: DateTime.now(),
      dateTimeModified: null,
      order: all.length,
      currency: base.currency,
      decimals: base.decimals,
      homePageWidgetDisplay: base.homePageWidgetDisplay,
    ),
    insert: true,
  );
  TransactionWallet created = await database.getWalletFromRowId(rowId);
  await setCategoryWalletLink(category.categoryPk, created.walletPk);
  return created;
}

/// Счета категорий (без общего): те, что привязаны к категориям.
Future<List<TransactionWallet>> getCategoryWallets() async {
  Set<String> pks = getCategoryWalletLinks().values.toSet();
  return (await database.getAllWallets())
      .where((w) => pks.contains(w.walletPk))
      .toList();
}
