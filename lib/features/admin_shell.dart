import 'resource_usage_page.dart';
import 'app_releases_page.dart';
import 'resource_admin_page.dart';
import 'jieyuan_admin_page.dart';
import 'package:flutter/material.dart';
import '../data/admin_api.dart';
import 'notice_editor.dart';
import 'catalog_page.dart';
import 'members_page.dart';
import 'public_content_page.dart';
import 'calendar_content_page.dart';
import 'chat_admin_page.dart';
import 'connection_config_page.dart';

class AdminShell extends StatefulWidget {
  final AdminApi? api;
  const AdminShell({super.key, required this.api});
  @override
  State<AdminShell> createState() => _AdminShellState();
}

class _AdminShellState extends State<AdminShell> {
  final email = TextEditingController(),
      password = TextEditingController(),
      search = TextEditingController();
  Map<String, dynamic>? member;
  Map<String, dynamic> data = {};
  String section = '首页';
  String? error;
  bool busy = false;
  int offset = 0;
  int generation = 0;
  static const sections = [
    '首页',
    '通知',
    '文章',
    '论坛',
    '用户',
    '藏历',
    '群聊管理',
    '结缘管理',
    '备用连接',
    '数据统计',
    '公共网盘',
    '用户资源用量',
    'App版本',
    '系统设置',
    '后台发布笔记',
    '关于与联系',
  ];
  AdminApi get api => widget.api!;
  String get role => member?['role'] as String? ?? '';
  bool allowed(String name) =>
      role == 'super_admin' ||
      (role == 'admin' &&
          [
            '首页',
            '通知',
            '文章',
            '论坛',
            '用户',
            '结缘管理',
            '公共网盘',
            '用户资源用量',
            'App版本',
          ].contains(name)) ||
      (role == 'moderator' && ['论坛', '结缘管理'].contains(name));
  String get roleName => switch (role) {
    'super_admin' => '超级管理员',
    'admin' => '管理员',
    _ => '版主',
  };
  List<Map<String, dynamic>> get rows => (data['items'] as List? ?? [])
      .map((e) => Map<String, dynamic>.from(e as Map))
      .toList();
  @override
  void dispose() {
    email.dispose();
    password.dispose();
    search.dispose();
    super.dispose();
  }

