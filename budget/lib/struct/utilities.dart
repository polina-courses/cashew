// Локальная версия: вкладка «ЖКХ» — свои пункты, отметка оплаты раз в месяц,
// учёт переплат. Чистая логика без БД, хранится в настройках (ключ `utilities`).

int utilityMonthIndex(DateTime d) => d.year * 12 + d.month - 1;

class UtilityItem {
  UtilityItem({
    required this.id,
    required this.name,
    this.amount = 0,
    this.credit = 0,
    this.paidMonth,
    this.paidAmount = 0,
    this.paidOn,
    this.creditBeforePay = 0,
  });

  final String id;
  String name;

  /// Обычная сумма за месяц (0 — сумма меняется, баланс не ведётся).
  double amount;

  /// Баланс: больше нуля — переплата, меньше нуля — недоплата.
  double credit;

  /// Месяц последней оплаты (utilityMonthIndex). Сам «сбрасывается» 1 числа:
  /// оплата считается текущей, только если месяц совпадает.
  int? paidMonth;
  double paidAmount;
  DateTime? paidOn;
  double creditBeforePay;

  bool isPaid(DateTime now) => paidMonth == utilityMonthIndex(now);

  /// Сколько нужно заплатить в этом месяце с учётом переплаты (не меньше 0).
  double due() {
    if (amount <= 0) return 0;
    double v = amount - credit;
    return v < 0 ? 0 : v;
  }

  /// Отметить оплату. Переплата/недоплата считается от обычной суммы.
  void markPaid(double paid, DateTime now) {
    creditBeforePay = credit;
    if (amount > 0) credit = _round(credit + paid - amount);
    paidAmount = paid;
    paidMonth = utilityMonthIndex(now);
    paidOn = now;
  }

  /// Снять отметку (ошибся): баланс возвращается как был.
  void unmarkPaid() {
    if (paidMonth != null) credit = creditBeforePay;
    paidMonth = null;
    paidAmount = 0;
    paidOn = null;
    creditBeforePay = 0;
  }

  Map<String, dynamic> toJson() => {
        "id": id,
        "n": name,
        "a": amount,
        "c": credit,
        "pm": paidMonth,
        "pa": paidAmount,
        "po": paidOn?.toIso8601String(),
        "cb": creditBeforePay,
      };

  static UtilityItem fromJson(Map m) => UtilityItem(
        id: m["id"].toString(),
        name: (m["n"] ?? "").toString(),
        amount: (m["a"] as num?)?.toDouble() ?? 0,
        credit: (m["c"] as num?)?.toDouble() ?? 0,
        paidMonth: (m["pm"] as num?)?.toInt(),
        paidAmount: (m["pa"] as num?)?.toDouble() ?? 0,
        paidOn: m["po"] == null ? null : DateTime.tryParse(m["po"].toString()),
        creditBeforePay: (m["cb"] as num?)?.toDouble() ?? 0,
      );
}

double _round(double v) => (v * 100).roundToDouble() / 100;

List<UtilityItem> utilitiesFromSettings(dynamic raw) {
  if (raw is! List) return [];
  return [
    for (final m in raw)
      if (m is Map) UtilityItem.fromJson(m)
  ];
}

List<Map<String, dynamic>> utilitiesToSettings(List<UtilityItem> items) =>
    [for (final i in items) i.toJson()];

/// Сколько ещё не оплачено в этом месяце (по пунктам с суммой).
double utilitiesLeftToPay(List<UtilityItem> items, DateTime now) {
  double sum = 0;
  for (final i in items) {
    if (!i.isPaid(now)) sum += i.due();
  }
  return sum;
}
