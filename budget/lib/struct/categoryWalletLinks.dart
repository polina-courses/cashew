// Локальная версия: связка «категория расхода → счёт по умолчанию».
// Хранится в настройках приложения: {categoryPk: walletPk}.
import 'package:budget/database/tables.dart';
import 'package:budget/struct/settings.dart';

Map<String, String> getCategoryWalletLinks() {
  final dynamic raw = appStateSettings["categoryWalletLinks"];
  if (raw is Map) {
    return raw.map((k, v) => MapEntry(k.toString(), v.toString()));
  }
  return {};
}

/// Счёт, привязанный к категории (null — не задан или счёта уже нет).
String? getLinkedWalletPk(String categoryPk, AllWallets allWallets) {
  String? walletPk = getCategoryWalletLinks()[categoryPk];
  if (walletPk == null) return null;
  return allWallets.indexedByPk.containsKey(walletPk) ? walletPk : null;
}

Future<void> setCategoryWalletLink(String categoryPk, String? walletPk) async {
  Map<String, String> links = getCategoryWalletLinks();
  if (walletPk == null) {
    links.remove(categoryPk);
  } else {
    links[categoryPk] = walletPk;
  }
  await updateSettings("categoryWalletLinks", links, updateGlobalState: false);
}
