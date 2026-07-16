import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Web host provides an inline zero-network startup shell', () {
    final index = File('web/index.html').readAsStringSync();

    expect(index, contains('id="lifly-startup-shell"'));
    expect(index, contains('lifly-host-feedback'));
    expect(index, contains('lifly-core-usable'));
    expect(index, contains('system-ui'));
    expect(index, isNot(contains('fonts.googleapis.com')));
    expect(index, isNot(contains('<img')));
  });

  test('custom bootstrap records each Flutter initialization stage', () {
    final bootstrap = File('web/flutter_bootstrap.js').readAsStringSync();

    expect(bootstrap, contains('{{flutter_js}}'));
    expect(bootstrap, contains('{{flutter_build_config}}'));
    expect(bootstrap, contains('_flutter.loader.load'));
    expect(bootstrap, contains('onEntrypointLoaded'));
    expect(bootstrap, contains('lifly-entrypoint-loaded'));
    expect(bootstrap, contains('lifly-engine-initialized'));
    expect(bootstrap, contains('lifly-run-app-resolved'));
    expect(bootstrap, contains('lifly-bootstrap-failed'));
  });

  test('Core theme has no remote, font, or decorative asset dependency', () {
    final coreTheme = File('lib/app/theme/app_theme.dart').readAsStringSync();

    expect(coreTheme, isNot(contains('http://')));
    expect(coreTheme, isNot(contains('https://')));
    expect(coreTheme, contains('fontFamily: null'));
    expect(coreTheme, isNot(matches(RegExp(r'''fontFamily:\s*["']'''))));
    expect(coreTheme, isNot(contains('AssetImage')));
    expect(coreTheme, isNot(contains('NetworkImage')));
  });
}
