import 'dart:math';
import 'package:budget/functions.dart';
import 'package:budget/pages/editBudgetPage.dart';
import 'package:budget/pages/homePage/newHomePage.dart';
import 'package:budget/pages/walletsTabPage.dart';
import 'package:budget/widgets/fab.dart';
import 'package:budget/pages/editHomePage.dart';
import 'package:budget/pages/editObjectivesPage.dart';
import 'package:budget/pages/subscriptionsPage.dart';
import 'package:budget/pages/transactionsListPage.dart';
import 'package:budget/pages/upcomingOverdueTransactionsPage.dart';
import 'package:budget/struct/navBarIconsData.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/fadeIn.dart';
import 'package:budget/widgets/framework/popupFramework.dart';
import 'package:budget/widgets/navigationFramework.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:budget/widgets/outlinedButtonStacked.dart';
import 'package:budget/widgets/framework/navigation_bar/navigation_bar.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart'
    hide NavigationDestination, NavigationBar;
import 'package:budget/colors.dart';
import 'package:flutter/services.dart';

class BottomNavBar extends StatefulWidget {
  const BottomNavBar(
      {required this.onChanged,
      required this.currentNavigationStackedIndex,
      Key? key})
      : super(key: key);
  final Function(int) onChanged;

  // current
  final int currentNavigationStackedIndex;

  @override
  State<BottomNavBar> createState() => BottomNavBarState();
}

class BottomNavBarState extends State<BottomNavBar> {
  // Локальная версия: четыре раздела и кнопка «+» посередине.
  // Номера страниц в navigationFramework: 0 главная, 20 счета, 18 календарь, 19 ЖКХ.
  static const List<int> _stackIndexOfBarIndex = [0, 20, -1, 18, 19];

  void onItemTapped(int barIndex) {
    if (barIndex == 2) {
      openAddTransactionTypePicker(context);
      return;
    }
    int stackIndex = _stackIndexOfBarIndex[barIndex];
    if (stackIndex == widget.currentNavigationStackedIndex) {
      if (stackIndex == 0) newHomePageStateKey.currentState?.scrollToTop();
      if (stackIndex == 20) walletsTabPageStateKey.currentState?.scrollToTop();
    } else {
      widget.onChanged(stackIndex);
    }
    FocusScope.of(context).unfocus();
  }

  int getBarIndexFromStackedIndex(int stackedIndex) {
    int i = _stackIndexOfBarIndex.indexOf(stackedIndex);
    return i; // -1: открыта страница вне меню (например, «Ещё»)
  }

  Widget _item(BuildContext context,
      {required int barIndex,
      required IconData icon,
      required String label,
      required bool selected}) {
    Color color = selected
        ? Theme.of(context).colorScheme.primary
        : getColor(context, "textLight");
    return Expanded(
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () {
          Feedback.forTap(context);
          onItemTapped(barIndex);
        },
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: 56),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 26, color: color),
              SizedBox(height: 3),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontFamily: appStateSettings["font"],
                  fontFamilyFallback: ['Inter'],
                  fontSize: 12,
                  fontWeight: selected ? FontWeight.bold : FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (getIsFullScreen(context)) return SizedBox.shrink();
    int selected = getBarIndexFromStackedIndex(widget.currentNavigationStackedIndex);
    bool outlined = appStateSettings["outlinedIcons"] == true;
    return Container(
      decoration: BoxDecoration(
        color: getBottomNavbarBackgroundColor(
          colorScheme: Theme.of(context).colorScheme,
          brightness: Theme.of(context).brightness,
          lightDarkAccent: getColor(context, "lightDarkAccent"),
        ),
        boxShadow: boxShadowSharp(context),
      ),
      padding: EdgeInsetsDirectional.only(
          top: 4, bottom: max(4, MediaQuery.paddingOf(context).bottom)),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          _item(context,
              barIndex: 0,
              icon: outlined ? Icons.home_outlined : Icons.home_rounded,
              label: "Главная",
              selected: selected == 0),
          _item(context,
              barIndex: 1,
              icon: outlined
                  ? Icons.account_balance_wallet_outlined
                  : Icons.account_balance_wallet_rounded,
              label: "Счета",
              selected: selected == 1),
          Expanded(
            child: Center(
              child: Semantics(
                button: true,
                label: "Добавить",
                child: GestureDetector(
                  onTap: () {
                    Feedback.forTap(context);
                    onItemTapped(2);
                  },
                  child: Container(
                    width: 56,
                    height: 56,
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primary,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(Icons.add_rounded,
                        size: 30,
                        color: Theme.of(context).colorScheme.onPrimary),
                  ),
                ),
              ),
            ),
          ),
          _item(context,
              barIndex: 3,
              icon: outlined
                  ? Icons.calendar_month_outlined
                  : Icons.calendar_month_rounded,
              label: "Календарь",
              selected: selected == 3),
          _item(context,
              barIndex: 4,
              icon: outlined ? Icons.home_work_outlined : Icons.home_work_rounded,
              label: "ЖКХ",
              selected: selected == 4),
        ],
      ),
    );
  }
}

