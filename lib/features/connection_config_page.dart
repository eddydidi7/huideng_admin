import 'dart:convert';
import 'dart:typed_data';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import '../data/admin_api.dart';

class ConnectionConfigPage extends StatefulWidget {
  const ConnectionConfigPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<ConnectionConfigPage> createState() => _ConnectionConfigPageState();
}

class _ConnectionConfigPageState extends State<ConnectionConfigPage> {
  final origins = TextEditingController(),
      days = TextEditingController(text: '90');
  Map<String, dynamic>? envelope;
  int version = 0;
  bool busy = false, ready = false, loaded = false;
  String? error;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    origins.dispose();
    days.dispose();
    super.dispose();
  }

  Future<void> load() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.call('connection.get');
      if (!mounted) return;
      version = data['version'] as int;
      ready = data['signing_ready'] == true;
      loaded = true;
      envelope = data['envelope'] == null
          ? null
          : Map<String, dynamic>.from(data['envelope']);
      if (envelope != null) {
        final value =
            jsonDecode(
                  utf8.decode(base64Decode(envelope!['payload'] as String)),
                )
                as Map;
        origins.text = (value['origins'] as List).join('\n');
      }
    } catch (e) {
      if (mounted) error = '连接配置尚未启用或读取失败：$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> publish() async {
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final data = await widget.api.call('connection.publish', {
        'version': version,
        'days': int.tryParse(days.text),
        'origins': origins.text
            .split('\n')
            .map((s) => s.trim())
            .where((s) => s.isNotEmpty)
            .toList(),
      });
      if (!mounted) return;
      envelope = Map<String, dynamic>.from(data['envelope']);
      version = data['version'] as int;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('签名已生成。请导出并更新所有独立配置入口，手机才能收到。')),
      );
    } catch (e) {
      if (mounted) error = '$e\n如版本冲突，请重新加载核对后再保存。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> export() async {
    try {
      await FilePicker.platform.saveFile(
        fileName: 'connection-config.json',
        type: FileType.custom,
        allowedExtensions: ['json'],
        bytes: Uint8List.fromList(utf8.encode(jsonEncode(envelope))),
      );
    } catch (e) {
      if (mounted) setState(() => error = '导出失败：$e');
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text('备用连接配置', style: Theme.of(context).textTheme.headlineSmall),
      const Text('准备阶段：需先配置实际域名、同项目网关、独立配置入口和签名密钥。这里不创建服务器，也不迁移账号或数据。'),
      if (busy) const LinearProgressIndicator(),
      if (error != null) SelectableText(error!),
      if (!ready) const Text('尚未配置服务端签名密钥，当前不会启用远程切换。'),
      TextField(
        controller: origins,
        enabled: !busy,
        minLines: 4,
        maxLines: 6,
        decoration: const InputDecoration(
          labelText: 'HTTPS主、备用域名（每行一个，最多4个）',
          helperText:
              '全部必须连接原Supabase项目，支持Auth / REST / Functions / Storage / WebSocket。',
        ),
      ),
      TextField(
        controller: days,
        enabled: !busy,
        keyboardType: TextInputType.number,
        decoration: const InputDecoration(labelText: '有效天数（1～180）'),
      ),
      const Text('配置到期后手机回到内置地址，请提前续签并更新镜像。修改域名可能短暂重连。'),
      Wrap(
        spacing: 12,
        children: [
          FilledButton(
            onPressed: busy || !ready || !loaded ? null : publish,
            child: const Text('生成签名配置'),
          ),
          TextButton(
            onPressed: busy || envelope == null ? null : export,
            child: const Text('导出供独立入口发布'),
          ),
          TextButton(onPressed: busy ? null : load, child: const Text('重新加载')),
        ],
      ),
      Text('当前配置版本：$version'),
    ],
  );
}
