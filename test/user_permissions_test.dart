import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huideng_admin/data/admin_api.dart';
import 'package:huideng_admin/features/user_permissions_page.dart';

class FakePermissionsApi implements AdminApi {
  final writes = <Map<String, dynamic>>[];
  @override
  Future<Map<String, dynamic>> call(String action, [Map<String, dynamic> payload = const {}]) async {
    if (action == 'permissions.freeze') writes.add(payload);
    return {
      'revision': writes.length,
      'status': writes.isEmpty ? 'normal' : 'all_frozen',
      'permissions': [
        {'feature': 'chat', 'permission': 'send', 'feature_label': '聊天', 'label': '发送消息', 'restriction': null},
      ],
    };
  }
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {}
}

void main() {
  test('unknown state is not displayed as normal', () {
    expect(permissionStatus(null), '权限状态未获取');
  });
  testWidgets('freeze is confirmed and carries revision plus exact permission', (tester) async {
    final api = FakePermissionsApi();
    await tester.pumpWidget(MaterialApp(home: UserPermissionsPage(api: api, user: const {'id': 'user', 'nickname': '测试'})));
    await tester.pumpAndSettle();
    expect(find.text('聊天 · 发送消息'), findsOneWidget);
    await tester.tap(find.text('全部冻结'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(api.writes, isEmpty);
    await tester.tap(find.text('确认'));
    await tester.pumpAndSettle();
    expect(api.writes.single['revision'], 0);
    expect(api.writes.single['duration'], '7d');
    expect(api.writes.single['permissions'], [{'feature': 'chat', 'permission': 'send'}]);
    await tester.pumpWidget(const SizedBox());
  });
}
