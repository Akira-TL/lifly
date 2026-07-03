import 'package:flutter/material.dart';
import 'package:client_flutter/domain/entities/asset.dart';

class AssetCard extends StatelessWidget {
  final Asset asset;
  final VoidCallback? onTap;
  final Widget? trailing;

  const AssetCard({super.key, required this.asset, this.onTap, this.trailing});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              Icon(_iconForType(asset.assetType), size: 36, color: theme.colorScheme.primary),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(asset.displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _buildBadge(asset.kind, theme),
                        if (asset.mimeType != null) ...[
                          const SizedBox(width: 6),
                          Text(asset.mimeType!, style: theme.textTheme.bodySmall),
                        ],
                        if (asset.sizeBytes != null) ...[
                          const SizedBox(width: 6),
                          Text(_formatSize(asset.sizeBytes!), style: theme.textTheme.bodySmall),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
              if (trailing != null)
                trailing!
              else if (asset.isExternal)
                const Icon(Icons.open_in_new, size: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBadge(String kind, ThemeData theme) {
    final label = kind == 'internal' ? '内部' : '外部';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(label, style: theme.textTheme.labelSmall),
    );
  }

  IconData _iconForType(String type) {
    return switch (type) {
      'image' => Icons.image,
      'pdf' => Icons.picture_as_pdf,
      'ppt' => Icons.slideshow,
      'mindmap' => Icons.account_tree,
      'audio' => Icons.audiotrack,
      'video' => Icons.videocam,
      'link' => Icons.link,
      'embed' => Icons.code,
      _ => Icons.insert_drive_file,
    };
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }
}
