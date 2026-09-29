import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huideng_admin/data/admin_api.dart';
import 'package:huideng_admin/features/catalog_page.dart';
import 'package:huideng_admin/features/admin_shell.dart';

class CatalogApi implements AdminApi {
  final calls = <String>[];
  bool fail = false;
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add(action);
    if (action == 'me') return {'role': 'super_admin', 'email': 'admin@test'};
    if (action == 'dashboard') return {};
    if (fail) throw const AdminFailure('网络中断，请重试');
    return {
      'items': payload['search'] == '没有'
          ? []
          : [
              {
                'id': '1',
                'title': '测试文章',
                'body': '文章正文',
                'nickname': '测试用户',
                'personal_number': '1001',
              },
            ],
    };
  }
}

void main() {
  testWidgets('all three shell sections load actual catalog endpoints', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1400, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = CatalogApi();
    await tester.pumpWidget(MaterialApp(home: AdminShell(api: api)));
    await tester.tap(find.text('登录后台'));
    await tester.pumpAndSettle();
    for (final entry in {
      '论坛': 'forum.list',
      '文章': 'articles.list',
      '用户': 'users.list',
    }.entries) {
      await tester.tap(find.widgetWithText(ListTile, entry.key));
      await tester.pumpAndSettle();
      expect(api.calls, contains(entry.value));
      expect(find.text(entry.key == '用户' ? '测试用户' : '测试文章'), findsOneWidget);
      expect(tester.takeException(), isNull);
    }
  });
  testWidgets('failed request has retry and search empty state is distinct', (
    tester,
  ) async {
    final api = CatalogApi()..fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: CatalogPage(api: api, section: '论坛'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('网络中断，请重试'), findsOneWidget);
    expect(find.text('暂无帖子'), findsNothing);
    api.fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试文章'));
    await tester.pumpAndSettle();
    expect(find.textContaining('文章正文'), findsOneWidget);
    await tester.tap(find.text('关闭'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '没有');
    await tester.tap(find.text('搜索'));
    await tester.pumpAndSettle();
    expect(find.text('没有匹配的结果'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
