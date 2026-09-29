import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:huideng_connection/resource_resumable_upload.dart';
import 'package:huideng_connection/resource_upload_task.dart';
import 'apk_metadata.dart';

class ReleaseApkUploader {
  ReleaseApkUploader(this.client, this.baseUrl);
  final String baseUrl;
  final SupabaseClient client;
  Future<String> upload(ApkMetadata apk, void Function(double) progress) async {
    final owner = client.auth.currentUser?.id;
    if (owner == null) throw StateError('请先登录');
    void guard() {
      if (client.auth.currentUser?.id != owner ||
          client.auth.currentSession == null) {
        throw StateError('登录已失效；本地 APK 保留');
      }
    }

    Future<Map<String, dynamic>> call(
      String action,
      Map<String, dynamic> payload,
    ) async {
      guard();
      try {
        final response = await client.functions
            .invoke(
              'public-resources',
              body: {'api_version': 1, 'action': action, ...payload},
            )
            .timeout(Duration(seconds: action == 'complete' ? 150 : 30));
        guard();
        final result = Map<String, dynamic>.from(response.data as Map);
        if (result['api_version'] != 1 || result['error'] != null) {
          throw StateError('上传服务：${result['error'] ?? '协议版本不符'}');
        }
        return result;
      } on FunctionException catch (e) {
        final code = e.details is Map ? e.details['error'] : null;
        throw StateError(
          '上传服务 HTTP ${e.status}：${code ?? '请求失败'}；本地 APK 保留，可以重试',
        );
      }
    }

    final prefs = await SharedPreferences.getInstance();
    final key = 'admin_apk_upload_${owner}_${apk.hash}';
    final id = prefs.getString(key) ?? const Uuid().v4();
    if (!await prefs.setString(key, id)) throw StateError('无法保存上传进度');
    final task = DriveUpload(
      id: id,
      path: apk.path,
      name: apk.path.split(RegExp(r'[/\\]')).last,
      size: apk.size,
      checksum: apk.hash,
      category: '文件',
    );
    final plan = await call('begin', {
      'upload_protocol': 'tus',
      'upload_id': id,
      'file_name': task.name,
      'mime_type': 'application/vnd.android.package-archive',
      'file_size': apk.size,
      'checksum': apk.hash,
      'category': task.category,
      'description': '',
    });
    Map<String, dynamic> result = plan;
    if (plan['already_uploaded'] != true) {
      final transfer = plan['resumable'];
      if (transfer is! Map) throw StateError('请先部署最新版 public-resources 分块上传接口');
      final httpClient = http.Client();
      try {
        if (transfer['stored'] != true) {
          await uploadResourceResumable(
            client: httpClient,
            source: File(apk.path),
            task: task,
            owner: owner,
            plan: Map<String, dynamic>.from(transfer),
            guard: guard,
            progress: (p) => progress(p * .9),
          );
        }
        for (var i = 0; i < 128; i++) {
          result = await call('complete', {
            'upload_id': id,
            'upload_protocol': 'tus',
          });
          if (result['verifying'] != true) break;
          final bytes = result['verified_bytes'];
          if (bytes is! num || bytes < 0 || bytes > apk.size) {
            throw StateError('服务器校验进度无效');
          }
          progress(.9 + .1 * bytes / apk.size);
        }
      } finally {
        httpClient.close();
      }
    }
    final file = result['file'];
    if (file is! Map ||
        file['status'] != 'published' ||
        file['file_size'] != apk.size ||
        file['checksum'] != apk.hash) {
      throw StateError('服务器尚未完成文件校验，请重试');
    }
    final share = await call('share', {'id': file['id']});
    final shareUri = Uri.parse(share['url'] as String);
    final slug = shareUri.pathSegments.last;
    if (!RegExp(r'^[a-f0-9]{64}$').hasMatch(slug)) throw StateError('文件分享标识无效');
    progress(1);
    return Uri.parse(baseUrl)
        .replace(
          path: '/functions/v1/resource-web',
          queryParameters: {'slug': slug, 'download': '1', 'redirect': '1'},
        )
        .toString();
  }
}
