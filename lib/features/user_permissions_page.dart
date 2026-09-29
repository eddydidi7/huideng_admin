import 'dart:async';
import 'package:flutter/material.dart';
import '../data/admin_api.dart';

String permissionStatus(Object? value) => switch (value) {
  'normal' => '正常',
  'partially_frozen' => '部分功能冻结',
  'all_frozen' => '全部冻结',
  _ => '权限状态未获取',
};

class UserPermissionsPage extends StatefulWidget {
  const UserPermissionsPage({super.key, required this.api, required this.user});
  final AdminApi api;
  final Map<String, dynamic> user;
  @override
  State<UserPermissionsPage> createState() => _UserPermissionsPageState();
}

class _UserPermissionsPageState extends State<UserPermissionsPage> {
  Map<String, dynamic>? state;
  final selected = <String>{};
  bool busy = false;
  String? error;
  Timer? refresh;
  List<Map<String, dynamic>> get permissions =>
      (state?['permissions'] as List? ?? [])
          .cast<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  String keyOf(Map p) => '${p['feature']}.${p['permission']}';
  String date(Object? value) =>
      DateTime.tryParse('$value')?.toLocal().toString().split('.').first ?? '-';

  @override
  void initState() {
    super.initState();
    load();
    refresh = Timer.periodic(const Duration(seconds: 30), (_) => load());
  }

  @override
  void dispose() {
    refresh?.cancel();
    super.dispose();
  }

