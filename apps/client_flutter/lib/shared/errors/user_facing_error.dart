import 'package:flutter/foundation.dart';

String userFacingFailure({
  required String action,
  required Object error,
  StackTrace? stackTrace,
}) {
  if (kDebugMode) {
    debugPrint('[LIFLY_UI][$action] $error');
    if (stackTrace != null) {
      debugPrintStack(stackTrace: stackTrace);
    }
  }
  return '$action失败，请稍后重试';
}
