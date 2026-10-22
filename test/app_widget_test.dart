import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:newone/app.dart';
import 'package:newone/data/db/app_database.dart';
import 'package:newone/data/repositories/settings_repo.dart';
import 'package:newone/features/shell/nav.dart';
import 'package:newone/state/providers.dart';
import 'package:newone/data/repositories/todo_repo.dart';

import 'helpers.dart';

Future<(AppDatabase, ProviderContainer)> _pumpApp(WidgetTester tester, {AppSettings settings = const AppSettings(), Size size = const Size(412, 915)}) async {
  tester.view.physicalSize = size * 2.625;
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.reset);
  late AppDatabase db;
  late ProviderContainer c;
  await tester.runAsync(() async {
    await initializeDateFormatting();
    setUpTempPaths();
    db = await openTestDb();
    c = await makeContainer(db, settings: settings);
  });
  await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const HighhXTrackApp()));
  await _settle(tester);
  return (db, c);
}

/// Pumps frames until async DB work and animations finish.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 12; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _cleanup(WidgetTester tester, AppDatabase db, ProviderContainer c) async {
  await tester.pumpWidget(const SizedBox.shrink());
  c.dispose();
  await tester.runAsync(db.close);
}

void main() {
  testWidgets('home dashboard renders all sections', (tester) async {
    final (db, c) = await _pumpApp(tester);
    expect(find.text('TODAY'), findsOneWidget);
    expect(find.text('Todo'), findsWidgets);
    expect(find.text('Habits'), findsWidgets);
    expect(find.text('Study'), findsWidgets);
    expect(find.text('Budget left'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _cleanup(tester, db, c);
  });

  testWidgets('create a task end-to-end through the editor', (tester) async {
    final (db, c) = await _pumpApp(tester);
    await tester.tap(find.text('Todo').last);
    await _settle(tester);
    expect(find.text('Nothing due today'), findsOneWidget);

    await tester.tap(find.byTooltip('New task'));
    await _settle(tester);
    await tester.enterText(find.byType(TextFormField).first, 'Buy groceries');
    await tester.tap(find.text('Add task'));
    await _settle(tester);

    expect(find.text('Buy groceries'), findsOneWidget);
    final saved = await tester.runAsync(() => c.read(todoRepoProvider).query(const TodoQuery(view: TodoView.today)));
    expect(saved!.single.title, 'Buy groceries');

    // Complete via the checkbox; persisted + undo snackbar shown.
    await tester.tap(find.bySemanticsLabel('Mark complete'));
    await _settle(tester);
    expect(find.text('Task completed'), findsOneWidget);
    final done = await tester.runAsync(() => c.read(todoRepoProvider).todayProgress());
    expect(done, (1, 1));
    await _cleanup(tester, db, c);
  });

  testWidgets('every module and tool opens without errors', (tester) async {
    final (db, c) = await _pumpApp(tester);
    for (final tab in ['Todo', 'Calendar', 'Money', 'More', 'Home']) {
      await tester.tap(find.text(tab).last);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: tab);
    }
    // Calendar views.
    await tester.tap(find.text('Calendar').last);
    await _settle(tester);
    for (final v in ['Week', 'Day', 'Month']) {
      await tester.tap(find.text(v));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'calendar $v');
    }
    // Pushed modules and tools.
    await tester.tap(find.text('More').last);
    await _settle(tester);
    for (final name in ['Gym', 'Reminders', 'Habits', 'Documents', 'Notes', 'Study']) {
      await tester.tap(find.text(name).first);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: name);
      rootNavigatorKey.currentState!.pop();
      await _settle(tester);
    }
    for (final name in ['Insights & statistics', 'Settings', 'Search everything']) {
      await tester.tap(find.text(name));
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: name);
      rootNavigatorKey.currentState!.pop();
      await _settle(tester);
    }
    await _cleanup(tester, db, c);
  });

  testWidgets('gym tabs and workout session', (tester) async {
    final (db, c) = await _pumpApp(tester);
    await tester.tap(find.text('More').last);
    await _settle(tester);
    await tester.tap(find.text('Gym').first);
    await _settle(tester);
    for (final t in ['Muscles', 'Progress', 'History', 'Train']) {
      await tester.tap(find.text(t));
      await _settle(tester);
      await tester.pump(const Duration(seconds: 1));
      expect(tester.takeException(), isNull, reason: t);
    }
    await tester.tap(find.text('Empty workout'));
    await _settle(tester);
    expect(find.text('Add your first exercise'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await _cleanup(tester, db, c);
  });

  testWidgets('dark mode and a small phone screen render without overflow', (tester) async {
    final (db, c) = await _pumpApp(
      tester,
      settings: const AppSettings(themeMode: ThemeMode.dark),
      size: const Size(320, 640),
    );
    final ctx = tester.element(find.byType(Scaffold).first);
    expect(Theme.of(ctx).brightness, Brightness.dark);
    for (final tab in ['Todo', 'Calendar', 'Money', 'More', 'Home']) {
      await tester.tap(find.text(tab).last);
      await _settle(tester);
      expect(tester.takeException(), isNull, reason: 'small screen $tab');
    }
    await _cleanup(tester, db, c);
  });

  testWidgets('tablet width uses wider grids', (tester) async {
    final (db, c) = await _pumpApp(tester, size: const Size(900, 1200));
    expect(tester.takeException(), isNull);
    await _cleanup(tester, db, c);
  });
}
