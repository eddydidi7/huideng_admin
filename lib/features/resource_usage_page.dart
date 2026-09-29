import 'package:flutter/material.dart';
import '../data/admin_api.dart';

String usageBytes(dynamic value) =>
    '${((value as num? ?? 0) / 1048576).toStringAsFixed(1)} MB';
String usageModule(String value) =>
    const {
      'public-resources': '公共资料',
      'personal-drive': '个人云盘',
      'forum-files': '红书/论坛',
      'jieyuan': '结缘',
      'chat-files': '聊天附件',
      'chat-voice': '聊天语音',
      'group-files': '群文件',
      'counter-images': '计数图片',
      'chat-avatars': '头像',
    }[value] ??
    value;

class ResourceUsagePage extends StatefulWidget {
  const ResourceUsagePage({super.key, required this.api});
  final AdminApi api;
  @override
  State<ResourceUsagePage> createState() => _ResourceUsagePageState();
}

class _ResourceUsagePageState extends State<ResourceUsagePage> {
  final search = TextEditingController();
  String sort = 'storage', kind = '', status = '', level = '';
  int threshold = 0, offset = 0, unattributed = 0;
  bool busy = false, more = false;
  String? error;
  List<Map<String, dynamic>> rows = [];
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

  Future<void> load({bool reset = false}) async {
    if (reset) offset = 0;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final d = await widget.api.call('usage.list', {
        'search': search.text.trim(),
        'sort': sort,
        'kind': kind,
        'status': status,
        'level': level,
        'threshold': threshold,
        'offset': offset,
      });
      if (!mounted) return;
      final all = (d['items'] as List)
          .map((x) => Map<String, dynamic>.from(x))
          .toList();
      setState(() {
        unattributed = (d['unattributed_storage_files'] as num? ?? 0).toInt();
        more = all.length > 50;
        rows = all.take(50).toList();
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Widget choice(
    String label,
    String value,
    Map<String, String> options,
    void Function(String) change,
  ) => DropdownButton<String>(
    value: value,
    hint: Text(label),
    items: options.entries
        .map((e) => DropdownMenuItem(value: e.key, child: Text(e.value)))
        .toList(),
    onChanged: busy
        ? null
        : (v) {
            setState(() => change(v!));
            load(reset: true);
          },
  );
  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      const Text('用户资源用量', style: TextStyle(fontSize: 24)),
      const Text('实际下载流量：暂无法精确统计，不能按真实流量排序。签发量仅作参考。'),
      const Text('上传历史：升级前仅回溯仍存在的文件，升级后保留上传事件。日期按北京时间。红书和论坛共用帖子表，不重复相加。'),
      if (unattributed > 0) Text('另有 $unattributed 个存储对象无法归属用户，未计入个人用量。'),
      TextField(
        controller: search,
        decoration: InputDecoration(
          labelText: '用户名 / 昵称 / 用户ID',
          suffixIcon: IconButton(
            onPressed: busy ? null : () => load(reset: true),
            icon: const Icon(Icons.search),
          ),
        ),
      ),
      Wrap(
        spacing: 16,
        children: [
          choice('排序', sort, {
            'storage': '总占用降序',
            'upload': '月上传降序',
            'apk': 'APK占用降序',
            'video': '视频占用降序',
            'large': '大文件占用降序',
          }, (v) => sort = v),
          choice('类型', kind, {
            '': '所有类型',
            'apk': '有APK',
            'video': '有视频',
            'large': '有≥50MB文件',
          }, (v) => kind = v),
          choice('等级', level, {
            '': '所有等级',
            for (var n = 1; n <= 5; n++) '$n': '等级 $n',
          }, (v) => level = v),
          choice('状态', status, {
            '': '所有状态',
            'warned': '已警告',
            'restricted': '已限制',
            'banned': '已封禁',
          }, (v) => status = v),
          choice('配额使用', threshold.toString(), {
            '0': '全部配额',
            '70': '≥70%',
            '80': '≥80%',
            '90': '≥90%',
          }, (v) => threshold = int.parse(v)),
          IconButton(
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      for (final r in rows)
        Card(
          child: ListTile(
            isThreeLine: true,
            title: Text(
              '${r['nickname']} · ${r['username']} · 等级${r['level']}',
            ),
            subtitle: Text(
              '已用 ${usageBytes(r['used_bytes'])} + 预留 ${usageBytes(r['pending_bytes'])} / ${usageBytes(r['quota_bytes'])} · ${r['usage_percent']}%\n本月上传 ${usageBytes(r['month_upload_bytes'])} · ${r['month_upload_files']} 个文件${r['banned'] == true
                  ? ' · 已封禁'
                  : r['restricted'] == true
                  ? ' · 已限制'
                  : ''}',
            ),
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => ResourceUsageDetail(
                    api: widget.api,
                    userId: r['user_id'],
                  ),
                ),
              );
              if (mounted) load();
            },
          ),
        ),
      if (!busy && rows.isEmpty) const Text('没有符合条件的用户'),
      Row(
        children: [
          TextButton(
            onPressed: busy || offset == 0
                ? null
                : () {
                    offset -= 50;
                    load();
                  },
            child: const Text('上一页'),
          ),
          Text('${offset ~/ 50 + 1}'),
          TextButton(
            onPressed: busy || !more
                ? null
                : () {
                    offset += 50;
                    load();
                  },
            child: const Text('下一页'),
          ),
        ],
      ),
    ],
  );
}

