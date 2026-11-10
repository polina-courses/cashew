// Локальная версия: получатель перевода — счёт, цель накоплений или кредит.
// Чистая логика без базы: из выбора получателя получаем поля записи.

enum TransferTargetKind { wallet, goal, loan }

class ObjectiveTransferPlan {
  const ObjectiveTransferPlan({
    required this.amount,
    required this.income,
    required this.objectiveFk,
    required this.objectiveLoanFk,
  });

  /// Сумма записи со знаком (расход — минус).
  final double amount;
  final bool income;

  /// Взнос на цель накоплений.
  final String? objectiveFk;

  /// Платёж по кредиту.
  final String? objectiveLoanFk;
}

/// Перевод со счёта на цель (взнос) или кредит (платёж): всегда расход со
/// счёта-источника. Для обычного перевода между счетами возвращает null.
ObjectiveTransferPlan? planObjectiveTransfer({
  required TransferTargetKind kind,
  required double amount,
  required String? objectivePk,
}) {
  if (kind == TransferTargetKind.wallet) return null;
  if (objectivePk == null) return null;
  double value = amount.abs();
  if (value == 0) return null;
  return ObjectiveTransferPlan(
    amount: -value,
    income: false,
    objectiveFk: kind == TransferTargetKind.goal ? objectivePk : null,
    objectiveLoanFk: kind == TransferTargetKind.loan ? objectivePk : null,
  );
}
