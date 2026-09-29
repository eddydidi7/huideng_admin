import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:huideng_admin/data/admin_api.dart';
import 'package:huideng_admin/features/resource_admin_page.dart';

class ResourceApi implements AdminApi {
  Map<String, dynamic> config = {
    'version': 1,
    'enabled': true,
    'upload_enabled': true,
    'download_enabled': true,
    'uploader_delete_enabled': true,
    'group_transfer_enabled': true,
    'used_bytes': 0,
    'total_bytes': 1073741824,
    'max_file_bytes': 20971520,
    'daily_upload_bytes': 104857600,
    'daily_download_bytes': 524288000,
    'categories': ['经论'],
    'notice': '',
  };
  Map<String, dynamic>? saved;
  @override
  Future<void> signIn(String email, String password) async {}
  @override
  Future<void> signOut() async {}
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (action == 'resources.settings') {
      saved = Map.of(payload);
      config = {...payload, 'version': 2};
      return {'saved': true};
    }
    return {'config': Map.of(config), 'files': []};
  }
}

void main() {
  testWidgets('upload switch saves independently and survives reload', (
    tester,
  ) async {
    final api = ResourceApi();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: ResourceAdminPage(api: api)),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('允许用户上传'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('允许用户删除自己上传的文件'));
    await tester.tap(find.text('允许用户删除自己上传的文件'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('允许公共网盘与群文件互相转存'));
    await tester.tap(find.text('允许公共网盘与群文件互相转存'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('保存开关与设置'));
    await tester.tap(find.text('保存开关与设置'));
    await tester.pumpAndSettle();
    expect(api.saved?['upload_enabled'], false);
    expect(api.saved?['download_enabled'], true);
    expect(api.saved?['enabled'], true);
    expect(api.saved?['uploader_delete_enabled'], false);
    expect(api.saved?['group_transfer_enabled'], false);
    expect(
      tester.widget<SwitchListTile>(find.byType(SwitchListTile).at(1)).value,
      false,
    );
    expect(tester.takeException(), isNull);
  });
}
