import 'package:flutter/material.dart';
import '../data/admin_api.dart';

class JieyuanAdminPage extends StatefulWidget {
  const JieyuanAdminPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<JieyuanAdminPage> createState() => _JieyuanAdminPageState();
}

class _JieyuanAdminPageState extends State<JieyuanAdminPage> {
  Map<String, dynamic>? data;
  String? error;
  bool busy = false;
  final user = TextEditingController(),
      level = TextEditingController(text: '1'),
      post = TextEditingController(),
      message = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    user.dispose();
    level.dispose();
    post.dispose();
    message.dispose();
    super.dispose();
  }

  Future<void> load() async {
    try {
      final d = await widget.api.call('jieyuan.get');
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  Future<void> send(String action, Map<String, dynamic> value) async {
    if (busy) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.call(action, value);
      await load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已保存')));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = data?['config'] as Map?;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        const Text('结缘管理', style: TextStyle(fontSize: 24)),
        if (error != null) Text(error!),
        if (data == null)
          TextButton(onPressed: load, child: const Text('加载 / 重试')),
        if (c != null) ...[
          for (final e in {
            'enabled': '结缘总开关',
            'free': '免费结缘',
            'paid': '有偿转让',
            'wanted': '求结缘',
            'images': '结缘图片',
            'resource_images': '资源图片总开关',
          }.entries)
            SwitchListTile(
              title: Text(e.value),
              value: c[e.key] == true,
              onChanged: busy ? null : (v) => setState(() => c[e.key] = v),
            ),
          TextFormField(
            initialValue: c['rules'],
            maxLines: 4,
            decoration: const InputDecoration(labelText: '结缘规则'),
            onChanged: (v) => c['rules'] = v,
          ),
          TextFormField(
            initialValue: (c['currencies'] as List).join(','),
            decoration: const InputDecoration(labelText: '币种（逗号分隔）'),
            onChanged: (v) => c['currencies'] = v
                .split(',')
                .map((x) => x.trim().toUpperCase())
                .where((x) => x.isNotEmpty)
                .toList(),
          ),
          for (final l in data!['levels'] as List)
            ExpansionTile(
              title: Text('Lv.${l['level']}'),
              children: [
                for (final e in {
                  'enter': '允许进入',
                  'publish': '允许发布',
                  'free': '免费结缘',
                  'paid': '有偿转让',
                  'wanted': '求结缘',
                  'images': '上传图片',
                }.entries)
                  SwitchListTile(
                    title: Text(e.value),
                    value: l['permissions'][e.key] == true,
                    onChanged: busy
                        ? null
                        : (v) => setState(() => l['permissions'][e.key] = v),
                  ),
                for (final e in {
                  'max_images': '每帖图片数（0～30）',
                  'daily_posts': '每日发布数（UTC，0～1000）',
                }.entries)
                  TextFormField(
                    initialValue: '${l['permissions'][e.key]}',
                    decoration: InputDecoration(labelText: e.value),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => l['permissions'][e.key] = int.tryParse(v),
                  ),
              ],
            ),
          FilledButton(
            onPressed: busy
                ? null
                : () => send('jieyuan.save', {
                    'config': c,
                    'levels': data!['levels'],
                  }),
            child: const Text('保存开关与等级权限'),
          ),
          TextField(
            controller: user,
            decoration: const InputDecoration(labelText: '用户 UUID'),
          ),
          TextField(
            controller: level,
            decoration: const InputDecoration(labelText: '等级 1～5'),
          ),
          TextButton(
            onPressed: busy
                ? null
                : () => send('jieyuan.level', {
                    'user_id': user.text.trim(),
                    'level': int.tryParse(level.text),
                  }),
            child: const Text('设置用户等级'),
          ),
          const Divider(),
          const Text('举报与处理'),
          for (final r in data!['reports'] as List)
            ListTile(
              title: Text('${r['reason']}'),
              subtitle: Text('${r['post_id']} · ${r['created_at']}'),
              onTap: () => post.text = r['post_id'],
            ),
          TextField(
            controller: post,
            decoration: const InputDecoration(labelText: '帖子 UUID（点击举报可填入）'),
          ),
          TextField(
            controller: message,
            decoration: const InputDecoration(labelText: '警告内容'),
          ),
          Wrap(
            children: [
              for (final e in {
                'hide': '下架',
                'delete': '删除违规帖（保留记录）',
                'warn': '警告作者',
                'restrict': '限制发帖',
                'ban': '封禁账号',
              }.entries)
                TextButton(
                  onPressed: busy
                      ? null
                      : () async {
                          final ok = await showDialog<bool>(
                            context: context,
                            builder: (ctx) => AlertDialog(
                              title: Text('确认${e.value}？'),
                              content: Text(post.text),
                              actions: [
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, false),
                                  child: const Text('取消'),
                                ),
                                TextButton(
                                  onPressed: () => Navigator.pop(ctx, true),
                                  child: const Text('确认'),
                                ),
                              ],
                            ),
                          );
                          if (ok == true) {
                            await send('jieyuan.moderate', {
                              'post_id': post.text.trim(),
                              'operation': e.key,
                              'message': message.text.trim(),
                            });
                          }
                        },
                  child: Text(e.value),
                ),
            ],
          ),
        ],
      ],
    );
  }
}
