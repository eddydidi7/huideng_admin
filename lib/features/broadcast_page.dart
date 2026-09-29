import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/admin_api.dart';
import '../services/generic_file_metadata.dart';
import '../services/release_apk_uploader.dart';

String fileSizeText(num bytes) {
  const units = ['B', 'KB', 'MB', 'GB', 'TB'];
  var value = bytes.toDouble();
  var unit = 0;
  while (value >= 1024 && unit < units.length - 1) {
    value /= 1024;
    unit++;
  }
  return '${value.toStringAsFixed(unit == 0 ? 0 : 1)} ${units[unit]}';
}

/// Group-send a file to users' chat "文件传输助手", backed by
/// huideng_admin_broadcast (202609290076, huideng_counter repo) via the
/// admin-api edge function's broadcast.* actions.
class BroadcastPage extends StatefulWidget {
  final AdminApi api;
  const BroadcastPage({super.key, required this.api});
  @override
  State<BroadcastPage> createState() => _BroadcastPageState();
}

class _BroadcastPageState extends State<BroadcastPage> {
  List<Map<String, dynamic>> rows = [];
  bool busy = false;
  String? error;
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
      final data = await widget.api.call('broadcast.list');
      if (mounted) {
        setState(
          () => rows = (data['items'] as List)
              .map((r) => Map<String, dynamic>.from(r))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> compose() async {
    final sent = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => BroadcastComposePage(api: widget.api)),
    );
    if (sent == true && mounted) await load();
  }

  String targetText(Map<String, dynamic> row) => switch (row['target_type']) {
    'all' => '全部用户',
    'level' => '${row['target_level']} 级用户',
    _ => '指定用户',
  };

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        spacing: 12,
        children: [
          FilledButton.icon(
            onPressed: busy ? null : compose,
            icon: const Icon(Icons.send_outlined),
            label: const Text('新建群发'),
          ),
          TextButton(onPressed: busy ? null : load, child: const Text('刷新')),
        ],
      ),
      const Text('文件发送到目标用户的"聊天 → 文件传输助手"，不影响用户之间的私聊传输。'),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      for (final row in rows)
        Card(
          child: ListTile(
            title: Text(
              (row['title'] as String? ?? '').isNotEmpty
                  ? row['title'] as String
                  : row['file_name'] as String? ?? '',
            ),
            subtitle: Text(
              '${row['file_name']} · ${fileSizeText((row['file_size'] as num?) ?? 0)}\n'
              '目标：${targetText(row)} · 收件 ${row['recipient_count']} 人 · '
              '已读 ${row['read_count']} · 已下载 ${row['downloaded_count']}\n'
              '${row['created_at']}',
            ),
            isThreeLine: true,
          ),
        ),
      if (!busy && rows.isEmpty && error == null) const Text('暂无群发记录'),
    ],
  );
}

class BroadcastComposePage extends StatefulWidget {
  final AdminApi api;
  const BroadcastComposePage({super.key, required this.api});
  @override
  State<BroadcastComposePage> createState() => _BroadcastComposePageState();
}

class _BroadcastComposePageState extends State<BroadcastComposePage> {
  final title = TextEditingController();
  final note = TextEditingController();
  final fileName = TextEditingController();
  final downloadUrl = TextEditingController();
  final fileSize = TextEditingController();
  final search = TextEditingController();
  String targetType = 'all';
  int targetLevel = 1;
  bool useExistingUrl = false;
  bool busy = false;
  bool uploading = false;
  double uploadProgress = 0;
  String? error;
  String? result;
  String? pickedPath;
  String? pickedSha256;
  List<Map<String, dynamic>> searchResults = [];
  final Map<String, String> selected = {}; // user_id -> label

