import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/device/device_contracts.dart';
import 'package:client_flutter/features/settings/account_device_runtime.dart';
import 'package:flutter/material.dart';

class AccountDeviceSettingsSection extends StatefulWidget {
  final ApiClient api;
  final AccountDeviceRuntime? runtime;

  const AccountDeviceSettingsSection({
    super.key,
    required this.api,
    this.runtime,
  });

  @override
  State<AccountDeviceSettingsSection> createState() =>
      _AccountDeviceSettingsSectionState();
}

class _AccountDeviceSettingsSectionState
    extends State<AccountDeviceSettingsSection> {
  late final AccountDeviceRuntime _runtime;
  final _phone = TextEditingController();
  final _password = TextEditingController();
  final _displayName = TextEditingController();
  AccountDeviceSnapshot _snapshot = const AccountDeviceSnapshot();
  String? _error;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _runtime = widget.runtime ?? DefaultAccountDeviceRuntime(widget.api);
    _reload();
  }

  @override
  void dispose() {
    _phone.dispose();
    _password.dispose();
    _displayName.dispose();
    super.dispose();
  }

  Future<void> _reload() => _run(_runtime.load);

  Future<void> _run(Future<AccountDeviceSnapshot> Function() operation) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final snapshot = await operation();
      if (!mounted) return;
      setState(() => _snapshot = snapshot);
    } catch (error) {
      if (!mounted) return;
      setState(() => _error = error.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _register() => _run(
    () => _runtime.register(
      phone: _phone.text,
      password: _password.text,
      displayName: _displayName.text.trim().isEmpty ? null : _displayName.text,
    ),
  );

  Future<void> _login() =>
      _run(() => _runtime.login(phone: _phone.text, password: _password.text));

  Future<void> _rename(DeviceDescriptor device) async {
    final controller = TextEditingController(text: device.displayName);
    final name = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('设备名称'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(labelText: '名称'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (name == null || name.isEmpty) return;
    await _run(() => _runtime.renameDevice(device.deviceId, name));
  }

  @override
  Widget build(BuildContext context) {
    final session = _snapshot.session;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('账号与设备', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            if (_busy) const LinearProgressIndicator(),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(
                _error!,
                key: const ValueKey('account-device-error'),
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: 8),
            if (session == null) _buildSignedOut() else _buildSignedIn(),
          ],
        ),
      ),
    );
  }

  Widget _buildSignedOut() {
    final enabled = !_busy && _runtime.passwordAuthAvailable;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('手机号直接注册/登录；Demo 阶段不发送短信验证码。'),
        if (!_runtime.passwordAuthAvailable) ...[
          const SizedBox(height: 6),
          const Text(
            '安全密码认证桥尚未接入；为避免降级为明文密码，当前禁用注册/登录。',
            key: ValueKey('pake-unavailable'),
          ),
        ],
        const SizedBox(height: 10),
        TextField(
          controller: _phone,
          enabled: enabled,
          keyboardType: TextInputType.phone,
          decoration: const InputDecoration(labelText: '手机号'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _password,
          enabled: enabled,
          obscureText: true,
          decoration: const InputDecoration(labelText: '密码'),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _displayName,
          enabled: enabled,
          decoration: const InputDecoration(labelText: '显示名称（注册时可选）'),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          children: [
            FilledButton(
              key: const ValueKey('account-register'),
              onPressed: enabled ? _register : null,
              child: const Text('注册'),
            ),
            OutlinedButton(
              key: const ValueKey('account-login'),
              onPressed: enabled ? _login : null,
              child: const Text('登录'),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildSignedIn() {
    final session = _snapshot.session!;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          contentPadding: EdgeInsets.zero,
          leading: const Icon(Icons.account_circle_outlined),
          title: Text(session.account.displayName ?? session.account.phoneE164),
          subtitle: Text(session.account.phoneE164),
          trailing: Text(session.account.plan),
        ),
        Wrap(
          spacing: 8,
          children: [
            OutlinedButton(
              onPressed: _busy ? null : () => _run(_runtime.refreshSession),
              child: const Text('刷新会话'),
            ),
            TextButton(
              onPressed: _busy ? null : () => _run(_runtime.logout),
              child: const Text('退出登录'),
            ),
          ],
        ),
        const Divider(height: 24),
        Text('设备', style: Theme.of(context).textTheme.titleSmall),
        if (_snapshot.devices.isEmpty) const Text('暂无已登记设备'),
        for (final device in _snapshot.devices) _deviceTile(device),
      ],
    );
  }

  Widget _deviceTile(DeviceDescriptor device) {
    final current = device.deviceId == _snapshot.currentDeviceId;
    final capabilities = device.capabilityReport.capabilities
        .map((item) => item.value)
        .join(', ');
    final status = [
      device.platform,
      device.trustState.value,
      if (current) '当前设备',
      if (device.isDefaultComputeNode) '默认计算节点',
      if (capabilities.isNotEmpty) capabilities,
    ].join(' · ');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(device.displayName),
      subtitle: Text(status),
      trailing: Wrap(
        spacing: 2,
        children: [
          IconButton(
            key: ValueKey('rename-${device.deviceId}'),
            tooltip: '重命名',
            onPressed: _busy ? null : () => _rename(device),
            icon: const Icon(Icons.edit_outlined),
          ),
          IconButton(
            key: ValueKey('default-${device.deviceId}'),
            tooltip: '设为默认计算节点',
            onPressed: _busy || device.isDefaultComputeNode
                ? null
                : () => _run(
                    () => _runtime.setDefaultComputeNode(device.deviceId),
                  ),
            icon: const Icon(Icons.computer_outlined),
          ),
          IconButton(
            key: ValueKey('revoke-${device.deviceId}'),
            tooltip: '撤销设备',
            onPressed: _busy
                ? null
                : () => _run(() => _runtime.revokeDevice(device.deviceId)),
            icon: const Icon(Icons.link_off_outlined),
          ),
        ],
      ),
    );
  }
}
