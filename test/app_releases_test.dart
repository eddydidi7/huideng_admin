import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huideng_admin/data/admin_api.dart';
import 'package:huideng_admin/features/app_releases_page.dart';
import 'package:huideng_admin/services/apk_metadata.dart';

class ReleaseApi implements AdminApi {
  Map<String, dynamic>? saved;
  @override
  Future<void> signIn(String e, String p) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (action == 'releases.save') {
      saved = payload;
      return payload;
    }
    return {'items': <Map<String, dynamic>>[]};
  }
}

void main() {
  testWidgets(
    'APK metadata auto fills exact values; failed upload retries without choosing again; saving does not publish',
    (tester) async {
      final api = ReleaseApi();
      var picks = 0, attempts = 0;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: AppReleasesPage(
              api: api,
              pickApk: () async {
                picks++;
                return ApkMetadata(
                  'sample.apk',
                  200617590,
                  'a' * 64,
                  '1.0.47',
                  48,
                  'org.huideng.huideng_counter',
                );
              },
              uploadApk: (apk, progress) async {
                attempts++;
                if (attempts == 1) throw StateError('HTTP 503');
                progress(1);
                return 'https://example.com/download.apk';
              },
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新增版本'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('选择 APK 并自动填写'));
      await tester.pumpAndSettle();
      expect(find.textContaining('HTTP 503'), findsOneWidget);
      await tester.tap(find.text('重试上传所选 APK'));
      await tester.pumpAndSettle();
      expect(picks, 1);
      expect(attempts, 2);
      final fields = tester
          .widgetList<TextField>(find.byType(TextField))
          .toList();
      expect(fields[0].controller!.text, '48');
      expect(fields[1].controller!.text, '1.0.47');
      expect(fields[4].controller!.text, '200617590');
      expect(fields[5].controller!.text, 'a' * 64);
      fields[3].controller!.text = '更新说明';
      await tester.tap(find.text('保存草稿'));
      await tester.pumpAndSettle();
      expect(api.saved!['apk_size'], 200617590);
      expect(api.saved!['version_code'], 48);
      expect(api.saved!['is_published'], false);
      expect(api.saved!['force_update'], false);
      expect(api.saved!['minimum_version_code'], 0);
      expect(api.saved!['auto_download'], false);
      expect(api.saved!['startup_check'], true);
      expect(api.saved!['updates_enabled'], true);
      expect(tester.takeException(), isNull);
    },
  );
}