class NavBarSpaceButton extends StatelessWidget {
  const NavBarSpaceButton(
      {required this.onPress,
      required this.flex,
      required this.child,
      super.key});
  final VoidCallback onPress;
  final int flex;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      flex: flex,
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          Feedback.forTap(context);
          onPress();
        },
        child: child,
      ),
    );
  }
}

class CustomizableNavigationBarIcon extends StatelessWidget {
  const CustomizableNavigationBarIcon({
    required this.navigationBarIconBuilder,
    required this.shortcutAppSettingKey,
    required this.afterSet,
    super.key,
  });
  final Widget Function(NavBarIconData) navigationBarIconBuilder;
  final String shortcutAppSettingKey;
  final VoidCallback afterSet;
  @override
  Widget build(BuildContext context) {
    NavBarIconData navBarIconData;
    if (navBarIconsData.containsKey(appStateSettings[shortcutAppSettingKey])) {
      navBarIconData =
          navBarIconsData[appStateSettings[shortcutAppSettingKey]]!;
    } else {
      navBarIconData = navBarIconsData["home"]!;
    }

    return GestureDetector(
      onLongPress: () async {
        HapticFeedback.heavyImpact();
        dynamic result = await openBottomSheet(
          context,
          PopupFramework(
            title: "select-shortcut".tr(),
            child: SelectNavBarShortcutPopup(
              shortcutAppSettingKey: shortcutAppSettingKey,
            ),
          ),
        );
        if (result == true) {
          // Refresh this because we want to open up the budgets detail page
          // When the budgets icon is tapped on the more page
          // If budgets were removed
          settingsPageStateKey.currentState?.refreshState();
          // User did choose one
          afterSet();
        }
      },
      child: navigationBarIconBuilder(navBarIconData),
    );
  }
}

class SelectNavBarShortcutPopup extends StatelessWidget {
  const SelectNavBarShortcutPopup(
      {required this.shortcutAppSettingKey, super.key});
  final String shortcutAppSettingKey;
  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        NavBarShortcutSelection(
          shortcutAppSettingKey: shortcutAppSettingKey,
          navBarIconDataKey: "home",
          onSettings: () {
            pushRoute(context, EditHomePage());
          },
        ),
        NavBarShortcutSelection(
          shortcutAppSettingKey: shortcutAppSettingKey,
          navBarIconDataKey: "transactions",
          onSettings: () {
            openBottomSheet(
              context,
              PopupFramework(
                hasPadding: false,
                child: TransactionsSettings(),
              ),
            );
          },
        ),
        NavBarShortcutSelection(
          shortcutAppSettingKey: shortcutAppSettingKey,
          navBarIconDataKey: "budgets",
          onSettings: () {
            openBottomSheet(
              context,
              PopupFramework(
                hasPadding: false,
                child: BudgetSettings(),
              ),
            );
          },
        ),
        NavBarShortcutSelection(
          shortcutAppSettingKey: shortcutAppSettingKey,
          navBarIconDataKey: "calendar",
        ),
        NavBarShortcutSelection(
          shortcutAppSettingKey: shortcutAppSettingKey,
          navBarIconDataKey: "goals",
          onSettings: () {
            openBottomSheet(
              context,
              PopupFramework(
                hasPadding: false,
                child: ObjectiveSettings(),
              ),
            );
          },
        ),
        NavBarShortcutSelection(
          shortcutAppSettingKey: shortcutAppSettingKey,
          navBarIconDataKey: "allSpending",
        ),
        NavBarShortcutSelection(
          shortcutAppSettingKey: shortcutAppSettingKey,
          navBarIconDataKey: "subscriptions",
          onSettings: () {
            openBottomSheet(
              context,
              PopupFramework(
                hasPadding: false,
                child: SubscriptionSettings(),
              ),
            );
          },
        ),
        NavBarShortcutSelection(
          shortcutAppSettingKey: shortcutAppSettingKey,
          navBarIconDataKey: "scheduled",
          onSettings: () {
            openBottomSheet(
              context,
              PopupFramework(
                hasPadding: false,
                child: UpcomingOverdueSettings(),
              ),
            );
          },
        ),
        NavBarShortcutSelection(
          shortcutAppSettingKey: shortcutAppSettingKey,
          navBarIconDataKey: "loans",
        ),
      ],
    );
  }
}

