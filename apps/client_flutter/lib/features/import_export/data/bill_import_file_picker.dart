import 'package:file_selector/file_selector.dart';

class BillImportSelectedFile {
  final String name;
  final List<int> bytes;

  const BillImportSelectedFile({required this.name, required this.bytes});
}

abstract class BillImportFilePicker {
  Future<BillImportSelectedFile?> pickBillFile();
}

class FileSelectorBillImportFilePicker implements BillImportFilePicker {
  const FileSelectorBillImportFilePicker();

  @override
  Future<BillImportSelectedFile?> pickBillFile() async {
    const typeGroup = XTypeGroup(
      label: '微信 / 支付宝流水',
      extensions: ['csv', 'xlsx'],
    );
    final file = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (file == null) return null;
    return BillImportSelectedFile(
      name: file.name,
      bytes: await file.readAsBytes(),
    );
  }
}
