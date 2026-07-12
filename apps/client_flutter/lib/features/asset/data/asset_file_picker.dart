import 'package:file_selector/file_selector.dart';

class AssetSelectedFile {
  const AssetSelectedFile({
    required this.name,
    required this.bytes,
    required this.assetType,
    required this.mimeType,
  });

  final String name;
  final List<int> bytes;
  final String assetType;
  final String? mimeType;
}

abstract class AssetFilePicker {
  Future<AssetSelectedFile?> pickFile();
}

class FileSelectorAssetFilePicker implements AssetFilePicker {
  const FileSelectorAssetFilePicker();

  @override
  Future<AssetSelectedFile?> pickFile() async {
    final file = await openFile();
    if (file == null) return null;
    final extension = _extension(file.name);
    return AssetSelectedFile(
      name: file.name,
      bytes: await file.readAsBytes(),
      assetType: _assetType(extension),
      mimeType: _mimeType(extension),
    );
  }
}

String _extension(String filename) {
  final index = filename.lastIndexOf('.');
  if (index < 0 || index == filename.length - 1) return '';
  return filename.substring(index + 1).toLowerCase();
}

String _assetType(String extension) {
  if (const {'png', 'jpg', 'jpeg', 'gif', 'webp', 'heic'}.contains(extension)) {
    return 'image';
  }
  if (extension == 'pdf') return 'pdf';
  if (const {'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'}.contains(extension)) {
    return 'audio';
  }
  return 'file';
}

String? _mimeType(String extension) {
  return const <String, String>{
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'heic': 'image/heic',
    'pdf': 'application/pdf',
    'txt': 'text/plain',
    'md': 'text/markdown',
    'csv': 'text/csv',
    'json': 'application/json',
    'xml': 'application/xml',
    'mp3': 'audio/mpeg',
    'wav': 'audio/wav',
    'm4a': 'audio/mp4',
    'aac': 'audio/aac',
    'ogg': 'audio/ogg',
    'flac': 'audio/flac',
  }[extension];
}
