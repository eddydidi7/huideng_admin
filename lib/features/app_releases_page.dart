import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:file_picker/file_picker.dart';
import '../services/apk_metadata.dart';
import '../services/release_apk_uploader.dart';
import '../services/release_url_check.dart';
import '../data/admin_api.dart';

class AppReleasesPage extends StatefulWidget {
  final AdminApi api;
  const AppReleasesPage({
    super.key,
    required this.api,
    this.pickApk,
    this.uploadApk,
  });
  final Future<ApkMetadata?> Function()? pickApk;
  final Future<String> Function(ApkMetadata, ValueChanged<double>)? uploadApk;
  @override
  State<AppReleasesPage> createState() => _AppReleasesPageState();
}

class _AppReleasesPageState extends State<AppReleasesPage> {
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
      final data = await widget.api.call('releases.list');
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

  Future<void> edit([Map<String, dynamic>? row]) async {
    final labels = {
      'version_code': 'versionCode',
      'version_name': 'versionName',
      'download_url': 'HTTPS APK 下载地址',
      'release_notes': '更新说明',
      'apk_size': 'APK 字节数',
      'sha256': 'SHA-256',
      'published_at': '发布时间（ISO 8601）',
      'minimum_version_code': '最低允许 versionCode（0 为不限制）',
    };
    final fields = {
      for (final k in labels.keys)
        k: TextEditingController(
          text:
              row?[k]?.toString() ??
              (k == 'minimum_version_code'
                  ? '0'
                  : k == 'published_at'
                  ? DateTime.now().toUtc().toIso8601String()
                  : ''),
        ),
    };
    bool published = row?['is_published'] == true,
        force = row?['force_update'] == true,
        saving = false;
    String platform = row?['platform'] as String? ?? 'android';
    String? failure;
    final policies = <String, bool>{
      'updates_enabled': row?['updates_enabled'] != false,
      'prompt_enabled': row?['prompt_enabled'] != false,
      'startup_check': row?['startup_check'] != false,
      'auto_download': row?['auto_download'] == true,
      'wifi_only': row?['wifi_only'] != false,
    };
    ApkMetadata? selected;
    String phase = '';
    double? progress;
    final dialog = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialog) => PopScope(
          canPop: !saving,
          child: AlertDialog(
            title: const Text('App 版本'),
            content: SizedBox(
              width: 620,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (row == null)
                      FilledButton.icon(
                        icon: const Icon(Icons.upload_file),
                        label: Text(
                          selected == null ? '选择 APK 并自动填写' : '重试上传所选 APK',
                        ),
                        onPressed: saving
                            ? null
                            : () async {
                                setDialog(() {
                                  saving = true;
                                  failure = null;
                                  phase = '读取 APK 并计算 SHA-256…';
                                  progress = null;
                                });
                                try {
                                  if (selected == null) {
                                    if (widget.pickApk != null) {
                                      selected = await widget.pickApk!();
                                    } else {
                                      final picked = await FilePicker.platform
                                          .pickFiles(
                                            type: FileType.custom,
                                            allowedExtensions: ['apk'],
                                            withData: false,
                                          );
                                      final path = picked?.files.single.path;
                                      if (path != null) {
                                        selected = await compute(
                                          inspectApk,
                                          path,
                                        );
                                      }
                                    }
                                    if (selected == null) return;
                                  }
                                  final apk = selected!;
                                  if (apk.packageName !=
                                      'org.huideng.huideng_counter') {
                                    selected = null;
                                    throw const FormatException(
                                      '这个 APK 不是文殊计数器，请重新选择',
                                    );
                                  }
                                  setDialog(() {
                                    fields['version_code']!.text =
                                        '${apk.versionCode}';
                                    fields['version_name']!.text =
                                        apk.versionName;
                                    fields['apk_size']!.text = '${apk.size}';
                                    fields['sha256']!.text = apk.hash;
                                    fields['download_url']!.clear();
                                    published = false;
                                    force = false;
                                    phase = '上传及服务器校验（完成后进入公共网盘）';
                                    progress = 0;
                                  });
                                  final api = widget.api;
                                  final uploader =
                                      widget.uploadApk ??
                                      (api is SupabaseAdminApi
                                          ? ReleaseApkUploader(
                                              api.client,
                                              const String.fromEnvironment(
                                                'ADMIN_SUPABASE_URL',
                                              ),
                                            ).upload
                                          : null);
                                  if (uploader == null) {
                                    throw StateError('当前连接不支持 APK 上传');
                                  }
                                  final url = await uploader(apk, (value) {
                                    if (ctx.mounted) {
                                      setDialog(() => progress = value);
                                    }
                                  });
                                  if (!ctx.mounted) return;
                                  setDialog(() {
                                    fields['download_url']!.text = url;
                                    phase = '已自动填写。请填写更新说明，核对后保存。';
                                  });
                                } catch (e) {
                                  if (ctx.mounted) {
                                    setDialog(
                                      () => failure = e is FormatException
                                          ? e.message
                                          : e.toString(),
                                    );
                                  }
                                } finally {
                                  if (ctx.mounted) {
                                    setDialog(() => saving = false);
                                  }
                                }
                              },
                      ),
                    if (selected != null)
                      Text(
                        '${selected!.packageName} · ${(selected!.size / 1048576).toStringAsFixed(1)} MiB',
                      ),
                    if (row == null && selected != null)
                      TextButton(
                        onPressed: saving
                            ? null
                            : () => setDialog(() {
                                selected = null;
                                phase = '';
                              }),
                        child: const Text('选择其他 APK'),
                      ),
                    if (phase.isNotEmpty) Text(phase),
                    if (saving) LinearProgressIndicator(value: progress),
                    const Text('选择后会上传到公共网盘；版本记录仍需点击保存。测试签名包不要开启正式发布。'),
                    DropdownButtonFormField<String>(
                      initialValue: platform,
                      decoration: const InputDecoration(labelText: '平台'),
                      items: const [
                        DropdownMenuItem(value: 'android', child: Text('Android')),
                        DropdownMenuItem(value: 'windows', child: Text('Windows')),
                        DropdownMenuItem(value: 'ios', child: Text('iOS')),
                      ],
                      // versionCode is a single global sequence shared by every
                      // platform (see 202609290077_app_releases_platform.sql):
                      // switching platform after a versionCode has been saved
                      // would silently retarget which devices see this row.
                      onChanged: saving || row != null
                          ? null
                          : (v) => setDialog(() => platform = v ?? platform),
                    ),
                    const SizedBox(height: 10),
                    for (final e in fields.entries)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: TextField(
                          controller: e.value,
                          readOnly:
                              selected != null &&
                              [
                                'version_code',
                                'version_name',
                                'apk_size',
                                'sha256',
                                'download_url',
                              ].contains(e.key),
                          enabled:
                              !saving &&
                              !(e.key == 'version_code' && row != null),
                          maxLines: e.key == 'release_notes' ? 5 : 1,
                          decoration: InputDecoration(labelText: labels[e.key]),
                        ),
                      ),
                    SwitchListTile(
                      title: const Text('正式发布（测试版请关闭）'),
                      value: published,
                      onChanged: saving
                          ? null
                          : (v) => setDialog(() => published = v),
                    ),
                    SwitchListTile(
                      title: const Text('强制更新（默认关闭）'),
                      value: force,
                      onChanged: saving
                          ? null
                          : (v) => setDialog(() => force = v),
                    ),
                    if (failure != null) Text(failure!),
                    for (final entry in {
                      'updates_enabled': '开启版本检测',
                      'prompt_enabled': '开启更新提示',
                      'startup_check': '启动时检查更新',
                      'auto_download': '允许自动下载',
                      'wifi_only': '自动下载仅允许 Wi-Fi',
                    }.entries)
                      SwitchListTile(
                        title: Text(entry.value),
                        value: policies[entry.key]!,
                        onChanged: saving
                            ? null
                            : (v) => setDialog(() => policies[entry.key] = v),
                      ),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: saving ? null : () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: saving
                    ? null
                    : () async {
                        setDialog(() => saving = true);
                        try {
                          final uri = Uri.tryParse(
                            fields['download_url']!.text.trim(),
                          );
                          if (uri == null ||
                              uri.scheme != 'https' ||
                              uri.host.isEmpty ||
                              RegExp(
                                r'^/f/[a-f0-9]{64}/?$',
                              ).hasMatch(uri.path)) {
                            throw const FormatException(
                              '请使用 APK 直接下载地址，不能填写分享网页',
                            );
                          }
                          final data = <String, dynamic>{
                            for (final e in fields.entries)
                              e.key: e.value.text.trim(),
                            'platform': platform,
                            'version_code': int.parse(
                              fields['version_code']!.text,
                            ),
                            'apk_size': int.parse(fields['apk_size']!.text),
                            'is_published': published,
                            'force_update': force,
                            ...policies,
                            'minimum_version_code': int.parse(
                              fields['minimum_version_code']!.text,
                            ),
                            'expected_updated_at': row?['updated_at'],
                          };
                          if (published) {
                            await checkReleaseUrl(
                              data['download_url'] as String,
                              data['apk_size'] as int,
                            );
                          }
                          final result = await widget.api.call(
                            'releases.save',
                            data,
                          );
                          if (!result.containsKey('minimum_version_code')) {
                            throw StateError(
                              '版本已保存，但服务端尚未支持更新策略；请部署 084 迁移后重新保存。',
                            );
                          }
                          if (ctx.mounted) Navigator.pop(ctx);
                        } catch (e) {
                          setDialog(() {
                            failure = e.toString();
                            saving = false;
                          });
                        }
                      },
                child: Text(published ? '发布更新' : '保存草稿'),
              ),
            ],
          ),
        ),
      ),
    );
    await Navigator.of(context).push(dialog);
    await dialog.completed;
    for (final c in fields.values) {
      c.dispose();
    }
    if (mounted) await load();
  }

  Future<void> notify(Map<String, dynamic> row) async {
    setState(() => busy = true);
    try {
      await widget.api.call('releases.notify', {
        'version_code': row['version_code'],
      });
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    padding: const EdgeInsets.all(16),
    children: [
      Wrap(
        spacing: 12,
        children: [
          FilledButton(
            onPressed: busy ? null : () => edit(),
            child: const Text('新增版本'),
          ),
          TextButton(onPressed: busy ? null : load, child: const Text('刷新')),
        ],
      ),
      const Text('先上传正式签名 APK，再填写其真实下载地址、字节数和 SHA-256。保存与发送通知是两个独立操作。'),
      if (busy) const LinearProgressIndicator(),
      if (error != null) Text(error!),
      for (final row in rows)
        Card(
          child: ListTile(
            title: Text(
              '[${(row['platform'] as String? ?? 'android').toUpperCase()}] '
              '${row['version_name']} (${row['version_code']})',
            ),
            subtitle: Text(
              '${row['is_published'] == true ? '正式发布' : '未发布'} · ${row['notified_at'] == null ? '未通知' : '已通知'}\n${row['release_notes']}',
            ),
            onTap: busy ? null : () => edit(row),
            trailing: TextButton(
              onPressed:
                  busy ||
                      row['is_published'] != true ||
                      row['notified_at'] != null
                  ? null
                  : () => notify(row),
              child: const Text('发送更新通知'),
            ),
          ),
        ),
    ],
  );
}
