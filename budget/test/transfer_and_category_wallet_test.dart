import 'package:budget/struct/categoryWalletRules.dart';
import 'package:budget/struct/transferTarget.dart';
import 'package:flutter_test/flutter_test.dart';

bool _auto({
  bool isNewTransaction = true,
  bool isExpense = true,
  bool isLoanPayment = false,
  bool walletChosenManually = false,
  String? categoryPk = "cat-1",
  bool openedWithOtherWallet = false,
}) =>
    shouldAutoCreateCategoryWallet(
      isNewTransaction: isNewTransaction,
      isExpense: isExpense,
      isLoanPayment: isLoanPayment,
      walletChosenManually: walletChosenManually,
      categoryPk: categoryPk,
      openedWithOtherWallet: openedWithOtherWallet,
    );

void main() {
  group('счёт категории', () {
    test('счёт не выбирали вручную: счёт категории создаётся', () {
      expect(_auto(), isTrue);
    });

    test('счёт выбран вручную (даже основной): счёт категории не создаётся', () {
      expect(_auto(walletChosenManually: true), isFalse);
    });

    test('доход, редактирование, погашение кредита: не создаётся', () {
      expect(_auto(isExpense: false), isFalse);
      expect(_auto(isNewTransaction: false), isFalse);
      expect(_auto(isLoanPayment: true), isFalse);
    });

    test('без категории и служебная категория: не создаётся', () {
      expect(_auto(categoryPk: null), isFalse);
      expect(_auto(categoryPk: "0"), isFalse);
    });

    test('форма открыта из конкретного счёта: он остаётся', () {
      expect(_auto(openedWithOtherWallet: true), isFalse);
    });
  });

  group('перевод на цель или кредит', () {
    test('цель: взнос, расход со счёта с objectiveFk', () {
      ObjectiveTransferPlan? plan = planObjectiveTransfer(
          kind: TransferTargetKind.goal, amount: 1500, objectivePk: "goal-1");
      expect(plan, isNotNull);
      expect(plan!.amount, -1500);
      expect(plan.income, isFalse);
      expect(plan.objectiveFk, "goal-1");
      expect(plan.objectiveLoanFk, isNull);
    });

    test('кредит: платёж, расход со счёта с objectiveLoanFk', () {
      ObjectiveTransferPlan? plan = planObjectiveTransfer(
          kind: TransferTargetKind.loan, amount: -2000, objectivePk: "loan-1");
      expect(plan, isNotNull);
      expect(plan!.amount, -2000);
      expect(plan.income, isFalse);
      expect(plan.objectiveLoanFk, "loan-1");
      expect(plan.objectiveFk, isNull);
    });

    test('обычный перевод между счетами, пустой выбор и нулевая сумма: нет плана',
        () {
      expect(
          planObjectiveTransfer(
              kind: TransferTargetKind.wallet, amount: 10, objectivePk: "x"),
          isNull);
      expect(
          planObjectiveTransfer(
              kind: TransferTargetKind.goal, amount: 10, objectivePk: null),
          isNull);
      expect(
          planObjectiveTransfer(
              kind: TransferTargetKind.loan, amount: 0, objectivePk: "loan-1"),
          isNull);
    });
  });
}