  Future<void> load() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final result = await widget.api.call('permissions.get', {
        'user_id': widget.user['id'],
      });
      if (mounted) {
        setState(() {
          state = result;
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> change(
    bool freeze, {
    bool all = false,
    Map<String, dynamic>? single,
  }) async {
    if (busy || state == null) return;
    final targets = single != null
        ? [single]
        : permissions.where((p) => all || selected.contains(keyOf(p))).toList();
    if (targets.isEmpty) return;
    final revision = state!['revision'];
    setState(() => busy = true);
    try {
      final options = await showDialog<Map<String, dynamic>>(
        context: context,
        builder: (_) =>
            _RestrictionDialog(freeze: freeze, count: targets.length),
      );
      if (options == null || !mounted) return;
      final result = await widget.api.call(
        freeze ? 'permissions.freeze' : 'permissions.restore',
        {
          'user_id': widget.user['id'],
          'revision': revision,
          'permissions': targets
              .map(
                (p) => {'feature': p['feature'], 'permission': p['permission']},
              )
              .toList(),
          ...options,
        },
      );
      if (mounted) {
        setState(() {
          state = result;
          selected.clear();
          error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> audit() async {
    try {
      final result = await widget.api.call('permissions.audit', {
        'user_id': widget.user['id'],
      });
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('最近 100 条操作记录'),
          content: SizedBox(
            width: 680,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: (result['items'] as List)
                    .map(
                      (a) => ListTile(
                        title: Text(
                          '${a['operation'] == 'freeze' ? '冻结' : '恢复'} · ${date(a['created_at'])}',
                        ),
                        subtitle: SelectableText(
                          '原因：${a['reason']}\n管理员：${a['operator_id']}',
                        ),
                      ),
                    )
                    .toList(),
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
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: Text(
        '${widget.user['nickname'] ?? widget.user['email'] ?? '访客用户'} · 功能权限',
      ),
      actions: [
        IconButton(
          tooltip: '操作记录',
          onPressed: busy ? null : audit,
          icon: const Icon(Icons.history),
        ),
        IconButton(
          tooltip: '刷新',
          onPressed: busy ? null : load,
          icon: const Icon(Icons.refresh),
        ),
      ],
    ),
    body: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: SelectableText(
            '个人号：${widget.user['personal_number'] ?? '未生成'}\n用户 ID：${widget.user['id']}\n${permissionStatus(state?['status'])}',
          ),
        ),
        Wrap(
          spacing: 8,
          children: [
            TextButton(
              onPressed: busy ? null : () => change(true),
              child: Text('冻结所选 (${selected.length})'),
            ),
            TextButton(
              onPressed: busy ? null : () => change(false),
              child: const Text('恢复所选'),
            ),
            TextButton(
              onPressed: busy ? null : () => change(true, all: true),
              child: const Text('全部冻结'),
            ),
            TextButton(
              onPressed: busy ? null : () => change(false, all: true),
              child: const Text('全部恢复'),
            ),
          ],
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(
              error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ),
        Expanded(
          child: ListView.builder(
            itemCount: permissions.length,
            itemBuilder: (_, i) {
              final p = permissions[i];
              final r = p['restriction'] as Map?;
              final frozen = r != null;
              final remaining = (p['remaining_seconds'] as num?)?.ceil();
              return CheckboxListTile(
                value: selected.contains(keyOf(p)),
                onChanged: busy
                    ? null
                    : (value) => setState(() {
                        if (value == true) {
                          selected.add(keyOf(p));
                        } else {
                          selected.remove(keyOf(p));
                        }
                      }),
                title: Text('${p['feature_label']} · ${p['label']}'),
                subtitle: Text(
                  frozen
                      ? '已冻结 · ${r['permanent'] == true ? '永久' : '剩余 ${((remaining ?? 0) / 60).ceil()} 分钟'}\n开始：${date(r['frozen_at'])}\n到期：${r['permanent'] == true ? '永久' : date(r['expires_at'])}\n原因：${r['reason']}\n管理员：${p['operator_id']}'
                      : '正常',
                ),
                secondary: IconButton(
                  tooltip: frozen ? '恢复此项' : '冻结此项',
                  onPressed: busy ? null : () => change(!frozen, single: p),
                  icon: Icon(frozen ? Icons.lock_open : Icons.lock_outline),
                ),
                controlAffinity: ListTileControlAffinity.leading,
              );
            },
          ),
        ),
      ],
    ),
  );
}

class _RestrictionDialog extends StatefulWidget {
  const _RestrictionDialog({required this.freeze, required this.count});
  final bool freeze;
  final int count;
  @override
  State<_RestrictionDialog> createState() => _RestrictionDialogState();
}

class _RestrictionDialogState extends State<_RestrictionDialog> {
  final reason = TextEditingController();
  String duration = '7d';
  DateTime? expiry;
  @override
  void dispose() {
    reason.dispose();
    super.dispose();
  }

  Future<void> chooseDate() async {
    final now = DateTime.now();
    final day = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 7)),
      firstDate: now,
      lastDate: DateTime(now.year + 20),
    );
    if (day == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.now(),
    );
    if (time != null && mounted) {
      setState(
        () => expiry = DateTime(
          day.year,
          day.month,
          day.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: Text('${widget.freeze ? '冻结' : '恢复'} ${widget.count} 项权限'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.freeze)
              DropdownButtonFormField<String>(
                initialValue: duration,
                decoration: const InputDecoration(labelText: '冻结期限'),
                items:
                    const {
                          '3d': '3天',
                          '7d': '7天',
                          '14d': '14天',
                          '21d': '21天',
                          '30d': '30天',
                          '1y': '1年',
                          'permanent': '永久',
                          'custom': '自定义',
                        }.entries
                        .map(
                          (e) => DropdownMenuItem(
                            value: e.key,
                            child: Text(e.value),
                          ),
                        )
                        .toList(),
                onChanged: (v) => setState(() => duration = v!),
              ),
            if (widget.freeze && duration == 'custom')
              TextButton(
                onPressed: chooseDate,
                child: Text(expiry?.toString() ?? '选择解除日期和时间'),
              ),
            DropdownButtonFormField<String>(
              decoration: const InputDecoration(labelText: '常用原因'),
              items: const [
                '违反社区规则',
                '重复发布或骚扰',
                '异常上传或滥用资源',
                '账号安全风险',
                '其他',
              ].map((r) => DropdownMenuItem(value: r, child: Text(r))).toList(),
              onChanged: (v) {
                if (v != null) reason.text = v == '其他' ? '' : v;
              },
            ),
            TextField(
              controller: reason,
              maxLength: 1000,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(labelText: '原因'),
            ),
          ],
        ),
      ),
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('取消'),
      ),
      FilledButton(
        onPressed: widget.freeze && duration == 'custom' && expiry == null
            ? null
            : () => Navigator.pop(context, <String, dynamic>{
                'duration': duration,
                'reason': reason.text.trim(),
                if (duration == 'custom')
                  'expires_at': expiry?.toUtc().toIso8601String(),
              }),
        child: const Text('确认'),
      ),
    ],
  );
}
