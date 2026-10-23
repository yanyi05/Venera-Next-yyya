import 'package:flutter/material.dart';
import 'package:venera_next/components/appbar.dart';
import 'package:venera_next/foundation/context.dart';
import 'package:venera_next/features/comic_source/comic_source_api.dart';
import 'bangumi_client.dart';
import 'bangumi_service.dart';
import 'bangumi_page.dart';

class BangumiComicCard extends StatefulWidget {
  const BangumiComicCard({
    super.key,
    required this.source,
    required this.comic,
    required this.title,
    this.chapters,
  });
  final String source, comic, title;
  final ComicChapters? chapters;
  @override
  State<BangumiComicCard> createState() => _BangumiComicCardState();
}

class _BangumiComicCardState extends State<BangumiComicCard> {
  final service = BangumiService.instance;
  bool busy = false;
  String? error;
  Future<void> _bind() async {
    final source = widget.source, comic = widget.comic;
    final result = await Navigator.of(context).push<BangumiJson>(
      MaterialPageRoute(
        builder: (_) => BangumiPage(keyword: widget.title, pick: true),
      ),
    );
    if (result == null ||
        !mounted ||
        source != widget.source ||
        comic != widget.comic) {
      return;
    }
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('确认关联作品'),
        content: Text(
          '${widget.title}\n↔\n${bangumiTitle(result)}\n${result['name'] ?? ''}\n\n请确认这是同一部漫画，而非动画、同名作品或单独一卷。',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认关联'),
          ),
        ],
      ),
    );
    if (accepted != true || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.bind(source, comic, result);
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final binding = service.binding(widget.source, widget.comic);
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              binding == null
                  ? 'Bangumi · 关联作品以管理书单和阅读进度'
                  : 'Bangumi · ${binding['title']}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (binding?['score'] != null)
              Text(
                '评分 ${binding!['score']} · ${binding['votes'] ?? 0} 人 · 排名 ${binding['rank'] ?? '—'}',
              ),
            if (busy) const LinearProgressIndicator(),
            if (error != null) Text(error!),
            Wrap(
              spacing: 8,
              children: [
                if (binding == null)
                  TextButton.icon(
                    onPressed: busy ? null : _bind,
                    icon: const Icon(Icons.link),
                    label: const Text('关联 Bangumi'),
                  ),
                if (binding != null) ...[
                  TextButton(
                    onPressed: () => context.to(
                      () => BangumiSubjectPage(id: binding['subjectId'] as int),
                    ),
                    child: const Text('资料／状态／评分'),
                  ),
                  if (widget.chapters != null)
                    TextButton(
                      onPressed: () => context.to(
                        () => BangumiChapterMappingPage(
                          source: widget.source,
                          comic: widget.comic,
                          chapters: widget.chapters!,
                        ),
                      ),
                      child: const Text('设置章节进度对应'),
                    ),
                  TextButton(
                    onPressed: busy ? null : _bind,
                    child: const Text('更换关联'),
                  ),
                  TextButton(
                    onPressed: busy
                        ? null
                        : () async {
                            final yes = await showDialog<bool>(
                              context: context,
                              builder: (context) => AlertDialog(
                                title: const Text('解除关联？'),
                                content: const Text(
                                  '仅解除当前漫画的关联及章节映射，不删除 Bangumi 收藏。',
                                ),
                                actions: [
                                  TextButton(
                                    onPressed: () =>
                                        Navigator.pop(context, false),
                                    child: const Text('取消'),
                                  ),
                                  FilledButton(
                                    onPressed: () =>
                                        Navigator.pop(context, true),
                                    child: const Text('解除'),
                                  ),
                                ],
                              ),
                            );
                            if (yes != true || !mounted) return;
                            setState(() {
                              busy = true;
                              error = null;
                            });
                            try {
                              await service.unbind(widget.source, widget.comic);
                            } catch (e) {
                              if (mounted) setState(() => error = e.toString());
                            } finally {
                              if (mounted) setState(() => busy = false);
                            }
                          },
                    child: const Text('解除关联'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class BangumiChapterMappingPage extends StatefulWidget {
  const BangumiChapterMappingPage({
    super.key,
    required this.source,
    required this.comic,
    required this.chapters,
  });
  final String source, comic;
  final ComicChapters chapters;
  @override
  State<BangumiChapterMappingPage> createState() =>
      _BangumiChapterMappingPageState();
}

class _BangumiChapterMappingPageState extends State<BangumiChapterMappingPage> {
  final service = BangumiService.instance;
  late final ids = widget.chapters.ids.toList();
  late final titles = widget.chapters.titles.toList();
  bool busy = false;
  String? error;
  Future<void> _edit(int index) async {
    final mapping = BangumiService.map(
      service.binding(widget.source, widget.comic)?['chapters'],
    );
    final old = BangumiService.map(mapping[ids[index]]);
    final ep = TextEditingController(text: old['ep_status']?.toString() ?? '');
    final vol = TextEditingController(
      text: old['vol_status']?.toString() ?? '',
    );
    final form = GlobalKey<FormState>();
    final result = await showDialog<BangumiJson>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(titles[index]),
        content: Form(
          key: form,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('仅为确认过的章节填写对应话数／卷数。读到本章最后一张图片后，退出阅读器时提交进度；番外可不设置。'),
              for (final field in [(ep, '读完本章后已读总话数'), (vol, '读完本章后已读总卷数')])
                TextFormField(
                  controller: field.$1,
                  keyboardType: TextInputType.number,
                  decoration: InputDecoration(labelText: field.$2),
                  validator: (v) =>
                      v == null ||
                          v.trim().isEmpty ||
                          (int.tryParse(v) != null && int.parse(v) >= 0)
                      ? null
                      : '请输入非负整数',
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, <String, dynamic>{}),
            child: const Text('移除映射'),
          ),
          FilledButton(
            onPressed: () {
              if (!form.currentState!.validate()) return;
              Navigator.pop(context, {
                if (ep.text.trim().isNotEmpty) 'ep_status': int.parse(ep.text),
                if (vol.text.trim().isNotEmpty)
                  'vol_status': int.parse(vol.text),
              });
            },
            child: const Text('确认对应并启用'),
          ),
        ],
      ),
    );
    ep.dispose();
    vol.dispose();
    if (result == null || !mounted) return;
    setState(() {
      busy = true;
      error = null;
    });
    try {
      await service.setChapter(
        widget.source,
        widget.comic,
        ids[index],
        result.isEmpty ? null : result,
      );
    } catch (e) {
      if (mounted) setState(() => error = e.toString());
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final mapping = BangumiService.map(
      service.binding(widget.source, widget.comic)?['chapters'],
    );
    return Scaffold(
      appBar: Appbar(title: const Text('章节进度对应')),
      body: Column(
        children: [
          const Padding(
            padding: EdgeInsets.all(12),
            child: Text('不会根据列表序号猜测话数。只有你确认过的章节才自动同步，且不会降低 Bangumi 已有进度。'),
          ),
          if (busy) const LinearProgressIndicator(),
          if (error != null) Text(error!),
          Expanded(
            child: ListView.builder(
              itemCount: ids.length,
              itemBuilder: (context, index) {
                final value = BangumiService.map(mapping[ids[index]]);
                return ListTile(
                  title: Text(titles[index]),
                  subtitle: Text(
                    value.isEmpty
                        ? '未设置，不自动同步'
                        : '话数 ${value['ep_status'] ?? '不变'} · 卷数 ${value['vol_status'] ?? '不变'}',
                  ),
                  trailing: const Icon(Icons.edit_outlined),
                  onTap: busy ? null : () => _edit(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
