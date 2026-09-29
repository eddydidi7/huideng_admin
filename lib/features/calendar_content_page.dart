import 'package:flutter/material.dart';
import '../data/admin_api.dart';
import '../domain/calendar_traditions.dart';
import '../domain/chinese_calendar_events.dart';
import 'calendar_observances_admin_page.dart';

class CalendarContentPage extends StatefulWidget {
  const CalendarContentPage({super.key, required this.api});
  final AdminApi api;
  @override
  State<CalendarContentPage> createState() => _CalendarContentPageState();
}

class _CalendarContentPageState extends State<CalendarContentPage> {
  Map<String, dynamic>? item;
  final fields = <String, TextEditingController>{};
  Map<String, dynamic> chineseEvents = {};
  bool busy = true;
  String? error;
  static const labels = {
    'heading': '栏目标题',
    'tableTitle': '展开对照表标题',
    'haircutLabel': '理发标签',
    'washingLabel': '洗头标签',
    'annual': '年度理发说明',
    'infant': '婴儿说明',
    'tableAnnual': '对照表下方年度说明',
    'handling': '理发附注与咒语',
    'source': '资料来源',
    'caution': '特殊日期提醒',
    'specialPurify': '十月、十一月初八说明',
    'specialWisdom': '十二月二十五日说明',
  };
  @override
  void initState() {
    super.initState();
    load();
  }

  @override
  void dispose() {
    for (final c in fields.values) {
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
      final config = CalendarTraditions(item!['calendar_traditions']);
      chineseEvents = ChineseCalendarEvents(config.data['chinese_events']).data;
      void put(String key, String value) {
        (fields[key] ??= TextEditingController()).text = value;
      }

      for (final lang in ['zh', 'en']) {
        for (final key in labels.keys) {
          put('texts.$key.$lang', config.text(key, lang == 'en'));
        }
        for (var d = 1; d <= 30; d++) {
          for (final kind in ['haircut', 'washing']) {
            put('$d.$kind.$lang', config.day(d, kind, lang == 'en'));
          }
        }
      }
    } catch (e) {
      if (mounted) error = '$e';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> save() async {
    final config = CalendarTraditions(item!['calendar_traditions']).data;
    config['chinese_events'] = chineseEvents;
    for (final lang in ['zh', 'en']) {
      for (final key in labels.keys) {
        config['texts'][key][lang] = fields['texts.$key.$lang']!.text;
      }
      for (var d = 1; d <= 30; d++) {
        for (final kind in ['haircut', 'washing']) {
          config['days'][d - 1][kind][lang] = fields['$d.$kind.$lang']!.text;
        }
      }
    }
    if (!CalendarTraditions.valid(config)) {
      setState(() => error = '每个输入框最多10000个字符。');
      return;
    }
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await widget.api.call('links.save', {
        'version': item!['version'],
        'calendar_url': item!['calendar_url'],
        'forum_url': item!['forum_url'],
        'calendar_traditions': config,
      });
      await load();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('已发布。手机联网刷新后更新，离线保留上次内容。')),
        );
      }
    } catch (e) {
      if (mounted) error = '$e\n若版本冲突，请先备份本次编辑内容，再重新加载。';
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> editChineseEvent([String? dateKey]) async {
    if (dateKey == null) {
      final date = await showDatePicker(
        context: context,
        initialDate: DateTime.now(),
        firstDate: DateTime(2025),
        lastDate: DateTime(2100, 12, 31),
      );
      if (date == null || !mounted) return;
      dateKey = date.toIso8601String().substring(0, 10);
    }
    final key = dateKey;
    final zh = TextEditingController(
      text: chineseEvents[key]?['zh'] as String? ?? '',
    );
    final en = TextEditingController(
      text: chineseEvents[key]?['en'] as String? ?? '',
    );
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$key 农历下方介绍'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('填写节日、节气或当日说明。清空可隐藏该日介绍；放假、调休安排需按当年正式公告填写。'),
              TextField(
                controller: zh,
                maxLength: 2000,
                maxLines: 4,
                decoration: const InputDecoration(labelText: '中文'),
              ),
              TextField(
                controller: en,
                maxLength: 2000,
                maxLines: 4,
                decoration: const InputDecoration(labelText: 'English'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('确定'),
          ),
        ],
      ),
    );
    if (accepted == true && mounted) {
      setState(
        () => chineseEvents[key] = {'zh': zh.text.trim(), 'en': en.text.trim()},
      );
    }
    await Future<void>.delayed(const Duration(milliseconds: 300));
    zh.dispose();
    en.dispose();
  }

  Widget pair(String key, String label) => Column(
    children: [
      for (final lang in ['zh', 'en'])
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: TextField(
            controller: fields['$key.$lang'],
            enabled: !busy,
            minLines: 1,
            maxLines: 5,
            decoration: InputDecoration(
              labelText: '$label（${lang == 'zh' ? '中文' : 'English'}）',
              border: const OutlineInputBorder(),
            ),
          ),
        ),
    ],
  );
  @override
  Widget build(BuildContext context) => Column(
    children: [
      Wrap(
        spacing: 16,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Text('藏历内容管理', style: Theme.of(context).textTheme.headlineSmall),
          OutlinedButton(
            onPressed: busy
                ? null
                : () async {
                    await Navigator.push<void>(
                      context,
                      MaterialPageRoute(
                        builder: (_) =>
                            CalendarObservancesAdminPage(api: widget.api),
                      ),
                    );
                    if (mounted) await load();
                  },
            child: const Text('管理殊胜日'),
          ),
          FilledButton(
            onPressed: busy || item == null ? null : save,
            child: const Text('保存并发布'),
          ),
          TextButton(onPressed: busy ? null : load, child: const Text('重新加载')),
        ],
      ),
      const Text('可编辑30天对照表、展开标题、全部说明与资料来源。日期计算保持原有规则。'),
      if (busy) const LinearProgressIndicator(),
      if (error != null)
        SelectableText(
          error!,
          style: TextStyle(color: Theme.of(context).colorScheme.error),
        ),
      if (fields.isNotEmpty)
        Expanded(
          child: ListView(
            children: [
              ExpansionTile(
                title: const Text('农历下方：节日、节气与当天介绍'),
                children: [
                  TextButton.icon(
                    onPressed: busy ? null : () => editChineseEvent(),
                    icon: const Icon(Icons.add),
                    label: const Text('选择日期添加'),
                  ),
                  for (final date in chineseEvents.keys.toList()..sort())
                    ListTile(
                      title: Text(date),
                      subtitle: Text(
                        chineseEvents[date]['zh'].toString().isEmpty
                            ? '不显示'
                            : chineseEvents[date]['zh'],
                      ),
                      trailing: const Icon(Icons.edit_outlined),
                      onTap: busy ? null : () => editChineseEvent(date),
                    ),
                ],
              ),
              for (final entry in labels.entries)
                pair('texts.${entry.key}', entry.value),
              for (var d = 1; d <= 30; d++)
                ExpansionTile(
                  title: Text('藏历每月第$d日'),
                  children: [
                    pair('$d.haircut', '理发'),
                    pair('$d.washing', '洗头'),
                  ],
                ),
            ],
          ),
        ),
    ],
  );
}
