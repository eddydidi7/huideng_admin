import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huideng_admin/data/admin_api.dart';
import 'package:huideng_admin/features/resource_usage_page.dart';

class UsageApi implements AdminApi {
  final calls = <Map<String, dynamic>>[];
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add({'action': action, ...payload});
    if (action == 'usage.detail') {
      return {
        'user': {'user_id': 'u', 'nickname': '学友', 'level': 2},
        'limits': {
          'version': 1,
          'quota_bytes': 1000,
          'daily_bytes': 1000,
          'monthly_bytes': 1000,
          'daily_files': 100,
          'monthly_files': 1000,
          'paused': false,
          'blocked_types': <String>[],
        },
        'files': [],
        'warnings': [],
        'posts': [],
        'resources': [],
      };
    }
    return {
      'items': [
        {
          'user_id': 'u',
          'username': 'user',
          'nickname': '学友',
          'level': 2,
          'used_bytes': 10,
          'pending_bytes': 0,
          'quota_bytes': 100,
          'usage_percent': 10,
          'month_upload_bytes': 10,
          'month_upload_files': 1,
        },
      ],
    };
  }
}

void main() {
  testWidgets(
    'resource filters are sent to server; actual download usage stays unknown',
    (tester) async {
      final api = UsageApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: ResourceUsagePage(api: api)),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.textContaining('暂无法精确统计'), findsOneWidget);
      await tester.tap(find.text('总占用降序'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('月上传降序').last);
      await tester.pumpAndSettle();
      expect(api.calls.last['sort'], 'upload');
      await tester.tap(find.text('全部配额'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('≥80%').last);
      await tester.pumpAndSettle();
      expect(api.calls.last['threshold'], 80);
      await tester.tap(find.textContaining('学友').first);
      await tester.pumpAndSettle();
      expect(find.text('保持当前期限'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}
