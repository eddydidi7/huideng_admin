import 'dart:convert';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

class AdminFailure implements Exception {
  final String message;
  const AdminFailure(this.message);
  @override
  String toString() => message;
}

abstract class AdminApi {
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]);
  Future<void> signIn(String email, String password);
  Future<void> signOut();
}

class SupabaseAdminApi implements AdminApi {
  final SupabaseClient client;
  SupabaseAdminApi(this.client);
  final Map<String, String> pendingRequests = {};
  @override
  Future<void> signIn(String email, String password) async {
    try {
      await client.auth.signInWithPassword(
        email: email.trim(),
        password: password,
      );
    } on AuthException {
      throw const AdminFailure('登录失败，请检查邮箱、密码和账号状态。');
    } catch (_) {
      throw const AdminFailure('无法连接登录服务，请检查网络。');
    }
  }

  @override
  Future<void> signOut() => client.auth.signOut(scope: SignOutScope.local);
  @override
  Future<Map<String, dynamic>> call(
    String action, [
    Map<String, dynamic> payload = const {},
  ]) async {
    if (client.auth.currentSession == null) {
      throw const AdminFailure('请先登录管理员账号。');
    }
    final fingerprint = jsonEncode([action, payload]);
    final requestId = pendingRequests.putIfAbsent(
      fingerprint,
      () => const Uuid().v4(),
    );
    try {
      final result = await client.functions
          .invoke(
            'admin-api',
            body: {
              'action': action,
              'payload': payload,
              'request_id': requestId,
            },
          )
          .timeout(const Duration(seconds: 25));
      final data = Map<String, dynamic>.from(result.data as Map);
      if (data['ok'] != true) throw const AdminFailure('操作未完成，请刷新后重试。');
      pendingRequests.remove(fingerprint);
      return Map<String, dynamic>.from(data['data'] as Map);
    } on FunctionException catch (e) {
      throw AdminFailure(switch (e.status) {
        401 => '登录已失效，请退出后重新登录。',
        403 => '没有此操作权限，或管理员资格已停用。',
        404 => '管理服务尚未部署，或内容已不存在。',
        409 => '内容已被其他管理员修改，请重新打开后编辑。',
        400 => '内容未通过检查，请检查填写内容及发布时间。',
        _ => '服务暂时不可用，请稍后刷新核实操作结果。',
      });
    } on AdminFailure {
      rethrow;
    } catch (_) {
      throw const AdminFailure('连接中断，请刷新核实结果后再操作。');
    }
  }
}
