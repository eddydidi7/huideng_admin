import 'dart:convert';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';
import '../data/admin_api.dart';

class PublicContentPage extends StatefulWidget {
  final AdminApi api;
  final bool notes;
  const PublicContentPage({super.key, required this.api, required this.notes});
  @override
  State<PublicContentPage> createState() => _PublicContentPageState();
}

class _PublicContentPageState extends State<PublicContentPage> {
  Map<String, dynamic>? item;
  String? error;
  bool busy = false;
  final email = TextEditingController(),
      qq = TextEditingController(),
      zh = TextEditingController(),
      en = TextEditingController(),
      images = TextEditingController();
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in [email, qq, zh, en, images]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final result = await widget.api.call('links.get');
      if (!mounted) return;
      item = Map<String, dynamic>.from(result['item']);
      final about = item!['about_content'] as Map? ?? {};
      email.text = about['email'] as String? ?? 'eddydid@gmail.com';
      qq.text = about['qq'] as String? ?? '79576743';
      zh.text = about['text_zh'] as String? ?? '';
      en.text = about['text_en'] as String? ?? '';
      images.text = (about['images'] as List? ?? []).join('\n');
    } catch (e) {
      if (mounted) error = e.toString();
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save(Map<String, dynamic> changes) async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.call('links.save', {
        'version': item!['version'],
        'calendar_url': item!['calendar_url'],
        'forum_url': item!['forum_url'],
        ...changes,
      });
      await load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已发布，用户端联网刷新后可查看。')));
      }
    } catch (e) {
      if (mounted) setState(() => error = '$e\n如其他管理员已修改，请刷新后重试。');
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  List<Map<String, dynamic>> get notes =>
      (item?['published_notes'] as List? ?? [])
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
  Future<void> edit([Map<String, dynamic>? note]) async {
    final input = TextEditingController(text: note?['body'] as String? ?? '');
    final text = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(note == null ? '发布笔记给所有用户' : '编辑已发布笔记'),
        content: SizedBox(
          width: 650,
          child: TextField(
            controller: input,
            minLines: 8,
            maxLines: 16,
            maxLength: 10000,
            decoration: const InputDecoration(
              labelText: '正文',
              helperText: '发布后所有用户可查看，不会更改个人笔记。',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () {
              if (input.text.trim().isNotEmpty) {
                Navigator.pop(context, input.text.trim());
              }
            },
            child: const Text('发布'),
          ),
        ],
      ),
    );
    await Future<void>.delayed(const Duration(milliseconds: 300));
    input.dispose();
    if (text == null || !mounted) return;
    final now = DateTime.now().toUtc().toIso8601String();
    final next = notes;
    final record = {
      ...?note,
      'id': note?['id'] ?? const Uuid().v4(),
      'body': text,
      'created_at': note?['created_at'] ?? now,
      'updated_at': now,
    };
    next.removeWhere((n) => n['id'] == record['id']);
    next.insert(0, record);
    await save({'published_notes': next});
  }

  Future<void> remove(Map<String, dynamic> note) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('撤下这篇公开笔记？'),
        content: const Text('用户端下次联网刷新后不再显示。个人笔记不受影响。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('撤下'),
          ),
        ],
      ),
    );
    if (yes == true && mounted) {
      await save({
        'published_notes': notes.where((n) => n['id'] != note['id']).toList(),
      });
    }
  }

  Future<void> uploadImage() async {
    if (images.text.split('\n').where((e) => e.trim().isNotEmpty).length >= 8) {
      setState(() => error = '最多添加 8 张图片。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'webp'],
        withData: true,
      );
      if (picked == null) return;
      final file = picked.files.single;
      if (file.size > 2097152 || file.bytes == null) {
        throw const AdminFailure('请选择 2 MB 以内的图片。');
      }
      final result = await widget.api.call('assets.upload', {
        'base64': base64Encode(file.bytes!),
      });
      if (mounted) {
        setState(
          () => images.text = [
            images.text.trim(),
            result['url'] as String,
          ].where((s) => s.isNotEmpty).join('\n'),
        );
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> saveAbout() async {
    final urls = images.text
        .split('\n')
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
    if (urls.length > 8 ||
        urls.any((e) {
          final u = Uri.tryParse(e);
          return u == null ||
              u.scheme != 'https' ||
              u.host.isEmpty ||
              u.userInfo.isNotEmpty ||
              e.length > 2048 ||
              RegExp(r'\s').hasMatch(e);
        })) {
      setState(() => error = '图片最多 8 张，请每行填写一个完整 HTTPS 图片地址。');
      return;
    }
    await save({
      'about_content': {
        'email': email.text.trim(),
        'qq': qq.text.trim(),
        'text_zh': zh.text,
        'text_en': en.text,
        'images': urls,
      },
    });
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text(
        widget.notes ? '后台发布笔记' : '关于与联系',
        style: Theme.of(context).textTheme.headlineMedium,
      ),
      if (busy) const LinearProgressIndicator(),
      if (error != null) SelectableText(error!),
      TextButton(onPressed: busy ? null : load, child: const Text('刷新')),
      if (item != null && widget.notes) ...[
        const Text('公开栏目，最多 100 篇。与用户个人笔记分开保存。'),
        FilledButton(
          onPressed: busy || notes.length >= 100 ? null : () => edit(),
          child: const Text('新建公开笔记'),
        ),
        for (final note in notes)
          Card(
            child: ListTile(
              title: Text(
                note['body'] as String,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
              trailing: Wrap(
                children: [
                  TextButton(
                    onPressed: busy ? null : () => edit(note),
                    child: const Text('编辑'),
                  ),
                  TextButton(
                    onPressed: busy ? null : () => remove(note),
                    child: const Text('撤下'),
                  ),
                ],
              ),
            ),
          ),
      ],
      if (item != null && !widget.notes) ...[
        OutlinedButton.icon(
          onPressed: busy ? null : uploadImage,
          icon: const Icon(Icons.image_outlined),
          label: const Text('从电脑添加公开图片（2 MB 以内）'),
        ),
        const Text('图片上传后可公开访问；点击保存并发布后显示在 App。'),
        for (final field in [
          (email, '联系邮箱', 254),
          (qq, 'QQ', 40),
          (zh, '中文介绍', 20000),
          (en, '英文介绍', 20000),
          (images, '图片地址（每行一张，最多 8 张）', 16400),
        ])
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 10),
            child: TextField(
              controller: field.$1,
              enabled: !busy,
              maxLength: field.$3,
              minLines: field.$1 == email || field.$1 == qq ? 1 : 3,
              maxLines: 8,
              decoration: InputDecoration(labelText: field.$2),
            ),
          ),
        const Text('图片需使用可公开访问的 HTTPS 图片地址。保存后文字、联系方式和图片一起发布给所有用户。'),
        FilledButton(
          onPressed: busy ? null : saveAbout,
          child: const Text('保存并发布'),
        ),
      ],
    ],
  );
}
