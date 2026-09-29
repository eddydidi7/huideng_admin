import 'package:flutter/material.dart';
import '../data/admin_api.dart';

class MembersPage extends StatefulWidget {
  final AdminApi api;
  const MembersPage({super.key, required this.api});
  @override
  State<MembersPage> createState() => _MembersPageState();
}

class _MembersPageState extends State<MembersPage> {
  List<Map<String, dynamic>> items = [];
  bool busy = true;
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
      final value = await widget.api.call('members.list');
      if (mounted) {
        setState(
          () => items = (value['items'] as List)
              .map((e) => Map<String, dynamic>.from(e))
              .toList(),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => MemberEditor(api: widget.api, row: row),
      ),
    );
    if (saved == true && mounted) load();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('后台管理员')),
    body: ListView(
      padding: const EdgeInsets.all(24),
      children: [
        const Text('请先让对方拥有已注册账号，再授予后台权限。只有超级管理员可以授权；不能在此修改自己的权限。'),
        const SizedBox(height: 16),
        FilledButton(
          onPressed: busy ? null : () => edit(),
          child: const Text('添加管理员'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null) Text(error!),
        for (final row in items)
          Card(
            child: ListTile(
              title: Text('${row['email']}'),
              subtitle: Text(
                '${label(row['role'])} · ${row['enabled'] == true ? '已启用' : '已停用'}',
              ),
              trailing: TextButton(
                onPressed: busy ? null : () => edit(row),
                child: const Text('修改权限'),
              ),
            ),
          ),
      ],
    ),
  );
}

String label(Object? role) => switch (role) {
  'super_admin' => '超级管理员',
  'admin' => '管理员',
  'moderator' => '版主',
  _ => '未知角色',
};

class MemberEditor extends StatefulWidget {
  final AdminApi api;
  final Map<String, dynamic>? row;
  const MemberEditor({super.key, required this.api, this.row});
  @override
  State<MemberEditor> createState() => _MemberEditorState();
}

class _MemberEditorState extends State<MemberEditor> {
  late final email = TextEditingController(text: widget.row?['email'] ?? '');
  late String role = widget.row?['role'] ?? 'moderator';
  late bool enabled = widget.row?['enabled'] ?? true;
  bool busy = false;
  String? error;
  @override
  void dispose() {
    email.dispose();
    super.dispose();
  }

  Future<void> save() async {
    if (!email.text.contains('@')) {
      setState(() => error = '请填写已注册账号的邮箱。');
      return;
    }
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('确认修改后台权限？'),
        content: Text(
          '${email.text.trim()}\n角色：${label(role)}\n${enabled ? '启用' : '停用'}',
        ),
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
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await widget.api.call('members.save', {
        'email': email.text.trim(),
        'role': role,
        'enabled': enabled,
        if (widget.row != null) 'updated_at': widget.row!['updated_at'],
      });
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
      appBar: AppBar(title: const Text('管理员权限')),
      body: ListView(
        padding: const EdgeInsets.all(28),
        children: [
          TextField(
            controller: email,
            enabled: !busy && widget.row == null,
            decoration: const InputDecoration(labelText: '账号邮箱'),
          ),
          const SizedBox(height: 20),
          DropdownButtonFormField<String>(
            initialValue: role,
            decoration: const InputDecoration(labelText: '后台角色'),
            items: [
              for (final r in ['super_admin', 'admin', 'moderator'])
                DropdownMenuItem(value: r, child: Text(label(r))),
            ],
            onChanged: busy ? null : (v) => setState(() => role = v!),
          ),
          SwitchListTile(
            title: const Text('启用后台权限'),
            value: enabled,
            onChanged: busy ? null : (v) => setState(() => enabled = v),
          ),
          if (error != null) Text(error!),
          FilledButton(
            onPressed: busy ? null : save,
            child: const Text('保存权限'),
          ),
        ],
      ),
    ),
  );
}
