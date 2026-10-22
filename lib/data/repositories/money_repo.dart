import '../../core/utils/dates.dart';
import '../models/money.dart';
import 'base.dart';

class TxQuery {
  const TxQuery({required this.month, this.kind, this.categoryId, this.search = ''});
  final DateTime month;
  final TxKind? kind;
  final int? categoryId;
  final String search;

  @override
  bool operator ==(Object other) => other is TxQuery && other.month == month && other.kind == kind && other.categoryId == categoryId && other.search == search;

  @override
  int get hashCode => Object.hash(month, kind, categoryId, search);
}

class MoneyRepo extends Repo {
  MoneyRepo(super.db, super.changed);

  // ------------------------------------------------------------ categories
  Future<List<MoneyCategory>> categories({TxKind? kind}) async {
    final rows = await db.query(
      'money_categories',
      where: kind == null ? null : 'kind=?',
      whereArgs: kind == null ? null : [kind.index],
      orderBy: 'kind, position, id',
    );
    return rows.map(MoneyCategory.fromMap).toList();
  }

  Future<int> saveCategory(MoneyCategory c) async {
    final int id;
    if (c.id == null) {
      final pos = (await db.rawQuery('SELECT COALESCE(MAX(position),0)+1 p FROM money_categories')).first['p'] as int;
      id = await db.insert('money_categories', c.toMap()..['position'] = pos);
    } else {
      id = c.id!;
      await db.update('money_categories', c.toMap(), where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.money);
    return id;
  }

  Future<void> setCategoryBudget(int id, int? budget) async {
    await db.update('money_categories', {'budget': budget}, where: 'id=?', whereArgs: [id]);
    changed(Chg.money);
  }

  Future<void> deleteCategory(int id) async {
    await db.delete('money_categories', where: 'id=?', whereArgs: [id]);
    changed(Chg.money);
  }

  // ------------------------------------------------------------ transactions
  Future<List<Txn>> transactions(TxQuery q) async {
    final where = <String>['date_at>=? AND date_at<?'];
    final args = <Object?>[D.ms(D.startOfMonth(q.month)), D.ms(D.startOfNextMonth(q.month))];
    if (q.kind != null) {
      where.add('kind=?');
      args.add(q.kind!.index);
    }
    if (q.categoryId != null) {
      where.add('category_id=?');
      args.add(q.categoryId);
    }
    if (q.search.trim().isNotEmpty) {
      where.add(
        "(notes LIKE ? ESCAPE '\\' OR payment_method LIKE ? ESCAPE '\\' OR category_id IN (SELECT id FROM money_categories WHERE name LIKE ? ESCAPE '\\'))",
      );
      final l = Repo.like(q.search.trim());
      args.addAll([l, l, l]);
    }
    final rows = await db.query('transactions', where: where.join(' AND '), whereArgs: args, orderBy: 'date_at DESC, id DESC');
    return rows.map(Txn.fromMap).toList();
  }

  Future<List<Txn>> recent({int limit = 5}) async => (await db.query('transactions', orderBy: 'date_at DESC, id DESC', limit: limit)).map(Txn.fromMap).toList();

  Future<Txn?> get(int id) async {
    final rows = await db.query('transactions', where: 'id=?', whereArgs: [id]);
    return rows.isEmpty ? null : Txn.fromMap(rows.first);
  }

  Future<int> save(Txn t) async {
    final int id;
    if (t.id == null) {
      id = await db.insert('transactions', t.toMap());
    } else {
      id = t.id!;
      await db.update('transactions', t.toMap(), where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.money);
    return id;
  }

  Future<Map<String, Object?>?> delete(int id) async {
    final rows = await db.query('transactions', where: 'id=?', whereArgs: [id]);
    await db.delete('transactions', where: 'id=?', whereArgs: [id]);
    changed(Chg.money);
    return rows.isEmpty ? null : rows.first;
  }

  Future<void> restore(Map<String, Object?> row) async {
    await db.insert('transactions', row);
    changed(Chg.money);
  }

  // ------------------------------------------------------------ analytics
  Future<MonthSummary> summary(DateTime month, {int? budget}) async {
    final from = D.ms(D.startOfMonth(month));
    final to = D.ms(D.startOfNextMonth(month));
    final totals = await db.rawQuery('SELECT kind, SUM(amount) s FROM transactions WHERE date_at>=? AND date_at<? GROUP BY kind', [from, to]);
    var income = 0, expense = 0;
    for (final r in totals) {
      if (r['kind'] == 1) {
        income = (r['s'] as int?) ?? 0;
      } else {
        expense = (r['s'] as int?) ?? 0;
      }
    }
    final cats = await db.rawQuery(
      'SELECT category_id, SUM(amount) s FROM transactions WHERE kind=0 AND date_at>=? AND date_at<? GROUP BY category_id ORDER BY s DESC',
      [from, to],
    );
    final today = await db.rawQuery('SELECT SUM(amount) s FROM transactions WHERE kind=0 AND date_at>=? AND date_at<=?', [
      D.ms(D.today()),
      D.ms(D.endOfDay(DateTime.now())),
    ]);
    return MonthSummary(
      month: D.startOfMonth(month),
      income: income,
      expense: expense,
      budget: budget,
      byCategory: {for (final r in cats) r['category_id'] as int?: (r['s'] as int?) ?? 0},
      spentToday: (today.first['s'] as int?) ?? 0,
    );
  }

  /// Expense per day of [month].
  Future<List<int>> dailySpending(DateTime month) async {
    final days = D.daysInMonth(month.year, month.month);
    final out = List<int>.filled(days, 0);
    final rows = await db.query(
      'transactions',
      columns: ['date_at', 'amount'],
      where: 'kind=0 AND date_at>=? AND date_at<?',
      whereArgs: [D.ms(D.startOfMonth(month)), D.ms(D.startOfNextMonth(month))],
    );
    for (final r in rows) {
      out[D.fromMs(r['date_at'] as int).day - 1] += r['amount'] as int;
    }
    return out;
  }

  /// (month, income, expense) for the last [months] months, oldest first.
  Future<List<(DateTime, int, int)>> monthly(int months) async {
    final start = D.addMonths(D.startOfMonth(DateTime.now()), -(months - 1));
    final rows = await db.query('transactions', columns: ['date_at', 'amount', 'kind'], where: 'date_at>=?', whereArgs: [D.ms(start)]);
    final inc = List<int>.filled(months, 0);
    final exp = List<int>.filled(months, 0);
    for (final r in rows) {
      final d = D.fromMs(r['date_at'] as int);
      final idx = (d.year - start.year) * 12 + d.month - start.month;
      if (idx < 0 || idx >= months) continue;
      if (r['kind'] == 1) {
        inc[idx] += r['amount'] as int;
      } else {
        exp[idx] += r['amount'] as int;
      }
    }
    return [for (var k = 0; k < months; k++) (D.addMonths(start, k), inc[k], exp[k])];
  }

  /// Expense amounts per category id for a month.
  Future<Map<int?, int>> categorySpend(DateTime month) async => (await summary(month)).byCategory;

  // ------------------------------------------------------------ recurring
  Future<List<RecurringTxn>> recurring() async =>
      (await db.query('recurring_transactions', orderBy: 'active DESC, next_at ASC')).map(RecurringTxn.fromMap).toList();

  Future<int> saveRecurring(RecurringTxn r) async {
    final int id;
    if (r.id == null) {
      id = await db.insert('recurring_transactions', r.toMap());
    } else {
      id = r.id!;
      await db.update('recurring_transactions', r.toMap(), where: 'id=?', whereArgs: [id]);
    }
    changed(Chg.money);
    return id;
  }

  Future<void> deleteRecurring(int id) async {
    await db.delete('recurring_transactions', where: 'id=?', whereArgs: [id]);
    changed(Chg.money);
  }

  /// Marks one occurrence of a recurring item as paid now and advances it.
  Future<void> payRecurringNow(RecurringTxn r) async {
    await db.transaction((tx) async {
      await tx.insert(
        'transactions',
        Txn(
          kind: r.kind,
          amount: r.amount,
          categoryId: r.categoryId,
          date: DateTime.now(),
          paymentMethod: r.paymentMethod,
          notes: r.title,
          recurringId: r.id,
          createdAt: DateTime.now(),
        ).toMap(),
      );
      final next = r.recurrence.nextAfter(r.anchor, r.next);
      await tx.update('recurring_transactions', {'next_at': D.ms(next ?? r.next), if (next == null) 'active': 0}, where: 'id=?', whereArgs: [r.id]);
    });
    changed(Chg.money);
  }

  /// Creates transactions for auto-add items whose date has passed.
  /// Returns the number created. Safe to call repeatedly.
  Future<int> processDue({DateTime? now}) async {
    now ??= DateTime.now();
    var created = 0;
    final due = await db.query('recurring_transactions', where: 'active=1 AND auto_add=1 AND next_at<=?', whereArgs: [D.ms(now)]);
    if (due.isEmpty) return 0;
    await db.transaction((tx) async {
      for (final row in due) {
        final r = RecurringTxn.fromMap(row);
        DateTime? next = r.next;
        var guard = 0;
        while (next != null && !next.isAfter(now!) && guard++ < 400) {
          await tx.insert(
            'transactions',
            Txn(
              kind: r.kind,
              amount: r.amount,
              categoryId: r.categoryId,
              date: next,
              paymentMethod: r.paymentMethod,
              notes: r.title,
              recurringId: r.id,
              createdAt: DateTime.now(),
            ).toMap(),
          );
          created++;
          next = r.recurrence.nextAfter(r.anchor, next);
        }
        await tx.update(
          'recurring_transactions',
          {'next_at': next == null ? row['next_at'] : D.ms(next), if (next == null) 'active': 0},
          where: 'id=?',
          whereArgs: [r.id],
        );
      }
    });
    if (created > 0) changed(Chg.money);
    return created;
  }

  Future<List<RecurringTxn>> upcoming({int days = 7}) async {
    final rows = await db.query(
      'recurring_transactions',
      where: 'active=1 AND next_at<=?',
      whereArgs: [D.ms(D.endOfDay(D.addDays(DateTime.now(), days)))],
      orderBy: 'next_at',
    );
    return rows.map(RecurringTxn.fromMap).toList();
  }
}
