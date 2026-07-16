import 'package:client_flutter/app/theme/theme_package.dart';
import 'package:flutter/foundation.dart';

@immutable
class ThemeEntitlementGrant {
  final bool permitted;
  final DateTime? validUntil;
  final bool offlineAllowed;
  final String? reason;

  const ThemeEntitlementGrant._({
    required this.permitted,
    required this.validUntil,
    required this.offlineAllowed,
    required this.reason,
  });

  factory ThemeEntitlementGrant.allowed({
    DateTime? validUntil,
    bool offlineAllowed = false,
  }) {
    return ThemeEntitlementGrant._(
      permitted: true,
      validUntil: validUntil,
      offlineAllowed: offlineAllowed,
      reason: null,
    );
  }

  const ThemeEntitlementGrant.denied(String reason)
    : this._(
        permitted: false,
        validUntil: null,
        offlineAllowed: false,
        reason: reason,
      );

  bool isUsable({required bool offline, required DateTime now}) {
    if (!permitted) return false;
    if (offline && !offlineAllowed) return false;
    final expiry = validUntil;
    return expiry == null || !now.isAfter(expiry);
  }
}

abstract interface class ThemeEntitlementProvider {
  Future<ThemeEntitlementGrant> resolve(
    ThemeManifest manifest, {
    required bool offline,
    required DateTime now,
  });
}

class LocalThemeEntitlementProvider implements ThemeEntitlementProvider {
  final Map<String, ThemeEntitlementGrant> _grants;

  LocalThemeEntitlementProvider({
    Map<String, ThemeEntitlementGrant> grants = const {},
  }) : _grants = Map.of(grants);

  void setGrant(String themeId, ThemeEntitlementGrant grant) {
    _grants[themeId] = grant;
  }

  @override
  Future<ThemeEntitlementGrant> resolve(
    ThemeManifest manifest, {
    required bool offline,
    required DateTime now,
  }) async {
    if (manifest.entitlementType == ThemeEntitlementType.builtin ||
        manifest.entitlementType == ThemeEntitlementType.free) {
      return ThemeEntitlementGrant.allowed(offlineAllowed: true);
    }
    return _grants[manifest.themeId] ??
        const ThemeEntitlementGrant.denied('theme entitlement is unavailable');
  }
}

class ThemeEntitlementException implements Exception {
  final String themeId;
  final String message;

  const ThemeEntitlementException(this.themeId, this.message);

  @override
  String toString() => 'ThemeEntitlementException($themeId): $message';
}
