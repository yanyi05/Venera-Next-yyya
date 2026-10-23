import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher_string.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/foundation/appdata.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/features/search/search.dart';
import 'bangumi_client.dart';
import 'bangumi_service.dart';

/// The same page acts as an account library and an explicit subject picker.
class BangumiPage extends StatefulWidget {
  const BangumiPage({super.key, this.keyword = '', this.pick = false});
  final String keyword;
  final bool pick;
  @override
  State<BangumiPage> createState() => _BangumiPageState();
}

class _BangumiPageState extends State<BangumiPage> {
  final service = BangumiService.instance;
  late final query = TextEditingController(text: widget.keyword);
  BangumiJson auth = {};
  List<BangumiJson> items = [];
  int state = 1;
  int offset = 0;
  bool more = false, busy = false, searching = false;
  bool importing = false;
  String? error;
  @override
  void initState() {
    super.initState();
    unawaited(_initialize());
  }

  Future<void> _initialize() async {
    auth = await service.session();
    final saved = BangumiService.map(appdata.settings['bangumiLibrary']);
    final owner = auth['id']?.toString();
    items = (saved[owner] as List? ?? [])
        .map((e) => BangumiService.map(e))
        .where((e) => e['_collectionType'] == state)
        .toList();
    searching = widget.pick || query.text.trim().isNotEmpty;
    if (!mounted) return;
    setState(() {});
    if (searching) await _load();
    unawaited(service.drain());
  }

