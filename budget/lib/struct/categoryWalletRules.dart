// Локальная версия: чистые правила (без базы) для счёта категории.

/// Нужно ли при сохранении расхода подставить счёт категории (и создать его,
/// если его ещё нет).
///
/// Счёт категории появляется только когда счёт в форме вручную не выбирали.
/// Если счёт выбран руками (даже основной), новый счёт не создаётся: новая
/// категория расходов появляется, счёт — нет.
bool shouldAutoCreateCategoryWallet({
  required bool isNewTransaction,
  required bool isExpense,
  required bool isLoanPayment,
  required bool walletChosenManually,
  required String? categoryPk,
  required bool openedWithOtherWallet,
}) {
  if (!isNewTransaction) return false;
  if (!isExpense) return false;
  if (isLoanPayment) return false;
  if (walletChosenManually) return false;
  if (categoryPk == null || categoryPk == "0" || categoryPk == "-1") {
    return false;
  }
  // Форму открыли из конкретного (не основного) счёта: он и остаётся
  if (openedWithOtherWallet) return false;
  return true;
}
