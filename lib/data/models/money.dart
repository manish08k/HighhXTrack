import 'dart:ui';

import '../../core/utils/dates.dart';
import '../../core/utils/recurrence.dart';
import 'common.dart';

enum TxKind {
  expense('Expense'),
  income('Income');

  const TxKind(this.label);
  final String label;
}

const kPaymentMethods = ['Cash', 'UPI', 'Debit card', 'Credit card', 'Bank transfer', 'Wallet', 'Other'];

class MoneyCategory {
  const MoneyCategory({
    this.id,
    required this.name,
    this.kind = TxKind.expense,
    required this.icon,
    required this.color,
    this.budget,
    this.isDefault = false,
    this.position = 0,
  });
  final int? id;
  final String name;
  final TxKind kind;
  final int icon;
  final int color;

  /// Monthly budget in minor units, if set.
  final int? budget;
  final bool isDefault;
  final int position;

  Color get colorValue => Color(color);

  factory MoneyCategory.fromMap(Map<String, Object?> m) => MoneyCategory(
    id: m['id'] as int,
    name: m['name'] as String,
    kind: TxKind.values[(m['kind'] as int? ?? 0).clamp(0, 1)],
    icon: m['icon'] as int,
    color: m['color'] as int,
    budget: m['budget'] as int?,
    isDefault: b(m['is_default']),
    position: m['position'] as int? ?? 0,
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'name': name,
    'kind': kind.index,
    'icon': icon,
    'color': color,
    'budget': budget,
    'is_default': i(isDefault),
    'position': position,
  };
}

class Txn {
  const Txn({
    this.id,
    required this.kind,
    required this.amount,
    this.categoryId,
    required this.date,
    this.paymentMethod = '',
    this.notes = '',
    this.recurringId,
    required this.createdAt,
  });
  final int? id;
  final TxKind kind;
  final int amount;
  final int? categoryId;
  final DateTime date;
  final String paymentMethod;
  final String notes;
  final int? recurringId;
  final DateTime createdAt;

  int get signed => kind == TxKind.income ? amount : -amount;

  factory Txn.fromMap(Map<String, Object?> m) => Txn(
    id: m['id'] as int,
    kind: TxKind.values[(m['kind'] as int? ?? 0).clamp(0, 1)],
    amount: m['amount'] as int,
    categoryId: m['category_id'] as int?,
    date: D.fromMs(m['date_at'] as int),
    paymentMethod: m['payment_method'] as String? ?? '',
    notes: m['notes'] as String? ?? '',
    recurringId: m['recurring_id'] as int?,
    createdAt: D.fromMs(m['created_at'] as int),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'kind': kind.index,
    'amount': amount,
    'category_id': categoryId,
    'date_at': D.ms(date),
    'payment_method': paymentMethod,
    'notes': notes,
    'recurring_id': recurringId,
    'created_at': D.ms(createdAt),
  };
}

class RecurringTxn {
  const RecurringTxn({
    this.id,
    required this.title,
    this.kind = TxKind.expense,
    required this.amount,
    this.categoryId,
    this.paymentMethod = '',
    required this.recurrence,
    required this.anchor,
    required this.next,
    this.autoAdd = true,
    this.remind = true,
    this.active = true,
  });
  final int? id;
  final String title;
  final TxKind kind;
  final int amount;
  final int? categoryId;
  final String paymentMethod;
  final Recurrence recurrence;
  final DateTime anchor;
  final DateTime next;
  final bool autoAdd;
  final bool remind;
  final bool active;

  factory RecurringTxn.fromMap(Map<String, Object?> m) => RecurringTxn(
    id: m['id'] as int,
    title: m['title'] as String,
    kind: TxKind.values[(m['kind'] as int? ?? 0).clamp(0, 1)],
    amount: m['amount'] as int,
    categoryId: m['category_id'] as int?,
    paymentMethod: m['payment_method'] as String? ?? '',
    recurrence: Recurrence.decode(m['recurrence'] as String?),
    anchor: D.fromMs(m['anchor_at'] as int),
    next: D.fromMs(m['next_at'] as int),
    autoAdd: b(m['auto_add']),
    remind: b(m['remind']),
    active: b(m['active']),
  );

  Map<String, Object?> toMap() => {
    if (id != null) 'id': id,
    'title': title,
    'kind': kind.index,
    'amount': amount,
    'category_id': categoryId,
    'payment_method': paymentMethod,
    'recurrence': recurrence.encode(),
    'anchor_at': D.ms(anchor),
    'next_at': D.ms(next),
    'auto_add': i(autoAdd),
    'remind': i(remind),
    'active': i(active),
  };
}

class MonthSummary {
  const MonthSummary({required this.month, this.income = 0, this.expense = 0, this.budget, this.byCategory = const {}, this.spentToday = 0});
  final DateTime month;
  final int income;
  final int expense;
  final int? budget;
  final Map<int?, int> byCategory;
  final int spentToday;

  int get savings => income - expense;
  int? get remaining => budget == null ? null : budget! - expense;
  double get budgetUsed => (budget == null || budget == 0) ? 0 : expense / budget!;
}
