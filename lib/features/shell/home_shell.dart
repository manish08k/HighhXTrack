import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/tokens.dart';
import '../../core/widgets/cards.dart';
import '../../state/providers.dart';
import '../calendar/calendar_screen.dart';
import '../home/home_screen.dart';
import '../insights/insights_screen.dart';
import '../money/money_screen.dart';
import '../search/search_screen.dart';
import '../settings/settings_screen.dart';
import '../todo/todo_screen.dart';
import 'nav.dart';

/// Root scaffold with bottom navigation. Tabs are kept alive in an
/// IndexedStack so scroll position and state survive tab switches.
class HomeShell extends ConsumerWidget {
  const HomeShell({super.key});

  static const _tabs = [HomeScreen(), TodoScreen(), CalendarScreen(), MoneyScreen(), MoreScreen()];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(tabProvider);
    return PopScope(
      canPop: index == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) ref.read(tabProvider.notifier).select(0);
      },
      child: Scaffold(
        body: IndexedStack(
          index: index,
          children: [for (var i = 0; i < _tabs.length; i++) TickerMode(enabled: i == index, child: _tabs[i])],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: index,
          onDestinationSelected: ref.read(tabProvider.notifier).select,
          destinations: const [
            NavigationDestination(icon: Icon(Icons.space_dashboard_outlined), selectedIcon: Icon(Icons.space_dashboard_rounded), label: 'Home'),
            NavigationDestination(icon: Icon(Icons.check_circle_outline_rounded), selectedIcon: Icon(Icons.check_circle_rounded), label: 'Todo'),
            NavigationDestination(icon: Icon(Icons.calendar_month_outlined), selectedIcon: Icon(Icons.calendar_month_rounded), label: 'Calendar'),
            NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), selectedIcon: Icon(Icons.account_balance_wallet_rounded), label: 'Money'),
            NavigationDestination(icon: Icon(Icons.apps_outlined), selectedIcon: Icon(Icons.apps_rounded), label: 'More'),
          ],
        ),
      ),
    );
  }
}

class MoreScreen extends ConsumerWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(automaticallyImplyLeading: false, title: const Text('All modules')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(Gap.page, Gap.sm, Gap.page, Gap.xxxl),
        children: [
          const ModuleGrid(),
          const SectionHeader('Tools', padding: EdgeInsets.fromLTRB(0, Gap.xl, 0, Gap.sm)),
          AppCard(
            padding: const EdgeInsets.symmetric(vertical: Gap.xs),
            child: Column(
              children: [
                ListTile(
                  leading: const Icon(Icons.search_rounded),
                  title: const Text('Search everything'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(context, const SearchScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.insights_rounded),
                  title: const Text('Insights & statistics'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(context, const InsightsScreen()),
                ),
                ListTile(
                  leading: const Icon(Icons.settings_outlined),
                  title: const Text('Settings'),
                  trailing: const Icon(Icons.chevron_right_rounded),
                  onTap: () => push(context, const SettingsScreen()),
                ),
              ],
            ),
          ),
          const SizedBox(height: Gap.xl),
          Center(
            child: Text('HighhXTrack', style: context.text.labelLarge!.copyWith(color: context.colors.onSurfaceVariant)),
          ),
        ],
      ),
    );
  }
}