class ResourceUsageDetail extends StatefulWidget {
  const ResourceUsageDetail({
    super.key,
    required this.api,
    required this.userId,
  });
  final AdminApi api;
  final String userId;
  @override
  State<ResourceUsageDetail> createState() => _ResourceUsageDetailState();
}

class _ResourceUsageDetailState extends State<ResourceUsageDetail> {
  Map<String, dynamic>? data;
  bool busy = false;
  String? error;
  int offset = 0;
  @override
  void initState() {
    super.initState();
    load();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final d = await widget.api.call('usage.detail', {
        'user_id': widget.userId,
        'offset': offset,
      });
      if (mounted) setState(() => data = d);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> action(String name, Map<String, dynamic> payload) async {
    setState(() => busy = true);
    try {
      await widget.api.call(name, {'user_id': widget.userId, ...payload});
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> confirmAction(
    String title,
    String actionName,
    Map<String, dynamic> payload,
  ) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(title),
        content: const Text('此操作会立即影响该账号或公开内容；不会自动删除用户文件。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认'),
          ),
        ],
      ),
    );
    if (yes == true) await action(actionName, payload);
  }

  Future<void> warn() async {
    final t = TextEditingController();
    final message = await showDialog<String>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('向该用户发出警告'),
        content: TextField(controller: t, maxLength: 1000, maxLines: 4),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, t.text.trim()),
            child: const Text('发送'),
          ),
        ],
      ),
    );
    if (message != null && message.isNotEmpty) {
      await action('usage.warn', {'message': message});
    }
  }

  @override
  Widget build(BuildContext context) {
    final u = data?['user'] as Map?;
    final lim = data?['limits'] as Map?;
    return Scaffold(
      appBar: AppBar(title: const Text('用户资源详情')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (u != null) ...[
            Text(
              '${u['nickname']} · ${u['username']} · 等级 ${u['level']}',
              style: const TextStyle(fontSize: 22),
            ),
            SelectableText(widget.userId),
            Text(
              '注册：${u['registered_at']}\n最后活跃：${u['last_active_at'] ?? '暂无记录'}（登录/在线记录）',
            ),
            Text(
              '总占用 ${usageBytes(u['used_bytes'])}；预留 ${usageBytes(u['pending_bytes'])}；剩余 ${usageBytes(u['remaining_bytes'])}；${u['usage_percent']}%',
            ),
            Wrap(
              spacing: 20,
              children: [
                for (final e in {
                  'image': '图片',
                  'document': '文档',
                  'audio': '音频',
                  'apk': 'APK',
                  'video': '视频',
                  'other': '其他',
                  'drive': '云盘合计',
                }.entries)
                  Text('${e.value}：${usageBytes(u['${e.key}_bytes'])}'),
              ],
            ),
            Text(
              '今日上传 ${usageBytes(u['day_upload_bytes'])} / ${u['day_upload_files']} 个；本月 ${usageBytes(u['month_upload_bytes'])} / ${u['month_upload_files']} 个',
            ),
            const Text('今日 / 当月实际下载流量：暂无法精确统计'),
            Text(
              '公共网盘下载签发量（不是实际流量）：今日 ${usageBytes(u['day_download_signed_bytes'])}；本月 ${usageBytes(u['month_download_signed_bytes'])}',
            ),
            Text(
              '红书/论坛 ${u['redbook_posts']} 篇；结缘 ${u['jieyuan_posts']} 篇；聊天附件 ${u['chat_attachment_files']} 个；公共资料 ${u['public_resource_files']} 个',
            ),
          ],
          if (lim != null)
            ExpansionTile(
              title: const Text('等级、个人配额与上传限制'),
              initiallyExpanded: true,
              children: [
                DropdownButton<int>(
                  value: u!['level'] as int,
                  items: [
                    for (var n = 1; n <= 5; n++)
                      DropdownMenuItem(value: n, child: Text('等级 $n')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => u['level'] = v),
                ),
                for (final e in {
                  'quota_bytes': '个人总配额 MB',
                  'daily_bytes': '每日上传 MB',
                  'monthly_bytes': '每月上传 MB',
                  'daily_files': '每日文件数',
                  'monthly_files': '每月文件数',
                }.entries)
                  TextFormField(
                    key: ValueKey('${lim['version']}-${e.key}'),
                    initialValue:
                        '${(lim[e.key] as num) / (e.key.endsWith('bytes') ? 1048576 : 1)}',
                    decoration: InputDecoration(labelText: e.value),
                    keyboardType: TextInputType.number,
                    onChanged: (v) => lim[e.key] =
                        ((double.tryParse(v) ?? -1) *
                                (e.key.endsWith('bytes') ? 1048576 : 1))
                            .round(),
                  ),
                SwitchListTile(
                  title: const Text('暂停该用户全部上传'),
                  value: lim['paused'] == true,
                  onChanged: busy
                      ? null
                      : (v) => setState(() => lim['paused'] = v),
                ),
                DropdownButton<int>(
                  value: lim['_hours'] as int? ?? -1,
                  items: const [
                    DropdownMenuItem(value: -1, child: Text('保持当前期限')),
                    DropdownMenuItem(value: 0, child: Text('限制长期有效')),
                    DropdownMenuItem(value: 1, child: Text('限制1小时')),
                    DropdownMenuItem(value: 24, child: Text('限制1天')),
                    DropdownMenuItem(value: 168, child: Text('限制7天')),
                  ],
                  onChanged: busy
                      ? null
                      : (v) => setState(() => lim['_hours'] = v),
                ),
                Text(
                  '现有截止时间：${lim['paused_until'] ?? lim['types_until'] ?? '长期 / 未限制'}',
                ),
                Wrap(
                  children: [
                    for (final e in {
                      'image': '禁止图片',
                      'file': '禁止所有非图片文件',
                      'apk': '禁止APK',
                      'video': '禁止视频',
                    }.entries)
                      FilterChip(
                        label: Text(e.value),
                        selected: (lim['blocked_types'] as List).contains(
                          e.key,
                        ),
                        onSelected: busy
                            ? null
                            : (v) => setState(() {
                                final list = List<String>.from(
                                  lim['blocked_types'],
                                );
                                v ? list.add(e.key) : list.remove(e.key);
                                lim['blocked_types'] = list.toSet().toList();
                              }),
                      ),
                  ],
                ),
                FilledButton(
                  onPressed: busy
                      ? null
                      : () {
                          final n = lim['_hours'] as int?;
                          final payload = Map<String, dynamic>.from(lim)
                            ..remove('_hours');
                          if (n != null && n >= 0) {
                            final end = n == 0
                                ? null
                                : DateTime.now()
                                      .toUtc()
                                      .add(Duration(hours: n))
                                      .toIso8601String();
                            payload['paused_until'] = end;
                            payload['types_until'] = end;
                          }
                          confirmAction('保存此用户的配额与限制？', 'usage.save', {
                            ...payload,
                            'level': u['level'],
                          });
                        },
                  child: const Text('保存等级、配额与限制'),
                ),
              ],
            ),
          Wrap(
            spacing: 12,
            children: [
              OutlinedButton(
                onPressed: busy ? null : warn,
                child: const Text('发出警告'),
              ),
              OutlinedButton(
                onPressed: busy
                    ? null
                    : () => confirmAction('封禁此账号？', 'usage.ban', {}),
                child: const Text('封禁账号'),
              ),
            ],
          ),
          for (final w in data?['warnings'] ?? [])
            ListTile(
              title: Text(w['message']),
              subtitle: Text(w['created_at']),
            ),
          const Divider(),
          const Text('文件清单：仅元数据，不提供私人笔记或聊天文字、文件内容预览。'),
          for (final f in (data?['files'] as List? ?? []).take(100))
            ListTile(
              title: Text('${f['name']}'),
              subtitle: Text(
                '${usageModule(f['source'])} · ${f['kind']} · ${usageBytes(f['bytes'])} · ${f['created_at']}${f['pending'] == true ? ' · 预留/待完成' : ''}',
              ),
            ),
          Row(
            children: [
              TextButton(
                onPressed: busy || offset == 0
                    ? null
                    : () {
                        offset -= 100;
                        load();
                      },
                child: const Text('上一页文件'),
              ),
              TextButton(
                onPressed:
                    busy ||
                        ['files', 'posts', 'resources'].every(
                          (key) => (data?[key] as List? ?? []).length <= 100,
                        )
                    ? null
                    : () {
                        offset += 100;
                        load();
                      },
                child: const Text('下一页文件/公开内容'),
              ),
            ],
          ),
          const Text('公开内容管理（不删除文件）'),
          for (final p in (data?['posts'] as List? ?? []).take(100))
            ListTile(
              title: Text('${p['title']} · ${p['visibility']}'),
              trailing: TextButton(
                onPressed: busy
                    ? null
                    : () => confirmAction('下架这篇公开内容？', 'usage.hide', {
                        'module': 'forum',
                        'id': p['id'],
                      }),
                child: const Text('下架'),
              ),
            ),
          for (final f in (data?['resources'] as List? ?? []).take(100))
            ListTile(
              title: Text(f['file_name']),
              trailing: TextButton(
                onPressed: busy
                    ? null
                    : () => confirmAction('下架这份公共资料？', 'usage.hide', {
                        'module': 'public-resources',
                        'id': f['id'],
                      }),
                child: const Text('下架'),
              ),
            ),
        ],
      ),
    );
  }
}
