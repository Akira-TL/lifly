import 'package:client_flutter/app/theme/lifly_semantic_colors.dart';
import 'package:flutter/material.dart';

Color homeTaskQuadrantColor(String quadrant, LiflySemanticColors colors) {
  return switch (quadrant) {
    'important_urgent' => colors.critical,
    'important_not_urgent' => colors.info,
    'not_important_urgent' => colors.warning,
    'not_important_not_urgent' => colors.success,
    _ => colors.neutral,
  };
}

String homeTaskQuadrantLabel(String quadrant) {
  return switch (quadrant) {
    'important_urgent' => '重要且紧急',
    'important_not_urgent' => '重要不紧急',
    'not_important_urgent' => '不重要但紧急',
    'not_important_not_urgent' => '不重要不紧急',
    _ => '待判断',
  };
}

Color homeTaskTimeColor(Duration distance, LiflySemanticColors colors) {
  if (distance <= Duration.zero) return colors.critical;
  if (distance <= const Duration(hours: 6)) return colors.critical;
  if (distance <= const Duration(hours: 24)) return colors.warning;
  if (distance <= const Duration(days: 3)) return colors.info;
  return colors.success;
}

double homeTaskTimeRatio(Duration distance) {
  if (distance <= Duration.zero) return 1;
  if (distance <= const Duration(hours: 6)) return 0.9;
  if (distance <= const Duration(hours: 24)) return 0.72;
  if (distance <= const Duration(days: 3)) return 0.48;
  if (distance <= const Duration(days: 7)) return 0.28;
  return 0.14;
}

String homeTaskTimeDistanceLabel(Duration distance) {
  if (distance <= Duration.zero) return '0h';
  if (distance < const Duration(hours: 1)) return '<1h';
  if (distance < const Duration(days: 1)) return '${distance.inHours}h';
  if (distance < const Duration(days: 7)) return '${distance.inDays}d';
  return '${(distance.inDays / 7).ceil()}周';
}
