import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huideng_admin/main.dart';
import 'package:huideng_admin/data/admin_api.dart';
import 'package:huideng_admin/features/notice_editor.dart';
import 'package:huideng_admin/features/admin_shell.dart';

class FakeApi implements AdminApi {
  String role = 'admin';
  bool denied = false;
  bool failSave = false;
  bool signedOut = false;
  final calls = <String>[];
  Map<String, dynamic>? saved;
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {
    signedOut = true;
  }

  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    calls.add(action);
    if (action == 'me') {
      if (denied) throw const AdminFailure('没有后台权限');
      return {'role': role, 'email': 'admin@example.com'};
    }
    if (action == 'notices.save' || action == 'links.save') {
      if (failSave) throw const AdminFailure('连接中断');
      saved = payload;
      return {};
    }
    if (action == 'notices.list') return {'items': []};
    return {};
  }
}

void main() {
  testWidgets('sunrise link validates and saves through admin API', (
    tester,
  ) async {
    final api = FakeApi();
    var reloaded = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LinksPanel(
            api: api,
            item: {
              'calendar_url': 'https://zangli.org/',
              'forum_url': 'https://example.com/forum',
              'sunrise_url': 'https://example.com/old',
              'version': 3,
            },
            reload: () async {
              reloaded = true;
            },
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField).at(2), 'http://bad.example');
    await tester.ensureVisible(find.text('保存入口网址'));
    await tester.tap(find.text('保存入口网址'));
    await tester.pumpAndSettle();
    expect(api.saved, isNull);
    await tester.enterText(
      find.byType(TextField).at(2),
      'https://example.com/new',
    );
    await tester.tap(find.text('保存入口网址'));
    await tester.pumpAndSettle();
    expect(api.saved?['sunrise_url'], 'https://example.com/new');
    expect(api.saved?['version'], 3);
    expect(reloaded, isTrue);
  });
  testWidgets('ordinary account rejected and session cleared', (tester) async {
    final api = FakeApi()..denied = true;
    await tester.pumpWidget(AdminApp(api: api));
    await tester.tap(find.text('登录后台'));
    await tester.pumpAndSettle();
    expect(find.text('没有后台权限'), findsOneWidget);
    expect(api.signedOut, isTrue);
    expect(find.text('新建通知'), findsNothing);
  });
  testWidgets('moderator sees forum only and cannot load notices', (
    tester,
  ) async {
    final api = FakeApi()..role = 'moderator';
    await tester.pumpWidget(AdminApp(api: api));
    await tester.tap(find.text('登录后台'));
    await tester.pumpAndSettle();
    expect(find.widgetWithText(ListTile, '论坛'), findsOneWidget);
    expect(find.text('通知'), findsNothing);
    expect(api.calls.contains('dashboard'), isFalse);
    await tester.tap(find.text('退出登录'));
    await tester.pumpAndSettle();
    expect(find.text('登录后台'), findsOneWidget);
  });
  testWidgets('notice form retains content on failure and saves draft', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final api = FakeApi()..failSave = true;
    await tester.pumpWidget(MaterialApp(home: NoticeEditor(api: api)));
    await tester.enterText(find.byType(TextFormField).at(0), '共修安排');
    await tester.enterText(find.byType(TextFormField).at(1), '明天共修');
    await tester.ensureVisible(find.widgetWithText(FilledButton, '保存草稿'));
    await tester.tap(find.widgetWithText(FilledButton, '保存草稿'));
    await tester.pumpAndSettle();
    expect(find.text('连接中断'), findsOneWidget);
    expect(find.text('共修安排'), findsOneWidget);
    api.failSave = false;
    await tester.tap(find.widgetWithText(FilledButton, '保存草稿'));
    await tester.pumpAndSettle();
    expect(api.saved?['title_zh'], '共修安排');
    expect(api.saved?['mode'], 'draft');
  });
  testWidgets('missing configuration gives Chinese guidance', (tester) async {
    await tester.pumpWidget(const AdminApp());
    expect(find.text('管理服务尚未配置。请由维护人员完成首次配置后使用。'), findsOneWidget);
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton)).onPressed,
      isNull,
    );
  });
}
