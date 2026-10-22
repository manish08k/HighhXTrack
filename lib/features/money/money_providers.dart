import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/utils/dates.dart';
import '../../data/models/money.dart';
import '../../data/repositories/base.dart';
import '../../data/repositories/money_repo.dart';
import '../../state/providers.dart';

class MonthNotifier extends Notifier<DateTime> {
  @override
  DateTime build() => D.startOfMonth(DateTime.now());
  void set(DateTime m) => state = D.startOfMonth(m);
  void shift(int months) => state = D.addMonths(state, months);
}

/// Month currently shown in the Money module.
final moneyMonthProvider = NotifierProvider<MonthNotifier, DateTime>(MonthNotifier.new);

final moneyCategoriesProvider = FutureProvider.autoDispose<List<MoneyCategory>>((ref) {
  ref.watchTopics([Chg.money]);
  return ref.read(moneyRepoProvider).categories();
});

final transactionsProvider = FutureProvider.autoDispose.family<List<Txn>, TxQuery>((ref, q) {
  ref.watchTopics([Chg.money]);
  return ref.read(moneyRepoProvider).transactions(q);
});

final monthSummaryProvider = FutureProvider.autoDispose.family<MonthSummary, DateTime>((ref, month) {
  ref.watchTopics([Chg.money, Chg.settings]);
  final budget = ref.watch(settingsProvider.select((s) => s.monthlyBudget));
  return ref.read(moneyRepoProvider).summary(month, budget: budget);
});

final dailySpendingProvider = FutureProvider.autoDispose.family<List<int>, DateTime>((ref, month) {
  ref.watchTopics([Chg.money]);
  return ref.read(moneyRepoProvider).dailySpending(month);
});

final monthlyTotalsProvider = FutureProvider.autoDispose<List<(DateTime, int, int)>>((ref) {
  ref.watchTopics([Chg.money]);
  return ref.read(moneyRepoProvider).monthly(6);
});

final recurringProvider = FutureProvider.autoDispose<List<RecurringTxn>>((ref) {
  ref.watchTopics([Chg.money]);
  return ref.read(moneyRepoProvider).recurring();
});

final upcomingBillsProvider = FutureProvider.autoDispose<List<RecurringTxn>>((ref) {
  ref.watchTopics([Chg.money]);
  return ref.read(moneyRepoProvider).upcoming(days: 7);
});

final txnProvider = FutureProvider.autoDispose.family<Txn?, int>((ref, id) {
  ref.watchTopics([Chg.money]);
  return ref.read(moneyRepoProvider).get(id);
});
