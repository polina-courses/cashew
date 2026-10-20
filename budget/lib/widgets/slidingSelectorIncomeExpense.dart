import 'package:budget/colors.dart';
import 'package:budget/functions.dart';
import 'package:budget/struct/settings.dart';
import 'package:budget/widgets/openBottomSheet.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';

// Локальная версия: подпись вкладки уменьшается под ширину, а не вылезает за неё
Widget _tabLabel(String text) {
  return Padding(
    padding: const EdgeInsetsDirectional.only(top: 5.0),
    child: FittedBox(
      fit: BoxFit.scaleDown,
      child: Text(
        text,
        maxLines: 1,
        softWrap: false,
        style: TextStyle(
          fontSize: 14,
          fontFamily: appStateSettings["font"],
          fontFamilyFallback: ['Inter'],
        ),
      ),
    ),
  );
}

class SlidingSelectorIncomeExpense extends StatelessWidget {
  const SlidingSelectorIncomeExpense({
    Key? key,
    required this.onSelected,
    this.alternateTheme = false,
    this.useHorizontalPaddingConstrained = true,
    this.customPadding,
    this.options,
    this.initialIndex,
  }) : super(key: key);

  final Function(int) onSelected;
  final bool alternateTheme;
  final bool useHorizontalPaddingConstrained;
  final EdgeInsetsDirectional? customPadding;
  final List<String>? options;
  final int? initialIndex;

  @override
  Widget build(BuildContext context) {
    BorderRadius borderRadius = getPlatform() == PlatformOS.isIOS
        ? BorderRadius.circular(10)
        : BorderRadius.circular(15);
    return Padding(
      padding: EdgeInsetsDirectional.symmetric(
          horizontal: useHorizontalPaddingConstrained == false
              ? 0
              : getHorizontalPaddingConstrained(context)),
      child: Padding(
        padding: customPadding ??
            (alternateTheme
                ? const EdgeInsetsDirectional.symmetric(horizontal: 20)
                : const EdgeInsetsDirectional.symmetric(horizontal: 13)),
        child: Container(
          decoration: BoxDecoration(
            boxShadow: appStateSettings["materialYou"]
                ? []
                : boxShadowCheck(
                    boxShadowGeneral(context),
                  ),
          ),
          child: DefaultTabController(
            length: options != null ? options!.length : 3,
            initialIndex: initialIndex ?? 0,
            child: SizedBox(
              height: alternateTheme ? 40 : 45,
              child: Material(
                borderRadius: borderRadius,
                color: appStateSettings["materialYou"]
                    ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
                    : getColor(context, "lightDarkAccentHeavyLight"),
                child: TabBar(
                  splashFactory: getPlatform() == PlatformOS.isIOS
                      ? NoSplash.splashFactory
                      : null,
                  splashBorderRadius: borderRadius,
                  onTap: (value) {
                    onSelected(value + 1);
                  },
                  // Локальная версия: меньше боковых отступов, чтобы длинные подписи
                  // («Просроченные») помещались в узкие вкладки
                  labelPadding:
                      const EdgeInsetsDirectional.symmetric(horizontal: 4),
                  dividerColor: Colors.transparent,
                  indicatorColor: Colors.transparent,
                  indicatorSize: TabBarIndicatorSize.tab,
                  indicator: BoxDecoration(
                    color: appStateSettings["materialYou"]
                        ? Theme.of(context).colorScheme.primary.withOpacity(0.3)
                        : getColor(context, "black").withOpacity(0.15),
                    borderRadius: borderRadius,
                  ),
                  labelColor: getColor(context, "black"),
                  unselectedLabelColor: getColor(context, "textLight"),
                  tabs: options == null
                      ? [
                          Tab(
                            child: _tabLabel("all".tr()),
                          ),
                          Tab(
                            child: _tabLabel("expense".tr()),
                          ),
                          Tab(
                            child: _tabLabel("income".tr()),
                          ),
                        ]
                      : [
                          for (String option in options!)
                            Tab(
                              child: _tabLabel(option.tr()),
                            ),
                        ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