  Future<void> login() async {
    if (busy || widget.api == null) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await api.signIn(email.text, password.text);
      final me = await api.call('me');
      if (!['super_admin', 'admin', 'moderator'].contains(me['role'])) {
        throw const AdminFailure('此账号没有后台管理权限。');
      }
      if (!mounted) return;
      setState(() {
        member = me;
        section = role == 'moderator' ? '论坛' : '首页';
      });
      password.clear();
      await load();
    } catch (e) {
      if (member == null) {
        try {
          await api.signOut();
        } catch (_) {}
      }
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> load() async {
    final ticket = ++generation;
    final selected = section;
    setState(() {
      busy = true;
      error = null;
      data = {};
    });
    try {
      final value = switch (selected) {
        '首页' => await api.call('dashboard'),
        '通知' => await api.call('notices.list', {
          'offset': offset,
          'search': search.text.trim(),
        }),
        '系统设置' => await api.call('links.get'),
        _ => <String, dynamic>{},
      };
      if (mounted && ticket == generation) setState(() => data = value);
    } catch (e) {
      if (mounted && ticket == generation) setState(() => error = e.toString());
    } finally {
      if (mounted && ticket == generation) setState(() => busy = false);
    }
  }

  Future<void> logout() async {
    ++generation;
    try {
      await api.signOut();
    } catch (_) {}
    if (mounted) {
      setState(() {
        member = null;
        data = {};
        error = null;
        busy = false;
        password.clear();
      });
    }
  }

  Future<void> edit([Map<String, dynamic>? row]) async {
    final saved = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => NoticeEditor(api: api, item: row),
      ),
    );
    if (saved == true && mounted) await load();
  }

  Future<void> remove(Map<String, dynamic> row) async {
    final yes = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('删除这条通知？'),
        content: const Text('通知将从用户端撤下，后台保留删除记录。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(c, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (yes != true || !mounted) return;
    setState(() => busy = true);
    try {
      await api.call('notices.delete', {
        'id': row['id'],
        'version': row['version'],
      });
      await load();
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (member == null) {
      return Scaffold(
        body: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.all(28),
              children: [
                const Icon(Icons.admin_panel_settings_outlined, size: 56),
                const SizedBox(height: 20),
                Text(
                  '文殊计数器后台管理',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                const SizedBox(height: 12),
                const Text('仅限已授权管理员登录'),
                const SizedBox(height: 24),
                if (widget.api == null) const Text('管理服务尚未配置。请由维护人员完成首次配置后使用。'),
                TextField(
                  controller: email,
                  enabled: !busy,
                  decoration: const InputDecoration(labelText: '管理员邮箱'),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: password,
                  enabled: !busy,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: '密码'),
                  onSubmitted: (_) => login(),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: busy || widget.api == null ? null : login,
                  child: Text(busy ? '正在验证…' : '登录后台'),
                ),
                if (error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 16),
                    child: Text(
                      error!,
                      style: const TextStyle(color: Colors.red),
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: const Text('文殊计数器后台管理'),
        actions: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text('${member!['email']} · $roleName'),
          ),
          IconButton(
            tooltip: '刷新',
            onPressed: busy ? null : load,
            icon: const Icon(Icons.refresh),
          ),
          TextButton(
            onPressed: busy ? null : logout,
            child: const Text('退出登录'),
          ),
          const SizedBox(width: 16),
        ],
      ),
      body: Row(
        children: [
          SizedBox(
            width: 180,
            child: ListView(
              children: [
                for (final name in sections)
                  if (allowed(name))
                    ListTile(
                      selected: section == name,
                      title: Text(name),
                      onTap: busy
                          ? null
                          : () {
                              setState(() {
                                section = name;
                                offset = 0;
                              });
                              load();
                            },
                    ),
              ],
            ),
          ),
          const VerticalDivider(width: 1),
          Expanded(
            child: Column(
              children: [
                if (busy) const LinearProgressIndicator(),
                if (error != null)
                  MaterialBanner(
                    content: Text(error!),
                    actions: [
                      TextButton(
                        onPressed: busy ? null : load,
                        child: const Text('重试'),
                      ),
                    ],
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: body(),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget body() => switch (section) {
    '首页' => dashboard(),
    '通知' => notices(),
    '论坛' || '文章' || '用户' => CatalogPage(
      key: ValueKey('$section-$generation'),
      api: api,
      section: section,
    ),
    '系统设置' =>
      data['item'] == null
          ? const SizedBox.shrink()
          : LinksPanel(
              api: api,
              item: Map<String, dynamic>.from(data['item']),
              reload: load,
            ),
    '藏历' => CalendarContentPage(api: api),
    '用户资源用量' => ResourceUsagePage(api: api),
    'App版本' => AppReleasesPage(api: api),
    '公共网盘' => ResourceAdminPage(api: api),
    '结缘管理' => JieyuanAdminPage(api: api),
    '群聊管理' => ChatAdminPage(api: api),
    '备用连接' => ConnectionConfigPage(api: api),
    '后台发布笔记' => PublicContentPage(
      key: const ValueKey('public-notes'),
      api: api,
      notes: true,
    ),
    '关于与联系' => PublicContentPage(
      key: const ValueKey('about'),
      api: api,
      notes: false,
    ),
    '云存储' => ListView(
      children: [
        for (final name in [
          'Supabase Storage',
          '阿里云 OSS',
          '腾讯云 COS',
          'Google Drive',
        ])
          Card(
            child: ListTile(
              title: Text(name),
              subtitle: const Text('尚未接入管理端连接检查'),
            ),
          ),
      ],
    ),
    _ => Center(
      child: Text(
        '$section管理尚未接入。\n${section == '论坛' ? '现有论坛属于外部网站，需要接入网站管理接口。' : '将在后续阶段开放，不影响现有用户端。'}',
        textAlign: TextAlign.center,
      ),
    ),
  };
  Widget dashboard() {
    const labels = {
      'users': '用户总数',
      'new_users': '今日新增用户',
      'active_counters': '今日计数活跃用户',
      'today_count': '今日净增计数',
      'total_count': '累计净计数',
    };
    return ListView(
      children: [
        Text('首页', style: Theme.of(context).textTheme.headlineMedium),
        const Text('统计按北京时间计算，仅包含已同步数据。活跃用户指当天有计数变化的用户。'),
        const SizedBox(height: 16),
        Wrap(
          spacing: 16,
          runSpacing: 16,
          children: [
            for (final e in labels.entries)
              SizedBox(
                width: 220,
                child: Card(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(e.value),
                        const SizedBox(height: 12),
                        Text(
                          '${data[e.key] ?? '—'}',
                          style: Theme.of(context).textTheme.headlineMedium,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
        const SizedBox(height: 24),
        const Text('最新通知'),
        for (final row in data['notices'] as List? ?? [])
          Card(
            child: ListTile(
              title: Text('${row['title_zh']}'),
              subtitle: Text(
                row['is_published'] == true
                    ? '已发布'
                    : row['scheduled_at'] != null
                    ? '待定时发布'
                    : '草稿',
              ),
            ),
          ),
        const SizedBox(height: 16),
        const Text('今日新帖、待处理论坛内容、笔记统计：尚未接入。'),
      ],
    );
  }

  Widget notices() => Column(
    children: [
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: search,
              decoration: const InputDecoration(labelText: '搜索通知标题'),
              onSubmitted: (_) {
                offset = 0;
                load();
              },
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: busy
                ? null
                : () {
                    offset = 0;
                    load();
                  },
            child: const Text('搜索'),
          ),
          const SizedBox(width: 12),
          FilledButton.icon(
            onPressed: busy ? null : () => edit(),
            icon: const Icon(Icons.add),
            label: const Text('新建通知'),
          ),
        ],
      ),
      const SizedBox(height: 16),
      Expanded(
        child: rows.isEmpty
            ? const Center(child: Text('暂无通知'))
            : ListView(
                children: [
                  for (final row in rows)
                    Card(
                      child: ListTile(
                        title: Text('${row['title_zh']}'),
                        subtitle: Text(
                          '${row['is_pinned'] == true ? '置顶 · ' : ''}${row['is_published'] == true
                              ? '已发布'
                              : row['scheduled_at'] != null
                              ? '定时发布：${DateTime.tryParse(row['scheduled_at'])?.toLocal()}'
                              : '草稿'}',
                        ),
                        trailing: Wrap(
                          children: [
                            TextButton(
                              onPressed: busy ? null : () => edit(row),
                              child: const Text('编辑'),
                            ),
                            TextButton(
                              onPressed: busy ? null : () => remove(row),
                              child: const Text('删除'),
                            ),
                          ],
                        ),
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
                    offset -= 50;
                    load();
                  },
            child: const Text('上一页'),
          ),
          Text('第 ${offset ~/ 50 + 1} 页'),
          TextButton(
            onPressed: busy || rows.length < 50
                ? null
                : () {
                    offset += 50;
                    load();
                  },
            child: const Text('下一页'),
          ),
        ],
      ),
    ],
  );
}

class LinksPanel extends StatefulWidget {
  final AdminApi api;
  final Map<String, dynamic> item;
  final Future<void> Function() reload;
  const LinksPanel({
    super.key,
    required this.api,
    required this.item,
    required this.reload,
  });
  @override
  State<LinksPanel> createState() => _LinksPanelState();
}

class _LinksPanelState extends State<LinksPanel> {
  late final calendar = TextEditingController(
    text: widget.item['calendar_url'],
  );
  late final forum = TextEditingController(text: widget.item['forum_url']);
  late final sunrise = TextEditingController(
    text:
        widget.item['sunrise_url'] ??
        'https://www.daysfromdate.com/zh-cn/sunrise/cn?utm_source=chatgpt.com',
  );
  late final offering = TextEditingController(
    text: widget.item['offering_url'] ?? '',
  );
  bool saving = false;
  String? message;
  @override
  void dispose() {
    calendar.dispose();
    forum.dispose();
    sunrise.dispose();
    offering.dispose();
    super.dispose();
  }

  Future<void> save() async {
    for (final value in [
      calendar.text,
      forum.text,
      sunrise.text,
      if (offering.text.trim().isNotEmpty) offering.text,
    ]) {
      final uri = Uri.tryParse(value.trim());
      if (uri == null ||
          uri.scheme != 'https' ||
          uri.host.isEmpty ||
          uri.userInfo.isNotEmpty ||
          value.trim().length > 2048 ||
          RegExp(r'\s').hasMatch(value.trim())) {
        setState(() => message = '请填写完整 HTTPS 网址。');
        return;
      }
    }
    setState(() => saving = true);
    try {
      await widget.api.call('links.save', {
        'calendar_url': calendar.text.trim(),
        'forum_url': forum.text.trim(),
        'sunrise_url': sunrise.text.trim(),
        'offering_url': offering.text.trim(),
        'version': widget.item['version'],
      });
      await widget.reload();
    } catch (e) {
      if (mounted) setState(() => message = e.toString());
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  @override
  Widget build(BuildContext context) => ListView(
    children: [
      Text('手机与电脑入口设置', style: Theme.of(context).textTheme.headlineMedium),
      const SizedBox(height: 24),
      TextField(
        controller: calendar,
        decoration: const InputDecoration(labelText: '藏历网址'),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: forum,
        decoration: const InputDecoration(labelText: '论坛网址'),
      ),
      const SizedBox(height: 20),
      TextField(
        controller: sunrise,
        decoration: const InputDecoration(
          labelText: '日出网址',
          helperText: '日出栏点击后打开的网址，请填写完整 HTTPS 链接。',
        ),
      ),
      const SizedBox(height: 12),
      TextField(
        controller: offering,
        decoration: const InputDecoration(
          labelText: '供佛网址',
          helperText: '可留空；填写后显示在用户端我的页面。',
        ),
      ),
      const Text('保存后，用户端联网启动、回到前台或定期刷新时更新；离线保留上次网址。'),
      const SizedBox(height: 20),
      FilledButton(
        onPressed: saving ? null : save,
        child: const Text('保存入口网址'),
      ),
      if (message != null) Text(message!),
      const SizedBox(height: 24),
      const Text('后台管理员授权由超级管理员维护；首位管理员需由项目所有者进行一次性授权。'),
      OutlinedButton(
        onPressed: saving
            ? null
            : () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => MembersPage(api: widget.api),
                ),
              ),
        child: const Text('后台管理员'),
      ),
    ],
  );
}
