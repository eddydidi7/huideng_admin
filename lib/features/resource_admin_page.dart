import 'package:flutter/material.dart';
import '../data/admin_api.dart';

class ResourceAdminPage extends StatefulWidget {
  const ResourceAdminPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<ResourceAdminPage> createState() => _ResourceAdminPageState();
}

class _ResourceAdminPageState extends State<ResourceAdminPage> {
  Map<String, dynamic>? config;
  List<Map<String, dynamic>> files = [];
  bool busy = false, more = false;
  String? error;
  int offset = 0;
  final search = TextEditingController();
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
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final next = page ?? offset;
      final d = await widget.api.call('resources.list', {
        'search': search.text.trim(),
        'offset': next,
      });
      if (mounted) {
        setState(() {
          config = Map<String, dynamic>.from(d['config']);
          final all = (d['files'] as List)
              .map((x) => Map<String, dynamic>.from(x))
              .toList();
          more = all.length > 50;
          files = all.take(50).toList();
          offset = next;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    setState(() => busy = true);
    try {
      await widget.api.call('resources.settings', config!);
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> remove(Map<String, dynamic> file) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除公共资料？'),
        content: Text(
          '${file['file_name']}\n删除公共网盘中的引用。群文件等其他有效引用不受影响；实体文件仅在引用归零并满足清理条件后清理。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => busy = true);
    try {
      await widget.api.call('resources.delete', {'id': file['id']});
      await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  String bytes(dynamic n) =>
      '${((n as num? ?? 0) / 1048576).toStringAsFixed(1)} MB';
  @override
  Widget build(BuildContext context) {
    final c = config;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Row(
          children: [
            const Expanded(child: Text('公共网盘', style: TextStyle(fontSize: 24))),
            IconButton(
              onPressed: busy ? null : () => load(),
              icon: const Icon(Icons.refresh),
            ),
          ],
        ),
        const Text('用户上传完成后直接公开，无需审核。'),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        if (c != null) ...[
          Text('已用及预留：${bytes(c['used_bytes'])} / ${bytes(c['total_bytes'])}'),
          for (final e in {
            'enabled': '公共网盘总开关',
            'upload_enabled': '允许用户上传',
            'download_enabled': '允许用户下载',
            if (c.containsKey('uploader_delete_enabled'))
              'uploader_delete_enabled': '允许用户删除自己上传的文件',
            if (c.containsKey('group_transfer_enabled'))
              'group_transfer_enabled': '允许公共网盘与群文件互相转存',
          }.entries)
            SwitchListTile(
              title: Text(e.value),
              value: c[e.key] == true,
              onChanged: busy ? null : (v) => setState(() => c[e.key] = v),
            ),
          if (!c.containsKey('uploader_delete_enabled') ||
              !c.containsKey('group_transfer_enabled'))
            const Text('服务端尚未提供删除/转存权限设置，请先部署 077、078 迁移。'),
          ExpansionTile(
            title: const Text('容量、限额与分类'),
            children: [
              for (final e in {
                'total_bytes': '共享容量（MB）',
                'max_file_bytes': '单文件上限（MB，最大512）',
                'daily_upload_bytes': '每人每日上传额度（MB）',
                'daily_download_bytes': '每人每日下载签发额度（MB）',
              }.entries)
                TextFormField(
                  key: ValueKey('${c['version']}-${e.key}'),
                  initialValue: '${(c[e.key] as num) / 1048576}',
                  decoration: InputDecoration(labelText: e.value),
                  keyboardType: TextInputType.number,
                  onChanged: (v) =>
                      c[e.key] = ((double.tryParse(v) ?? -1) * 1048576).round(),
                ),
              TextFormField(
                key: ValueKey('categories-${c['version']}'),
                initialValue: (c['categories'] as List).join('，'),
                decoration: const InputDecoration(labelText: '分类（逗号分隔）'),
                onChanged: (v) => c['categories'] = v
                    .split(RegExp('[,，]'))
                    .map((x) => x.trim())
                    .where((x) => x.isNotEmpty)
                    .toList(),
              ),
              TextFormField(
                key: ValueKey('notice-${c['version']}'),
                initialValue: c['notice'],
                decoration: const InputDecoration(labelText: '公告'),
                onChanged: (v) => c['notice'] = v,
              ),
            ],
          ),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('保存开关与设置'),
          ),
          const Text(
            '关闭下载后停止签发新链接；已签发链接最长约2分钟失效。大文件删除会先隐藏，为等待上传凭证过期，存储清理可能延迟26小时，之后刷新后台继续清理。容量仍受 Supabase 套餐限制。',
          ),
          const Divider(),
          TextField(
            controller: search,
            decoration: InputDecoration(
              labelText: '搜索文件',
              suffixIcon: IconButton(
                onPressed: busy ? null : () => load(page: 0),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
          for (final f in files)
            ListTile(
              title: Text('${f['file_name']}'),
              subtitle: Text(
                '${bytes(f['file_size'])} · ${f['author_name']} · ${{'uploading': '上传中', 'published': '已公开', 'deleting': '正在清理'}[f['status']] ?? f['status']}',
              ),
              trailing: IconButton(
                onPressed: busy || f['status'] == 'deleting'
                    ? null
                    : () => remove(f),
                tooltip: '删除',
                icon: const Icon(Icons.delete_outline),
              ),
            ),
          if (files.isEmpty)
            const Padding(padding: EdgeInsets.all(20), child: Text('暂无公共资料')),
          Row(
            children: [
              TextButton(
                onPressed: busy || offset == 0
                    ? null
                    : () => load(page: offset - 50),
                child: const Text('上一页'),
              ),
              Text('${offset ~/ 50 + 1}'),
              TextButton(
                onPressed: busy || !more ? null : () => load(page: offset + 50),
                child: const Text('下一页'),
              ),
            ],
          ),
        ],
      ],
    );
  }
}
