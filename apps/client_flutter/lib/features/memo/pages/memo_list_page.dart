import 'package:flutter/material.dart';

class MemoListPage extends StatelessWidget {
  const MemoListPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('备忘录')),
      body: const Center(child: Text('备忘录列表')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {},
        child: const Icon(Icons.add),
      ),
    );
  }
}
