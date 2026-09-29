import 'package:flutter/material.dart';
import '../data/admin_api.dart';
import '../domain/calendar_observance_config.dart';
import '../domain/calendar_traditions.dart';

class CalendarObservancesAdminPage extends StatefulWidget {
  const CalendarObservancesAdminPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<CalendarObservancesAdminPage> createState() =>
      _CalendarObservancesAdminPageState();
}

class _CalendarObservancesAdminPageState
    extends State<CalendarObservancesAdminPage> {
  Map<String, dynamic>? item, config;
  bool busy = false;
  String? error;
  final texts = {
    for (final k in ['title_zh', 'title_en', 'note_zh', 'note_en'])
      k: TextEditingController(),
  };
  List get entries => config!['entries'] as List;
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in texts.values) {
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
      final r = await widget.api.call('links.get');
      if (!mounted) return;
      item = Map<String, dynamic>.from(r['item']);
      config = CalendarObservanceConfig(
        (item!['calendar_traditions'] as Map?)?['observances'],
      ).data;
      for (final k in texts.keys) {
        texts[k]!.text = config![k];
      }
    } catch (e) {
      if (mounted) error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    for (final k in texts.keys) {
      config![k] = texts[k]!.text;
    }
    if (!CalendarObservanceConfig.valid(config)) {
      setState(() => error = '内容不符合格式或超过500项，请检查。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      final traditions = CalendarTraditions(item!['calendar_traditions']).data;
      traditions['observances'] = config;
      await widget.api.call('links.save', {
        'version': item!['version'],
        'calendar_url': item!['calendar_url'],
        'forum_url': item!['forum_url'],
        'calendar_traditions': traditions,
      });
      await load();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('已发布，手机联网刷新后生效。')));
      }
    } catch (e) {
      if (mounted) error = '$e\n编辑内容仍保留；版本冲突时请备份编辑内容再重新加载。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> edit([int? index]) async {
    final e = index == null
        ? <String, dynamic>{
            'id': 'custom_${DateTime.now().microsecondsSinceEpoch}',
            'month': 0,
            'day': 1,
            'end_day': 1,
            'zh': '',
            'en': '',
            'source': '',
            'url': '',
            'enabled': true,
            'include_leap': true,
            'repeat': 'both',
          }
        : Map<String, dynamic>.from(entries[index]);
    final fields = {
      for (final k in ['month', 'day', 'end_day', 'zh', 'en', 'source', 'url'])
        k: TextEditingController(text: '${e[k]}'),
    };
    String? problem;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, change) => AlertDialog(
          title: Text(index == null ? '新增殊胜日' : '编辑殊胜日'),
          content: SizedBox(
            width: 520,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final pair in const {
                    'month': '藏历月份（0表示每月，1–12表示年度）',
                    'day': '开始日（1–30）',
                    'end_day': '结束日（单日填写同一天）',
                    'zh': '中文名称',
                    'en': '英文名称',
                    'source': '资料来源名称',
                    'url': '来源链接（可留空，须HTTPS）',
                  }.entries)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 5),
                      child: TextField(
                        controller: fields[pair.key],
                        decoration: InputDecoration(labelText: pair.value),
                        maxLines: pair.key == 'zh' || pair.key == 'en' ? 2 : 1,
                      ),
                    ),
                  SwitchListTile(
                    title: const Text('启用'),
                    value: e['enabled'],
                    onChanged: (v) => change(() => e['enabled'] = v),
                  ),
                  SwitchListTile(
                    title: const Text('闰月也显示'),
                    value: e['include_leap'],
                    onChanged: (v) => change(() => e['include_leap'] = v),
                  ),
                  DropdownButtonFormField<String>(
                    initialValue: e['repeat'],
                    decoration: const InputDecoration(labelText: '重日显示规则'),
                    items: const [
                      DropdownMenuItem(value: 'both', child: Text('两天均显示')),
                      DropdownMenuItem(value: 'first', child: Text('只在第一重日显示')),
                      DropdownMenuItem(
                        value: 'second',
                        child: Text('只在第二重日显示'),
                      ),
                    ],
                    onChanged: (v) => change(() => e['repeat'] = v),
                  ),
                  if (problem != null)
                    Text(
                      problem!,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                for (final k in fields.keys) {
                  e[k] = ['month', 'day', 'end_day'].contains(k)
                      ? int.tryParse(fields[k]!.text)
                      : fields[k]!.text.trim();
                }
                final trial = {
                  ...config!,
                  'entries': [e],
                };
                if (!CalendarObservanceConfig.valid(trial)) {
                  change(() => problem = '检查日期、中文名称与HTTPS链接；结束日不能小于开始日。');
                  return;
                }
                Navigator.pop(dialogContext, e);
              },
              child: const Text('保存到草稿'),
            ),
          ],
        ),
      ),
    );
    // Wait for dialog exit animation before releasing its text controllers.
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in fields.values) {
      c.dispose();
    }
    if (result != null && mounted) {
      setState(() {
        if (index == null) {
          entries.add(result);
        } else {
          entries[index] = result;
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('藏历 · 殊胜日管理')),
    body: Column(
      children: [
        Wrap(
          spacing: 12,
          children: [
            FilledButton(
              onPressed: busy || config == null ? null : save,
              child: const Text('保存并发布'),
            ),
            OutlinedButton(
              onPressed: busy || config == null || entries.length >= 500
                  ? null
                  : () => edit(),
              child: const Text('新增殊胜日'),
            ),
            TextButton(
              onPressed: busy ? null : load,
              child: const Text('重新加载'),
            ),
          ],
        ),
        const Padding(
          padding: EdgeInsets.all(8),
          child: Text('编辑后点击保存并发布。停用可撤下条目。月份0表示每月；缺日不自动移节。'),
        ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          SelectableText(
            error!,
            style: TextStyle(color: Theme.of(context).colorScheme.error),
          ),
        if (config != null)
          Expanded(
            child: ListView(
              children: [
                const Padding(
                  padding: EdgeInsets.all(8),
                  child: Text('殊胜月背景（按藏历月份，非闰月）'),
                ),
                Wrap(
                  spacing: 8,
                  children: [
                    for (var m = 1; m <= 12; m++)
                      FilterChip(
                        label: Text('$m月'),
                        selected: CalendarObservanceConfig(
                          config,
                        ).highlightedMonths.contains(m),
                        onSelected: busy
                            ? null
                            : (selected) => setState(() {
                                final months = CalendarObservanceConfig(
                                  config,
                                ).highlightedMonths;
                                if (selected) {
                                  months.add(m);
                                } else {
                                  months.remove(m);
                                }
                                months.sort();
                                config!['highlight_months'] = months;
                              }),
                      ),
                  ],
                ),
                for (final label in const {
                  'title_zh': '栏目标题（中文）',
                  'title_en': '栏目标题（英文）',
                  'note_zh': '说明（中文）',
                  'note_en': '说明（英文）',
                }.entries)
                  Padding(
                    padding: const EdgeInsets.all(8),
                    child: TextField(
                      controller: texts[label.key],
                      enabled: !busy,
                      maxLines: label.key.startsWith('note') ? 4 : 1,
                      decoration: InputDecoration(
                        labelText: label.value,
                        border: const OutlineInputBorder(),
                      ),
                    ),
                  ),
                for (var i = 0; i < entries.length; i++)
                  ListTile(
                    title: Text(entries[i]['zh']),
                    subtitle: Text(
                      '${entries[i]['month'] == 0 ? '每月' : "${entries[i]['month']}月"} ${entries[i]['day']}–${entries[i]['end_day']} · ${entries[i]['enabled'] ? '已启用' : '已停用'}',
                    ),
                    trailing: const Icon(Icons.edit_outlined),
                    onTap: busy ? null : () => edit(i),
                  ),
              ],
            ),
          ),
      ],
    ),
  );
}
