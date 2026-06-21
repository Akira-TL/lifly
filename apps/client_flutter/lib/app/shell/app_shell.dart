import 'package:flutter/material.dart';
import 'package:client_flutter/features/memo/pages/memo_list_page.dart';
import 'package:client_flutter/features/ledger/pages/ledger_list_page.dart';
import 'package:client_flutter/features/task/pages/task_list_page.dart';
import 'package:client_flutter/features/settings/settings_page.dart';

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentIndex = 0;

  final pages = const [
    MemoListPage(),
    LedgerListPage(),
    TaskListPage(),
    SettingsPage(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: pages[_currentIndex],
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentIndex,
        onDestinationSelected: (i) => setState(() => _currentIndex = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.note_outlined), label: '备忘'),
          NavigationDestination(icon: Icon(Icons.account_balance_wallet_outlined), label: '记账'),
          NavigationDestination(icon: Icon(Icons.check_circle_outline), label: '任务'),
          NavigationDestination(icon: Icon(Icons.settings_outlined), label: '设置'),
        ],
      ),
    );
  }
}
