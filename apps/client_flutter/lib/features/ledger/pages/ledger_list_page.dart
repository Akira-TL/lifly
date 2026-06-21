import 'package:flutter/material.dart';

class LedgerListPage extends StatelessWidget {
  const LedgerListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('记账')),
      body: const Center(child: Text('账单列表')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
