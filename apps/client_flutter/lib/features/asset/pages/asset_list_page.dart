import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:client_flutter/data/api/api_client.dart';
import 'package:client_flutter/data/repositories/asset_repository.dart';
import 'package:client_flutter/domain/entities/asset.dart';
import 'package:client_flutter/features/asset/data/asset_file_picker.dart';
import 'package:client_flutter/shared/widgets/asset_card.dart';

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
    _repo = AssetRepository(context.read<ApiClient>());
    _load();
  }

  Future<void> _load() async {
    setState(() { _loading = true; _error = null; });
    try {
      final assets = await _repo.list();
      setState(() { _assets = assets; _loading = false; });
    } catch (e) {
      setState(() { _error = e.toString(); _loading = false; });
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
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) return Center(child: Text('加载失败: $_error'));
    if (_assets.isEmpty) return const Center(child: Text('暂无附件'));
    return RefreshIndicator(
      onRefresh: _load,
      child: ListView.builder(
        itemCount: _assets.length,
        itemBuilder: (_, i) => AssetCard(
          asset: _assets[i],
          onTap: () => _showDetail(_assets[i]),
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
              onTap: () { Navigator.pop(ctx); _showExternalLinkDialog(); },
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
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('已上传 ${asset.displayName}')),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('上传失败：$error')),
      );
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _showExternalLinkDialog() {
    final urlCtl = TextEditingController();
    final titleCtl = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('添加外链'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: titleCtl, decoration: const InputDecoration(labelText: '标题')),
            TextField(controller: urlCtl, decoration: const InputDecoration(labelText: 'URL')),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(ctx);
              if (urlCtl.text.isNotEmpty) {
                await _repo.registerExternalUrl(
                  externalUrl: urlCtl.text,
                  title: titleCtl.text.isNotEmpty ? titleCtl.text : null,
                );
                _load();
              }
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('关闭')),
        ],
      ),
    );
  }
}
