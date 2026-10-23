import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/openContainerNavigation.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/tappable.dart';
import 'package:budget/widgets/textWidgets.dart';
import 'package:budget/database/tables.dart';
import 'package:budget/functions.dart';
import 'package:budget/pages/addTransactionPage.dart';
import 'package:budget/pages/addWalletPage.dart';
import 'package:budget/struct/databaseGlobal.dart';
import 'package:budget/widgets/openPopup.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

class AddFAB extends StatelessWidget {
  const AddFAB({
    this.openPage,
    this.onTap,
    this.tooltip,
    this.enableLongPress = false,
    this.color,
    this.colorIcon,
    super.key,
  });
  final Widget? openPage;
  final VoidCallback? onTap;
  final String? tooltip;
  final bool enableLongPress;
  final Color? color;
  final Color? colorIcon;

  @override
  Widget build(BuildContext context) {
    return FAB(
      colorIcon: colorIcon,
      color: color,
      tooltip: tooltip,
      iconData: appStateSettings["outlinedIcons"]
          ? Icons.add_outlined
          : Icons.add_rounded,
      openPage: openPage,
      onTap: onTap,
      fabSize: getIsFullScreen(context) == false ? 60 : 70,
      borderRadius: getIsFullScreen(context) == false ? 18 : 22,
      onLongPress: () {
        openBottomSheet(
          context,
          PopupFramework(
            child: AddMoreThingsPopup(),
          ),
        );
      },
    );
  }
}

class FAB extends StatelessWidget {
  const FAB({
    Key? key,
    this.openPage,
    this.onTap,
    this.onLongPress,
    this.tooltip,
    this.color,
    this.colorIcon,
    this.iconData,
    this.fabSize = 60,
    this.borderRadius = 18,
    this.label,
    this.labelSize = 18,
    this.isOutlined = false,
  }) : super(key: key);

  final Widget? openPage;
  final String? tooltip;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final Color? colorIcon;
  final IconData? iconData;
  final double fabSize;
  final double borderRadius;
  final String? label;
  final double labelSize;
  final bool isOutlined;

  @override
  Widget build(BuildContext context) {
    Color? containerColor = color != null
        ? color
        : isOutlined
            ? Theme.of(context).colorScheme.onSecondary
            : Theme.of(context).colorScheme.secondary;
    Color? iconColor = color != null
        ? colorIcon
        : isOutlined
            ? Theme.of(context).colorScheme.secondary
            : Theme.of(context).colorScheme.onSecondary;

    // Experiment with more vibrant FAB colors
    // Color? containerColor = color != null
    //     ? color
    //     : isOutlined
    //         ? Theme.of(context).colorScheme.onSecondary
    //         : blend(Theme.of(context).colorScheme.secondary,
    //             Theme.of(context).colorScheme.primary,
    //             amount: 0.35);
    // Color? iconColor = color != null
    //     ? colorIcon
    //     : isOutlined
    //         ? Theme.of(context).colorScheme.secondary
    //         : blend(Theme.of(context).colorScheme.onSecondary,
    //             Theme.of(context).colorScheme.onPrimary,
    //             amount: 0.35);
    return OpenContainerNavigation(
      closedElevation: 10,
      borderRadius: borderRadius,
      closedColor: containerColor,
      button: (openContainer) {
        return Tooltip(
          message: tooltip ?? "",
          child: Tappable(
            color: containerColor,
            onTap: () {
              if (onTap != null)
                onTap!();
              else
                openContainer();
            },
            onLongPress: onLongPress,
            child: OutlinedContainer(
              enabled: isOutlined,
              borderRadius: borderRadius,
              child: Builder(builder: (context) {
                Widget fabIcon = SizedBox(
                  height: fabSize,
                  width: fabSize,
                  child: Center(
                    child: Icon(
                      iconData,
                      color: iconColor,
                    ),
                  ),
                );
                if (label != null)
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      fabIcon,
                      Padding(
                        padding: const EdgeInsetsDirectional.only(
                            top: 5, bottom: 5, end: 20),
                        child: TextFont(
                          text: label ?? "",
                          fontSize: labelSize,
                          textColor: iconColor,
                        ),
                      ),
                    ],
                  );
                return fabIcon;
              }),
            ),
          ),
        );
      },
      openPage: openPage ?? Container(),
    );
  }
}

// Кнопка «+» для новой транзакции: сначала спрашивает тип
// (расход / доход / перевод), потом открывает форму на нужной вкладке.
class AddTransactionFAB extends StatelessWidget {
  const AddTransactionFAB({
    this.selectedBudget,
    this.routesToPopAfterDelete = RoutesToPopAfterDelete.None,
    this.color,
    this.colorIcon,
    super.key,
  });
  final Budget? selectedBudget;
  final RoutesToPopAfterDelete routesToPopAfterDelete;
  final Color? color;
  final Color? colorIcon;

  @override
  Widget build(BuildContext context) {
    return AddFAB(
      tooltip: "add-transaction".tr(),
      color: color,
      colorIcon: colorIcon,
      onTap: () {
        openAddTransactionTypePicker(
          context,
          selectedBudget: selectedBudget,
          routesToPopAfterDelete: routesToPopAfterDelete,
        );
      },
    );
  }
}

Future openAddTransactionTypePicker(
  BuildContext context, {
  Budget? selectedBudget,
  RoutesToPopAfterDelete routesToPopAfterDelete = RoutesToPopAfterDelete.None,
}) {
  final bool canTransfer =
      Provider.of<AllWallets>(context, listen: false).list.length > 1;

  void openForm(bool isIncome) {
    popRoute(context);
    pushRoute(
      context,
      AddTransactionPage(
        selectedBudget: selectedBudget,
        selectedIncome: isIncome,
        routesToPopAfterDelete: routesToPopAfterDelete,
      ),
    );
  }

  return openBottomSheet(
    context,
    PopupFramework(
      title: "select-transaction-type".tr(),
      child: Column(
        children: [
          OutlinedButtonStacked(
            text: "expense".tr(),
            iconData: appStateSettings["outlinedIcons"]
                ? Icons.arrow_downward_outlined
                : Icons.arrow_downward_rounded,
            alignStart: true,
            alignBeside: true,
            padding: EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 18),
            onTap: () => openForm(false),
          ),
          SizedBox(height: 10),
          OutlinedButtonStacked(
            text: "income".tr(),
            iconData: appStateSettings["outlinedIcons"]
                ? Icons.arrow_upward_outlined
                : Icons.arrow_upward_rounded,
            alignStart: true,
            alignBeside: true,
            padding: EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 18),
            onTap: () => openForm(true),
          ),
          if (canTransfer) SizedBox(height: 10),
          if (canTransfer)
            OutlinedButtonStacked(
              text: "transfer".tr(),
              iconData: appStateSettings["outlinedIcons"]
                  ? Icons.compare_arrows_outlined
                  : Icons.compare_arrows_rounded,
              alignStart: true,
              alignBeside: true,
              padding: EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 18),
            padding: EdgeInsetsDirectional.symmetric(horizontal: 8, vertical: 18),
              onTap: () {
                popRoute(context);
                openBottomSheet(
                  context,
                  fullSnap: true,
                  TransferBalancePopup(
                    allowEditWallet: true,
                    wallet: Provider.of<AllWallets>(context, listen: false)
                        .indexedByPk[appStateSettings["selectedWalletPk"]]!,
                    showAllEditDetails: true,
                  ),
                );
              },
            ),
        ],
      ),
    ),
  );
}
