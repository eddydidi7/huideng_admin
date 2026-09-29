import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huideng_admin/data/admin_api.dart';
import 'package:huideng_admin/features/public_content_page.dart';

class ContentApi implements AdminApi {
  Map<String, dynamic> item = {
    'calendar_url': 'https://example.com/calendar',
    'forum_url': 'https://example.com/forum',
    'version': 1,
    'published_notes': [],
  };
  Map<String, dynamic>? last;
  @override
  Future<void> signIn(String a, String b) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (action == 'links.save') {
      last = payload;
      item = {...item, ...payload, 'version': 2};
    }
    return {'item': item};
  }
}

void main() {
  testWidgets(
    'publishing produces stable public record without private note writes',
    (tester) async {
      final api = ContentApi();
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: PublicContentPage(api: api, notes: true)),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('新建公开笔记'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), '发布测试正文');
      await tester.tap(find.text('发布'));
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pumpAndSettle();
      final note = (api.last!['published_notes'] as List).single as Map;
      expect(note['body'], '发布测试正文');
      expect(note['id'], matches(RegExp(r'^[0-9a-f-]{36}$')));
      expect(api.last!['version'], 1);
      expect(api.last!.containsKey('user_id'), false);
      expect(find.text('发布测试正文'), findsOneWidget);
    },
  );
}