  @override
  void dispose() {
    title.dispose();
    note.dispose();
    fileName.dispose();
    downloadUrl.dispose();
    fileSize.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> pickAndUpload() async {
    setState(() {
      error = null;
      uploading = true;
      uploadProgress = 0;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(withData: false);
      final path = picked?.files.single.path;
      if (path == null) {
        setState(() => uploading = false);
        return;
      }
      final meta = await inspectGenericFile(path);
      final api = widget.api;
      if (api is! SupabaseAdminApi) throw StateError('当前连接不支持文件上传');
      final url = await ReleaseApkUploader(
        api.client,
        const String.fromEnvironment('ADMIN_SUPABASE_URL'),
      ).upload(
        meta,
        (p) {
          if (mounted) setState(() => uploadProgress = p);
        },
        mimeType: 'application/octet-stream',
      );
      if (!mounted) return;
      setState(() {
        pickedPath = path;
        pickedSha256 = meta.hash;
        fileName.text = path.split(RegExp(r'[/\\]')).last;
        fileSize.text = '${meta.size}';
        downloadUrl.text = url;
      });
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => uploading = false);
    }
  }

  Future<void> searchUsers() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.call('users.list', {
        'search': search.text.trim(),
        'offset': 0,
      });
      if (mounted) {
        setState(
          () => searchResults = (data['items'] as List)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> send() async {
    if (fileName.text.trim().isEmpty || downloadUrl.text.trim().isEmpty) {
      setState(() => error = '请先选择文件并等待上传完成，或填写下载地址。');
      return;
    }
    final size = int.tryParse(fileSize.text.trim());
    if (size == null || size < 1) {
      setState(() => error = '文件字节数无效。');
      return;
    }
    if (targetType == 'users' && selected.isEmpty) {
      setState(() => error = '请至少选择一个接收用户。');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认发送？'),
        content: Text(
          '文件：${fileName.text}\n'
          '目标：${switch (targetType) {
            'all' => '全部用户',
            'level' => '$targetLevel 级用户',
            _ => '已选 ${selected.length} 人',
          }}',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('取消')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('确认发送')),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final payload = <String, dynamic>{
        'title': title.text.trim(),
        'note': note.text.trim(),
        'file_name': fileName.text.trim(),
        'download_url': downloadUrl.text.trim(),
        'file_size': size,
        if (pickedSha256 != null) 'sha256': pickedSha256,
        'target_type': targetType,
        if (targetType == 'level') 'target_level': targetLevel,
        if (targetType == 'users') 'target_ids': selected.keys.toList(),
      };
      final data = await widget.api.call('broadcast.send', payload);
      if (!mounted) return;
      setState(
        () => result =
            '发送成功：目标人数 ${data['recipient_count']}'
            '${(data['failed'] as num? ?? 0) > 0 ? '，未找到 ${data['failed']} 人' : ''}',
      );
      await Future<void>.delayed(const Duration(seconds: 2));
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !busy,
    child: Scaffold(
      appBar: AppBar(title: const Text('新建群发')),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          TextField(
            controller: title,
            enabled: !busy,
            decoration: const InputDecoration(labelText: '标题（可选）'),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: note,
            enabled: !busy,
            maxLines: 3,
            decoration: const InputDecoration(labelText: '说明（可选）'),
          ),
          const SizedBox(height: 20),
          Text('文件', style: Theme.of(context).textTheme.titleMedium),
          SwitchListTile(
            title: const Text('使用已有下载链接（例如复用某个已发布版本的 APK，不重复占用存储）'),
            value: useExistingUrl,
            onChanged: busy || uploading
                ? null
                : (v) => setState(() {
                    useExistingUrl = v;
                    pickedPath = null;
                    pickedSha256 = null;
                    fileName.clear();
                    downloadUrl.clear();
                    fileSize.clear();
                  }),
          ),
          if (!useExistingUrl) ...[
            FilledButton.icon(
              onPressed: busy || uploading ? null : pickAndUpload,
              icon: const Icon(Icons.upload_file),
              label: Text(pickedPath == null ? '选择文件并上传' : '重新选择并上传'),
            ),
            if (uploading) ...[
              const SizedBox(height: 8),
              LinearProgressIndicator(value: uploadProgress),
              Text('${(uploadProgress * 100).toStringAsFixed(0)}%'),
            ],
            if (pickedPath != null)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text('已上传：${fileName.text} · ${fileSizeText(int.tryParse(fileSize.text) ?? 0)}'),
              ),
          ] else ...[
            const SizedBox(height: 8),
            TextField(
              controller: fileName,
              enabled: !busy,
              decoration: const InputDecoration(labelText: '文件名'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: downloadUrl,
              enabled: !busy,
              decoration: const InputDecoration(labelText: 'HTTPS 下载地址'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: fileSize,
              enabled: !busy,
              keyboardType: TextInputType.number,
              decoration: const InputDecoration(labelText: '文件字节数（须与实际一致，否则用户端下载会校验失败）'),
            ),
          ],
          const SizedBox(height: 20),
          Text('接收对象', style: Theme.of(context).textTheme.titleMedium),
          for (final entry in const {'all': '全部用户', 'users': '指定用户', 'level': '按群发等级'}.entries)
            RadioListTile<String>(
              value: entry.key,
              groupValue: targetType,
              title: Text(entry.value),
              onChanged: busy ? null : (v) => setState(() => targetType = v ?? targetType),
            ),
          if (targetType == 'level')
            DropdownButtonFormField<int>(
              initialValue: targetLevel,
              decoration: const InputDecoration(labelText: '等级（1-5，未单独设置的用户默认 1 级）'),
              items: [for (var i = 1; i <= 5; i++) DropdownMenuItem(value: i, child: Text('$i 级'))],
              onChanged: busy ? null : (v) => setState(() => targetLevel = v ?? targetLevel),
            ),
          if (targetType == 'users') ...[
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: search,
                    enabled: !busy,
                    decoration: const InputDecoration(hintText: '搜索昵称、个人号或邮箱'),
                    onSubmitted: (_) => searchUsers(),
                  ),
                ),
                TextButton(onPressed: busy ? null : searchUsers, child: const Text('搜索')),
              ],
            ),
            if (selected.isNotEmpty)
              Wrap(
                spacing: 6,
                children: [
                  for (final e in selected.entries)
                    Chip(
                      label: Text(e.value),
                      onDeleted: busy ? null : () => setState(() => selected.remove(e.key)),
                    ),
                ],
              ),
            for (final u in searchResults)
              CheckboxListTile(
                dense: true,
                value: selected.containsKey(u['id']),
                title: Text('${u['nickname'] ?? u['email'] ?? '访客用户'}'),
                subtitle: Text('个人号：${u['personal_number'] ?? '未生成'}'),
                onChanged: busy
                    ? null
                    : (v) => setState(() {
                        final label = '${u['nickname'] ?? u['email'] ?? '访客用户'}';
                        if (v == true) {
                          selected[u['id'] as String] = label;
                        } else {
                          selected.remove(u['id']);
                        }
                      }),
              ),
          ],
          const SizedBox(height: 20),
          if (error != null)
            Text(error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          if (result != null) Text(result!),
          FilledButton(
            onPressed: busy || uploading ? null : send,
            child: Text(busy ? '发送中…' : '发送'),
          ),
        ],
      ),
    ),
  );
}
