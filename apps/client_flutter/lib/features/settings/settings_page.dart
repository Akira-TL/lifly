import 'package:flutter/material.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        children: const [
          ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('同步状态'),
            subtitle: Text('未连接'),
          ),
          ListTile(
            leading: Icon(Icons.storage_outlined),
            title: Text('数据管理'),
          ),
          ListTile(
            leading: Icon(Icons.info_outline),
            title: Text('关于 Lifily'),
            subtitle: Text('v0.1.0'),
          ),
        ],
      ),
    );
  }
}
