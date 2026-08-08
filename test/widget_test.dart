// Basic Flutter test stub.
//
// There is no real test suite yet; verification is `flutter analyze` plus
// manual smoke testing (see CLAUDE.md). The app root is `TrakrApp` (single
// Email/Password login resolved against the Master control-plane index), which
// requires initialized Firebase, so a widget-level smoke test cannot run in a
// bare test environment.

import 'package:flutter_test/flutter_test.dart';

import 'package:attendqr/main.dart' as app;

void main() {
  test('app entry point is wired', () {
    expect(app.main, isNotNull);
  });
}
