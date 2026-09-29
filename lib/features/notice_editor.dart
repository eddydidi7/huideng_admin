import 'package:flutter/material.dart';
import '../data/admin_api.dart';

class NoticeEditor extends StatefulWidget {
  final AdminApi api;
  final Map<String, dynamic>? item;
  const NoticeEditor({super.key, required this.api, this.item});
  @override
  State<NoticeEditor> createState() => _NoticeEditorState();
}

class _NoticeEditorState extends State<NoticeEditor> {
  final form = GlobalKey<FormState>();
  late final title = TextEditingController(
    text: widget.item?['title_zh'] ?? '',
  );
  late final body = TextEditingController(text: widget.item?['body_zh'] ?? '');
  late final englishTitle = TextEditingController(
    text: widget.item?['title_en'] ?? '',
  );
  late final englishBody = TextEditingController(
    text: widget.item?['body_en'] ?? '',
  );
  late String type = widget.item?['notice_type'] ?? 'system';
  late bool pinned = widget.item?['is_pinned'] == true;
  late String mode = widget.item?['scheduled_at'] != null
      ? 'scheduled'
      : widget.item?['is_published'] == true
      ? 'now'
      : 'draft';
  late DateTime? scheduled = DateTime.tryParse(
    widget.item?['scheduled_at'] ?? '',
  )?.toLocal();
  bool saving = false;
  String? error;
  @override
  void dispose() {
    title.dispose();
    body.dispose();
    englishTitle.dispose();
    englishBody.dispose();
    super.dispose();
  }

  Future<void> pick() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: scheduled != null && scheduled!.isAfter(now)
          ? scheduled!
          : now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(
        scheduled ?? now.add(const Duration(hours: 1)),
      ),
    );
    if (time != null && mounted) {
      setState(
        () => scheduled = DateTime(
          date.year,
          date.month,
          date.day,
          time.hour,
          time.minute,
        ),
      );
    }
  }

  Future<void> save() async {
    if (!form.currentState!.validate()) return;
    if (mode == 'scheduled' &&
        (scheduled == null || !scheduled!.isAfter(DateTime.now()))) {
      setState(() => error = '请选择未来的发布时间。');
      return;
    }
    setState(() {
      saving = true;
      error = null;
    });
    try {
      await widget.api.call('notices.save', {
        if (widget.item != null) 'id': widget.item!['id'],
        if (widget.item != null) 'version': widget.item!['version'],
        'title_zh': title.text.trim(),
        'body_zh': body.text.trim(),
        'title_en': englishTitle.text.trim(),
        'body_en': englishBody.text.trim(),
        'notice_type': type,
        'is_pinned': pinned,
        'mode': mode,
        'scheduled_at': mode == 'scheduled'
            ? scheduled!.toUtc().toIso8601String()
            : null,
      });
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: !saving,
    child: Scaffold(
      appBar: AppBar(title: Text(widget.item == null ? '新建通知' : '编辑通知')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 850),
          child: Form(
            key: form,
            child: ListView(
              padding: const EdgeInsets.all(28),
              children: [
                TextFormField(
                  controller: title,
                  enabled: !saving,
                  maxLength: 200,
                  decoration: const InputDecoration(labelText: '标题'),
                  validator: (v) =>
                      v == null || v.trim().isEmpty ? '请填写标题' : null,
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: body,
                  enabled: !saving,
                  maxLength: 20000,
                  minLines: 6,
                  maxLines: 14,
                  decoration: const InputDecoration(labelText: '通知内容'),
                  validator: (v) =>
                      mode != 'draft' && (v == null || v.trim().isEmpty)
                      ? '请填写通知内容'
                      : null,
                ),
                ExpansionTile(
                  title: const Text('英文内容（可选，留空时显示中文）'),
                  children: [
                    TextFormField(
                      controller: englishTitle,
                      maxLength: 400,
                      enabled: !saving,
                      decoration: const InputDecoration(labelText: '英文标题'),
                    ),
                    TextFormField(
                      controller: englishBody,
                      maxLength: 40000,
                      enabled: !saving,
                      minLines: 3,
                      maxLines: 8,
                      decoration: const InputDecoration(labelText: '英文内容'),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                DropdownButtonFormField<String>(
                  initialValue: type,
                  decoration: const InputDecoration(labelText: '通知类型'),
                  items: const [
                    DropdownMenuItem(value: 'system', child: Text('系统通知')),
                    DropdownMenuItem(value: 'practice', child: Text('共修通知')),
                    DropdownMenuItem(value: 'article', child: Text('文章通知')),
                    DropdownMenuItem(value: 'admin', child: Text('管理员通知')),
                  ],
                  onChanged: saving ? null : (v) => setState(() => type = v!),
                ),
                SwitchListTile(
                  title: const Text('是否置顶'),
                  value: pinned,
                  onChanged: saving ? null : (v) => setState(() => pinned = v),
                ),
                DropdownButtonFormField<String>(
                  initialValue: mode,
                  decoration: const InputDecoration(labelText: '发布时间'),
                  items: const [
                    DropdownMenuItem(value: 'draft', child: Text('保存草稿')),
                    DropdownMenuItem(value: 'now', child: Text('立即发布')),
                    DropdownMenuItem(value: 'scheduled', child: Text('定时发布')),
                  ],
                  onChanged: saving ? null : (v) => setState(() => mode = v!),
                ),
                if (mode == 'scheduled')
                  ListTile(
                    title: Text(
                      scheduled == null
                          ? '选择发布时间（本机时区）'
                          : '${scheduled.toString().split('.').first}（本机时区）',
                    ),
                    trailing: const Icon(Icons.schedule),
                    onTap: saving ? null : pick,
                  ),
                const SizedBox(height: 24),
                if (error != null)
                  Text(error!, style: const TextStyle(color: Colors.red)),
                FilledButton(
                  onPressed: saving ? null : save,
                  child: Text(
                    saving
                        ? '正在保存…'
                        : mode == 'draft'
                        ? '保存草稿'
                        : mode == 'scheduled'
                        ? '保存定时发布'
                        : '发布',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    ),
  );
}
