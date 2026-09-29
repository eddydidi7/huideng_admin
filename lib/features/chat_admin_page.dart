import 'package:flutter/material.dart';
import '../data/admin_api.dart';

class ChatAdminPage extends StatefulWidget {
  const ChatAdminPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<ChatAdminPage> createState() => _ChatAdminPageState();
}

class _ChatAdminPageState extends State<ChatAdminPage> {
  List<dynamic> rows = [];
  Map<String, dynamic>? room;
  int offset = 0;
  bool busy = false;
  String? error;
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

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final r = await widget.api
          .call(room == null ? 'chat.list' : 'chat.members', {
            'offset': offset,
            'query': search.text.trim(),
            if (room != null) 'room_id': room!['id'],
          });
      if (mounted) setState(() => rows = r['items'] as List);
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> limit(Map<String, dynamic> group) async {
    final input = TextEditingController(text: '${group['member_limit']}');
    final value = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('设置群人数上限'),
        content: TextField(
          controller: input,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: '0 表示不限人数',
            helperText: '降低上限不自动移除已有成员。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, input.text),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    // Controller disposal is deferred until the dialog animation completes.
    Future.delayed(const Duration(seconds: 1), input.dispose);
    if (value == null || !mounted) return;
    final n = int.tryParse(value);
    if (n == null || n < 0) {
      setState(() => error = '请填写0或正整数。');
      return;
    }
    await mutate('chat.limit', {
      'room_id': group['id'],
      'member_limit': n,
      'previous_limit': group['member_limit'],
    });
  }

  Future<void> remove(Map<String, dynamic> member) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('移除群成员'),
        content: Text('将“${member['nickname']}”移出本群？聊天记录保留。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('移除'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await mutate('chat.remove', {
        'room_id': room!['id'],
        'user_id': member['user_id'],
      });
    }
  }

  Future<void> mutate(String action, Map<String, dynamic> payload) async {
    setState(() => busy = true);
    try {
      await widget.api.call(action, payload);
      if (mounted) await load();
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Row(
        children: [
          if (room != null)
            IconButton(
              onPressed: busy
                  ? null
                  : () {
                      room = null;
                      offset = 0;
                      load();
                    },
              icon: const Icon(Icons.arrow_back),
            ),
          Expanded(
            child: Text(
              room == null ? '群聊管理' : '${room!['title']} · 成员',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          TextButton(onPressed: busy ? null : load, child: const Text('刷新')),
        ],
      ),
      if (room == null)
        TextField(
          controller: search,
          decoration: const InputDecoration(
            labelText: '按群名搜索',
            suffixIcon: Icon(Icons.search),
          ),
          onSubmitted: (_) {
            offset = 0;
            load();
          },
        ),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        Text(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      Expanded(
        child: ListView(
          children: [
            for (final row in rows)
              ListTile(
                title: Text('${row[room == null ? 'title' : 'nickname']}'),
                subtitle: Text(
                  room == null
                      ? '${row['member_count']}人 · 上限：${row['member_limit'] == 0 ? '不限' : row['member_limit']}'
                      : '个人号：${row['personal_number']}',
                ),
                onTap: room == null && !busy
                    ? () {
                        room = Map<String, dynamic>.from(row);
                        offset = 0;
                        load();
                      }
                    : null,
                trailing: room == null
                    ? TextButton(
                        onPressed: busy
                            ? null
                            : () => limit(Map<String, dynamic>.from(row)),
                        child: const Text('设置上限'),
                      )
                    : row['user_id'] == room!['owner_id']
                    ? const Text('群主')
                    : TextButton(
                        onPressed: busy
                            ? null
                            : () => remove(Map<String, dynamic>.from(row)),
                        child: const Text('移除'),
                      ),
              ),
          ],
        ),
      ),
      Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          TextButton(
            onPressed: busy || offset == 0
                ? null
                : () {
                    offset -= (room == null ? 50 : 100);
                    load();
                  },
            child: const Text('上一页'),
          ),
          TextButton(
            onPressed: busy || rows.length < (room == null ? 50 : 100)
                ? null
                : () {
                    offset += (room == null ? 50 : 100);
                    load();
                  },
            child: const Text('下一页'),
          ),
        ],
      ),
    ],
  );
}
