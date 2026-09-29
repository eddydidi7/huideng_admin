import 'package:flutter/material.dart';
import '../data/admin_api.dart';
import 'user_permissions_page.dart';

class CatalogPage extends StatefulWidget {
  const CatalogPage({super.key, required this.api, required this.section});
  final AdminApi api;
  final String section;
  @override
  State<CatalogPage> createState() => _CatalogPageState();
}

class _CatalogPageState extends State<CatalogPage> {
  final search = TextEditingController();
  List<Map<String, dynamic>> rows = [];
  bool busy = false, more = false;
  int offset = 0;
  String? error;
  bool get users => widget.section == '用户';
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    search.dispose();
    super.dispose();
  }

  Future<void> load({int? page}) async {
    if (busy) return;
    final next = page ?? offset;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.call(
        switch (widget.section) {
          '用户' => 'users.list',
          '文章' => 'articles.list',
          _ => 'forum.list',
        },
        {'search': search.text.trim(), 'offset': next},
      );
      if (result['items'] is! List) {
        throw const AdminFailure('列表服务尚未就绪，请联系维护人员更新管理服务。');
      }
      final items = (result['items'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      if (users) {
        try {
          final states = await widget.api.call('permissions.states', {
            'user_ids': items.take(50).map((e) => e['id']).toList(),
          });
          final byId = {
            for (final s in states['items'] as List) s['user_id']: s['status'],
          };
          for (final row in items) {
            row['feature_status'] = byId[row['id']];
          }
        } catch (_) {
          // Existing users remain accessible while the new service is undeployed.
        }
      }
      if (mounted) {
        setState(() {
          rows = items.take(50).toList();
          more = items.length > 50;
          offset = next;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          error = e.toString();
          rows = [];
          more = false;
        });
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  void detail(Map<String, dynamic> row) async {
    if (users) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => UserPermissionsPage(api: widget.api, user: row),
        ),
      );
      if (mounted) load();
      return;
    }
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          users
              ? '${row['nickname'] ?? row['email'] ?? '访客用户'}'
              : '${row['title'] ?? '无标题'}',
        ),
        content: SizedBox(
          width: 680,
          child: SingleChildScrollView(
            child: SelectableText(
              users
                  ? '个人号：${row['personal_number'] ?? '未生成'}\n邮箱：${row['email'] ?? '无'}\n注册时间：${row['created_at']}\n状态：${row['account_status']}\n用户 ID：${row['id']}'
                  : '${row['body'] ?? ''}\n\n作者：${row['author_name'] ?? ''}\n发布时间：${row['created_at']}\n文章 ID：${row['id']}',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('关闭'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      Text(widget.section, style: Theme.of(context).textTheme.headlineSmall),
      const SizedBox(height: 8),
      Text(
        users
            ? 'App 注册账号与访客账号；点击查看账号资料。'
            : widget.section == '文章'
            ? '红书中的长文章。普通动态和图文请在“论坛”查看。'
            : '红书动态、图文和长文章；不读取私人笔记或私密帖子。',
      ),
      const SizedBox(height: 12),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: search,
              enabled: !busy,
              decoration: InputDecoration(
                hintText: users ? '搜索昵称、个人号或邮箱' : '搜索标题、正文或作者',
              ),
              onSubmitted: (_) => load(page: 0),
            ),
          ),
          TextButton(
            onPressed: busy ? null : () => load(page: 0),
            child: const Text('搜索'),
          ),
          IconButton(
            tooltip: '刷新列表',
            onPressed: busy ? null : () => load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            TextButton(
              onPressed: busy ? null : () => load(),
              child: const Text('重试'),
            ),
          ],
        ),
      Expanded(
        child: !busy && error == null && rows.isEmpty
            ? Center(
                child: Text(
                  search.text.trim().isNotEmpty
                      ? '没有匹配的结果'
                      : users
                      ? '暂无用户'
                      : widget.section == '文章'
                      ? '暂无长文章，请在论坛查看图文和动态'
                      : '暂无帖子',
                ),
              )
            : ListView.builder(
                itemCount: rows.length,
                itemBuilder: (_, i) {
                  final r = rows[i];
                  return Card(
                    child: ListTile(
                      onTap: () => detail(r),
                      title: Text(
                        users
                            ? '${r['nickname'] ?? r['email'] ?? '访客用户'}'
                            : '${r['title'] ?? '无标题'}',
                      ),
                      subtitle: Text(
                        users
                            ? '个人号：${r['personal_number'] ?? '未生成'} · ${r['is_anonymous'] == true ? '访客' : '注册用户'} · ${r['account_status']} · ${permissionStatus(r['feature_status'])}'
                            : '${r['author_name'] ?? ''} · ${r['created_at']} · 点赞 ${r['like_count']} · 评论 ${r['reply_count']}',
                      ),
                      trailing: const Icon(Icons.chevron_right),
                    ),
                  );
                },
              ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: busy || offset == 0
                ? null
                : () => load(page: offset - 50),
            child: const Text('上一页'),
          ),
          Text('第 ${offset ~/ 50 + 1} 页'),
          TextButton(
            onPressed: busy || !more ? null : () => load(page: offset + 50),
            child: const Text('下一页'),
          ),
        ],
      ),
    ],
  );
}