class NavBarShortcutSelection extends StatelessWidget {
  const NavBarShortcutSelection({
    required this.shortcutAppSettingKey,
    required this.navBarIconDataKey,
    this.onSettings,
    super.key,
  });

  final String shortcutAppSettingKey;
  final String navBarIconDataKey;
  final VoidCallback? onSettings;

  @override
  Widget build(BuildContext context) {
    NavBarIconData iconData = navBarIconsData[navBarIconDataKey]!;
    return Padding(
      padding: const EdgeInsetsDirectional.only(
        bottom: 5,
        top: 5,
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButtonStacked(
              filled:
                  appStateSettings[shortcutAppSettingKey] == navBarIconDataKey,
              alignStart: true,
              alignBeside: true,
              padding: onSettings == null
                  ? EdgeInsetsDirectional.symmetric(
                      horizontal: 20, vertical: 15)
                  : EdgeInsetsDirectional.only(
                      start: 20,
                      end: 5,
                      top: 3,
                      bottom: 3,
                    ),
              text: iconData.label.tr().capitalizeFirst,
              iconData: iconData.iconData,
              iconScale: iconData.iconScale,
              onTap: () async {
                await updateSettings(shortcutAppSettingKey, navBarIconDataKey,
                    updateGlobalState: false);
                popRoute(context, true);
              },
              infoButton: onSettings == null
                  ? null
                  : IconButton(
                      padding: EdgeInsetsDirectional.all(15),
                      onPressed: onSettings,
                      icon: Icon(
                        appStateSettings["outlinedIcons"]
                            ? Icons.settings_outlined
                            : Icons.settings_rounded,
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

class NavBarIcon extends StatelessWidget {
  const NavBarIcon({
    required this.onItemTapped,
    required this.icon,
    required this.navigationBarIndex,
    required this.currentNavigationBarIndex,
    this.customIconScale = 1,
    super.key,
  });
  final Function(int index) onItemTapped;
  final IconData icon;
  final int navigationBarIndex;
  final int currentNavigationBarIndex;
  final double customIconScale;

  @override
  Widget build(BuildContext context) {
    bool selected = navigationBarIndex == currentNavigationBarIndex;
    return Stack(
      alignment: AlignmentDirectional.center,
      children: [
        selected
            ? ScaleIn(
                duration: Duration(milliseconds: 200),
                curve: Curves.fastOutSlowIn,
                child: Container(
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Theme.of(context).colorScheme.secondaryContainer
                        : Theme.of(context)
                            .colorScheme
                            .secondary
                            .withOpacity(0.3),
                  ),
                  height: 52,
                  width: 52,
                  margin: EdgeInsetsDirectional.all(5),
                ),
              )
            : Container(
                color: Colors.transparent,
                height: 52,
                width: 52,
                margin: EdgeInsetsDirectional.all(5),
              ),
        IconButton(
          padding: EdgeInsetsDirectional.all(15),
          color: selected
              ? Theme.of(context).colorScheme.onSecondaryContainer
              : null,
          icon: Transform.scale(
            scale: customIconScale,
            child: Icon(
              icon,
              size: 27,
            ),
          ),
          onPressed: () {
            onItemTapped(navigationBarIndex);
          },
        ),
      ],
    );
  }
}
