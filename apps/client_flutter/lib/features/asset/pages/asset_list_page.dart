import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/asset_repository.dart';
import 'package:client_flutter/data/crypto/account_e2ee_runtime.dart';
import 'package:client_flutter/domain/entities/asset.dart';
import 'package:client_flutter/features/asset/data/asset_file_picker.dart';
import 'package:client_flutter/shared/errors/user_facing_error.dart';
import 'package:client_flutter/shared/widgets/asset_card.dart';
import 'package:client_flutter/shared/widgets/async_content.dart';

class AssetListPage extends StatefulWidget {
  const AssetListPage({super.key});

  @override
  State<AssetListPage> createState() => _AssetListPageState();
}

class _AssetListPageState extends State<AssetListPage> {
  late final AssetRepository _repo;
  final AssetFilePicker _filePicker = const FileSelectorAssetFilePicker();
  List<Asset> _assets = [];
  bool _loading = true;
  bool _uploading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _repo = AssetRepository(
      context.read<ApiClient>(),
      e2ee: context.read<AccountE2eeRuntime>(),
    );
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final assets = await _repo.list();
      if (!mounted) return;
      setState(() {
        _assets = assets;
        _loading = false;
      });
    } catch (error, stackTrace) {
      if (!mounted) return;
      setState(() {
        _error = userFacingFailure(
          action: '加载附件',
          error: error,
          stackTrace: stackTrace,
        );
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('附件库'), scrolledUnderElevation: 0),
      body: _buildBody(),
      floatingActionButton: FloatingActionButton(
        heroTag: 'asset-create-fab',
        onPressed: () => _showAddSheet(context),
        child: const Icon(Icons.add),
      ),
    );
  }

  Widget _buildBody() {
    return AsyncContentScaffold(
      isLoading: _loading,
      error: _error,
      isEmpty: _assets.isEmpty,
      onRefresh: _load,
      loadingMessage: '正在读取附件',
      emptyIcon: Icons.attach_file_outlined,
      emptyTitle: '还没有附件',
      emptySubtitle: '上传文件或登记外部链接，正文之外的数据也能统一管理。',
      emptyActionLabel: '添加附件',
      onEmptyAction: () => _showAddSheet(context),
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
        itemCount: _assets.length,
        itemBuilder: (_, index) => AssetCard(
          asset: _assets[index],
          onTap: () => _showDetail(_assets[index]),
        ),
      ),
    );
  }

  void _showAddSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.upload_file),
              title: const Text('上传文件'),
              subtitle: _uploading ? const Text('正在上传…') : null,
              onTap: _uploading
                  ? null
                  : () {
                      Navigator.pop(ctx);
                      _triggerUpload();
                    },
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('添加外链'),
              onTap: () {
                Navigator.pop(ctx);
                _showExternalLinkDialog();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _triggerUpload() async {
    final selected = await _filePicker.pickFile();
    if (selected == null || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final asset = await _repo.uploadBytes(
        filename: selected.name,
        bytes: selected.bytes,
        mimeType: selected.mimeType,
        assetType: selected.assetType,
      );
      if (!mounted) return;
      setState(() => _assets.insert(0, asset));
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('已上传 ${asset.displayName}')));
    } catch (error, stackTrace) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingFailure(
              action: '上传附件',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _showExternalLinkDialog() async {
    final draft = await showDialog<_ExternalLinkDraft>(
      context: context,
      builder: (_) => const _ExternalLinkDialog(),
    );
    if (draft == null) return;

    try {
      await _repo.registerExternalUrl(
        externalUrl: draft.url,
        title: draft.title.isEmpty ? null : draft.title,
      );
      await _load();
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('外链已添加')));
    } catch (error, stackTrace) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            userFacingFailure(
              action: '添加外链',
              error: error,
              stackTrace: stackTrace,
            ),
          ),
        ),
      );
    }
  }

  void _showDetail(Asset asset) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(asset.displayName),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('ID: ${asset.id}'),
            Text('类型: ${asset.assetType}'),
            if (asset.sizeBytes != null) Text('大小: ${asset.sizeBytes} bytes'),
            if (asset.mimeType != null) Text('MIME: ${asset.mimeType}'),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }
}

class _ExternalLinkDraft {
  const _ExternalLinkDraft({required this.url, required this.title});

  final String url;
  final String title;
}

class _ExternalLinkDialog extends StatefulWidget {
  const _ExternalLinkDialog();

  @override
  State<_ExternalLinkDialog> createState() => _ExternalLinkDialogState();
}

class _ExternalLinkDialogState extends State<_ExternalLinkDialog> {
  final _urlController = TextEditingController();
  final _titleController = TextEditingController();
  String? _urlError;

  @override
  void dispose() {
    _urlController.dispose();
    _titleController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('添加外链'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleController,
            decoration: const InputDecoration(labelText: '标题'),
          ),
          TextField(
            controller: _urlController,
            decoration: InputDecoration(labelText: 'URL', errorText: _urlError),
            onChanged: (_) {
              if (_urlError != null) setState(() => _urlError = null);
            },
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        FilledButton(onPressed: _submit, child: const Text('保存')),
      ],
    );
  }

  void _submit() {
    final url = _urlController.text.trim();
    if (url.isEmpty) {
      setState(() => _urlError = '请输入链接地址');
      return;
    }
    Navigator.pop(
      context,
      _ExternalLinkDraft(url: url, title: _titleController.text.trim()),
    );
  }
}
