import 'package:client_flutter/features/ai_capture/models/ai_capture_models.dart';
import 'package:flutter/material.dart';

Future<Set<String>?> showAiCaptureAssetPicker(
  BuildContext context, {
  required List<AiCaptureAssetContext> assets,
  required Set<String> selectedIds,
}) {
  return showModalBottomSheet<Set<String>>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _AiCaptureAssetPicker(
      assets: assets,
      selectedIds: selectedIds,
    ),
  );
}

class _AiCaptureAssetPicker extends StatefulWidget {
  const _AiCaptureAssetPicker({
    required this.assets,
    required this.selectedIds,
  });

  final List<AiCaptureAssetContext> assets;
  final Set<String> selectedIds;

  @override
  State<_AiCaptureAssetPicker> createState() => _AiCaptureAssetPickerState();
}

class _AiCaptureAssetPickerState extends State<_AiCaptureAssetPicker> {
  late final Set<String> _selected = {...widget.selectedIds};

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.72,
        child: Column(
          children: [
            ListTile(
              title: const Text('选择附件'),
              subtitle: const Text('附件会按引用保存；仅已支持的内容会参与解析。'),
              trailing: FilledButton(
                onPressed: () => Navigator.of(context).pop(_selected),
                child: Text('完成 ${_selected.length}'),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: widget.assets.isEmpty
                  ? const Center(child: Text('暂无可用附件'))
                  : ListView.builder(
                      itemCount: widget.assets.length,
                      itemBuilder: (context, index) {
                        final asset = widget.assets[index];
                        return CheckboxListTile(
                          value: _selected.contains(asset.assetId),
                          onChanged: (selected) {
                            setState(() {
                              if (selected ?? false) {
                                _selected.add(asset.assetId);
                              } else {
                                _selected.remove(asset.assetId);
                              }
                            });
                          },
                          title: Text(asset.displayName),
                          subtitle: Text(
                            '${asset.assetType ?? 'file'} · ${_statusLabel(asset.status)}',
                          ),
                          secondary: Icon(_assetIcon(asset)),
                        );
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }

  IconData _assetIcon(AiCaptureAssetContext asset) {
    final mime = asset.mimeType ?? '';
    if (mime.startsWith('image/')) return Icons.image_outlined;
    if (mime.startsWith('audio/')) return Icons.audio_file_outlined;
    if (mime == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (asset.kind == 'external') return Icons.link_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _statusLabel(String status) {
    return switch (status) {
      'ready' => '可参与解析',
      'metadata_only' => '仅元数据',
      'pending_upload' => '等待上传',
      'unsupported' => '等待解析能力',
      'missing' => '不存在',
      'inactive' => '不可用',
      'failed' => '读取失败',
      _ => status,
    };
  }
}