  Future<void> _load({bool next = false}) async {
    if (busy) return;
    if (!searching && auth['username'] == null) {
      setState(() => error = '请先连接 Bangumi 账号，或搜索公开作品资料');
      return;
    }
    final word = query.text.trim();
    if (searching && word.isEmpty) return;
    setState(() {
      busy = true;
      error = null;
    });
    BangumiClient? api;
    try {
      api = await service.client();
      final start = next ? offset : 0;
      final result = searching
          ? await api.search(word, offset: start)
          : await api.library(
              auth['username'].toString(),
              state,
              offset: start,
            );
      final batch = (result['data'] as List)
          .map(
            (row) => searching
                ? BangumiService.map(row)
                : {
                    ...BangumiService.map(row['subject']),
                    '_collectionType': state,
                  },
          )
          .toList();
      if (!mounted) return;
      setState(() {
        if (!next) items = [];
        final ids = items.map((e) => e['id']).toSet();
        items.addAll(batch.where((e) => ids.add(e['id'])));
        offset = start + batch.length;
        more = offset < ((result['total'] as num?)?.toInt() ?? offset);
      });
      if (!searching) {
        // Persist the explicitly imported pages; no exhaustive background crawl.
        final captured = List<BangumiJson>.of(items);
        final owner = auth['id'].toString();
        await appdata.updateSettings((draft) {
          final library = BangumiService.map(draft['bangumiLibrary']);
          final prior = (library[owner] as List? ?? []).map(BangumiService.map);
          final all = <String, dynamic>{
            for (final item in prior) '${item['id']}': item,
            for (final item in captured) '${item['id']}': item,
          };
          library[owner] = all.values.toList();
          draft['bangumiLibrary'] = library;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      api?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _connect() async {
    final token = TextEditingController();
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('连接 Bangumi'),
        content: SizedBox(
          width: 420,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('在 Bangumi 官网生成个人令牌，粘贴后连接。令牌仅保存在本机；其他设备需单独连接。'),
              TextButton(
                onPressed: () => launchUrlString(
                  'https://next.bgm.tv/demo/access-token',
                  mode: LaunchMode.externalApplication,
                ),
                child: const Text('打开 Bangumi 获取令牌'),
              ),
              TextField(
                controller: token,
                obscureText: true,
                enableSuggestions: false,
                autocorrect: false,
                decoration: const InputDecoration(labelText: 'Access Token'),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('连接'),
          ),
        ],
      ),
    );
    final value = token.text.trim();
    token.dispose();
    if (accepted != true || value.isEmpty || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.connect(value);
      final session = await service.session();
      if (mounted) {
        setState(() {
          auth = session;
          items = [];
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _importAll() async {
    if (busy || importing) return;
    setState(() {
      importing = true;
      searching = false;
    });
    try {
      await _load();
      while (mounted && importing && more && error == null) {
        await _load(next: true);
      }
    } finally {
      if (mounted) setState(() => importing = false);
    }
  }

  @override
  void dispose() {
    query.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: Appbar(
      title: Text(widget.pick ? '关联 Bangumi 作品' : 'Bangumi 书单'),
      actions: [
        TextButton(
          onPressed: busy ? null : _connect,
          child: Text(
            auth['username'] == null
                ? '连接账号'
                : '${auth['nickname'] ?? auth['username']}',
          ),
        ),
        if (auth['username'] != null)
          IconButton(
            tooltip: '断开账号',
            icon: const Icon(Icons.logout),
            onPressed: busy
                ? null
                : () async {
                    await service.disconnect();
                    if (mounted) {
                      setState(() {
                        auth = {};
                        items = [];
                      });
                    }
                  },
          ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(12),
          child: TextField(
            enabled: !busy,
            controller: query,
            onSubmitted: (_) {
              searching = true;
              _load();
            },
            decoration: InputDecoration(
              hintText: '搜索漫画名称，手动确认对应作品',
              suffixIcon: IconButton(
                onPressed: busy
                    ? null
                    : () {
                        searching = true;
                        _load();
                      },
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        if (!widget.pick)
          Wrap(
            spacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              for (final entry in bangumiStates.entries)
                ChoiceChip(
                  label: Text(entry.value),
                  selected: !searching && state == entry.key,
                  onSelected: busy
                      ? null
                      : (_) {
                          state = entry.key;
                          searching = false;
                          _load();
                        },
                ),
              TextButton(
                onPressed: busy
                    ? null
                    : () {
                        searching = false;
                        _load();
                      },
                child: const Text('导入／刷新书单'),
              ),
              TextButton(
                onPressed: importing
                    ? () => setState(() => importing = false)
                    : busy
                    ? null
                    : _importAll,
                child: Text(
                  importing ? '停止导入（已导入 ${items.length} 本）' : '导入当前分类全部书单',
                ),
              ),
            ],
          ),
        if (busy) const LinearProgressIndicator(),
        if (error != null)
          Padding(padding: const EdgeInsets.all(12), child: Text(error!)),
        if (service.lastError != null) Text('进度待同步：${service.lastError}'),
        Expanded(
          child: ListView.builder(
            itemCount: items.length + (more ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == items.length) {
                return TextButton(
                  onPressed: busy ? null : () => _load(next: true),
                  child: const Text('加载更多'),
                );
              }
              final item = items[index];
              return ListTile(
                title: Text(bangumiTitle(item)),
                subtitle: Text('${item['name'] ?? ''} · ${item['date'] ?? ''}'),
                trailing: Icon(widget.pick ? Icons.link : Icons.chevron_right),
                onTap: busy
                    ? null
                    : () {
                        if (widget.pick) {
                          Navigator.pop(context, item);
                        } else {
                          context.to(
                            () => BangumiSubjectPage(id: item['id'] as int),
                          );
                        }
                      },
              );
            },
          ),
        ),
      ],
    ),
  );
}

class BangumiSubjectPage extends StatefulWidget {
  const BangumiSubjectPage({super.key, required this.id});
  final int id;
  @override
  State<BangumiSubjectPage> createState() => _BangumiSubjectPageState();
}

class _BangumiSubjectPageState extends State<BangumiSubjectPage> {
  final service = BangumiService.instance;
  BangumiJson? subject, collection;
  List<BangumiJson> relations = [];
  String? error;
  bool busy = false;
  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      busy = true;
      error = null;
    });
    BangumiClient? api;
    try {
      api = await service.client();
      final item = await api.subject(widget.id);
      if (!mounted) return;
      setState(() => subject = item);
      final auth = await service.session();
      final own = auth['username'] == null
          ? null
          : await api.collection(auth['username'].toString(), widget.id);
      if (mounted) setState(() => collection = own);
      final related = await api.relations(widget.id);
      if (mounted) {
        setState(() {
          collection = own;
          relations = related;
        });
      }
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      api?.close();
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> _edit() async {
    final auth = await service.session();
    if (!mounted) return;
    if (auth['token'] == null) {
      context.to(() => const BangumiPage());
      return;
    }
    final values = await showDialog<BangumiJson>(
      context: context,
      builder: (_) => _CollectionDialog(value: collection ?? {}),
    );
    if (values == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.saveCollection(widget.id, values);
      if (mounted) setState(() => collection = {...?collection, ...values});
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final item = subject;
    final rating = BangumiService.map(item?['rating']);
    final images = BangumiService.map(item?['images']);
    return Scaffold(
      appBar: Appbar(
        title: Text(item == null ? 'Bangumi' : bangumiTitle(item)),
        actions: [
          IconButton(
            onPressed: busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          if (item != null) ...[
            if (images['medium'] is String)
              Center(
                child: Image.network(
                  images['medium'],
                  height: 200,
                  errorBuilder: (_, _, _) => const Icon(Icons.book, size: 80),
                ),
              ),
            Text(
              bangumiTitle(item),
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            Text(
              '评分 ${rating['score'] ?? '—'} · ${rating['total'] ?? 0} 人 · 排名 ${rating['rank'] ?? '—'}',
            ),
            const SizedBox(height: 12),
            Text(item['summary']?.toString() ?? ''),
            Wrap(
              spacing: 8,
              children: [
                for (final tag in (item['tags'] as List? ?? []).take(12))
                  Chip(label: Text(tag['name'].toString())),
              ],
            ),
            Wrap(
              spacing: 8,
              children: [
                if (item['type'] == 1)
                  FilledButton(
                    onPressed: busy ? null : _edit,
                    child: Text(
                      collection == null
                          ? '加入书单／评分'
                          : '${bangumiStates[collection!['type']] ?? '收藏'} · 我的评分 ${collection!['rate'] ?? 0}',
                    ),
                  ),
                OutlinedButton(
                  onPressed: () => context.to(
                    () => AggregatedSearchPage(keyword: bangumiTitle(item)),
                  ),
                  child: const Text('在漫画源中查找'),
                ),
                TextButton(
                  onPressed: () => launchUrlString(
                    'https://bgm.tv/subject/${widget.id}',
                    mode: LaunchMode.externalApplication,
                  ),
                  child: const Text('查看 Bangumi 网页'),
                ),
              ],
            ),
            if (collection != null)
              Text(
                '读至 ${collection!['ep_status'] ?? 0} 话／${collection!['vol_status'] ?? 0} 卷\n${collection!['comment'] ?? ''}',
              ),
            const Divider(),
            const Text('关联作品'),
            for (final related in relations)
              ListTile(
                title: Text(bangumiTitle(related)),
                subtitle: Text(related['relation']?.toString() ?? ''),
                onTap: () => context.to(
                  () => BangumiSubjectPage(id: related['id'] as int),
                ),
              ),
          ],
        ],
      ),
    );
  }
}

class _CollectionDialog extends StatefulWidget {
  const _CollectionDialog({required this.value});
  final BangumiJson value;
  @override
  State<_CollectionDialog> createState() => _CollectionDialogState();
}

class _CollectionDialogState extends State<_CollectionDialog> {
  late int type = widget.value['type'] as int? ?? 3;
  late int rate = widget.value['rate'] as int? ?? 0;
  late bool private = widget.value['private'] as bool? ?? false;
  late final comment = TextEditingController(
    text: widget.value['comment'] as String? ?? '',
  );
  late final tags = TextEditingController(
    text: (widget.value['tags'] as List? ?? []).join(' '),
  );
  late final ep = TextEditingController(
    text: '${widget.value['ep_status'] ?? 0}',
  );
  late final vol = TextEditingController(
    text: '${widget.value['vol_status'] ?? 0}',
  );
  final form = GlobalKey<FormState>();
  @override
  void dispose() {
    for (final c in [comment, tags, ep, vol]) {
      c.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
    title: const Text('阅读状态、评分与进度'),
    content: SizedBox(
      width: 460,
      child: SingleChildScrollView(
        child: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButtonFormField<int>(
                initialValue: type,
                items: [
                  for (final e in bangumiStates.entries)
                    DropdownMenuItem(value: e.key, child: Text(e.value)),
                ],
                onChanged: (v) => type = v!,
              ),
              Row(
                children: [
                  const Text('评分'),
                  Expanded(
                    child: Slider(
                      value: rate.toDouble(),
                      min: 0,
                      max: 10,
                      divisions: 10,
                      label: rate == 0 ? '未评分' : '$rate',
                      onChanged: (v) => setState(() => rate = v.round()),
                    ),
                  ),
                  Text('$rate'),
                ],
              ),
              TextFormField(
                controller: comment,
                maxLines: 3,
                maxLength: 380,
                decoration: const InputDecoration(labelText: '短评'),
              ),
              TextFormField(
                controller: tags,
                decoration: const InputDecoration(labelText: '标签（空格分隔）'),
              ),
              for (final field in [(ep, '读至话数'), (vol, '读至卷数')])
                TextFormField(
                  controller: field.$1,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: field.$2),
                  validator: (v) =>
                      int.tryParse(v ?? '') == null || int.parse(v!) < 0
                      ? '请输入非负整数'
                      : null,
                ),
              CheckboxListTile(
                value: private,
                title: const Text('仅自己可见'),
                onChanged: (v) => setState(() => private = v!),
              ),
            ],
          ),
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
          if (!form.currentState!.validate()) return;
          Navigator.pop(context, {
            'type': type,
            'rate': rate,
            'comment': comment.text,
            'tags': tags.text
                .trim()
                .split(RegExp(r'\s+'))
                .where((s) => s.isNotEmpty)
                .toList(),
            'private': private,
            if (int.parse(ep.text) != (widget.value['ep_status'] ?? 0))
              'ep_status': int.parse(ep.text),
            if (int.parse(vol.text) != (widget.value['vol_status'] ?? 0))
              'vol_status': int.parse(vol.text),
          });
        },
        child: const Text('保存到 Bangumi'),
      ),
    ],
  );
}
