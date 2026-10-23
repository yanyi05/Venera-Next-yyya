import 'dart:io';
import 'package:flutter/material.dart';
import 'package:venera_next/components/message.dart';
import 'package:venera_next/components/window_selection_task.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/foundation/reading_activity.dart';
import 'package:venera_next/foundation/selection_operation.dart';
import 'package:venera_next/foundation/file_system.dart'
    show bytesToReadableString;
import 'local.dart';
import 'local_download_removal.dart';

class LocalDownloadCleanupPage extends StatefulWidget {
  const LocalDownloadCleanupPage({super.key, this.manager});
  final LocalManager? manager;
  @override
  State<LocalDownloadCleanupPage> createState() =>
      _LocalDownloadCleanupPageState();
}

class _LocalDownloadCleanupPageState extends State<LocalDownloadCleanupPage> {
  late final LocalManager _library;
  List<LocalComic> _comics = [];
  final _selected = <(String, int), Set<String>?>{};
  final _sizes = <(String, int), String>{};
  bool _imports = false, _busy = false;
  String _search = '';
  (String, int)? _measuring;
  String? _error;
  (String, int) _key(LocalComic comic) => (comic.id, comic.comicType.value);
  @override
  void initState() {
    super.initState();
    _library = widget.manager ?? LocalManager();
    _load();
    _library.addListener(_changed);
  }

  void _load() {
    _comics = _library.getComics(LocalSortType.name);
    final keys = _comics.map(_key).toSet();
    _selected.removeWhere((key, _) => !keys.contains(key));
    _sizes.clear();
  }

  void _changed() {
    if (mounted) setState(_load);
  }

  @override
  void dispose() {
    _library.removeListener(_changed);
    super.dispose();
  }

  List<LocalComic> get _visible => _comics
      .where(
        (comic) =>
            (_imports || comic.comicType != ComicType.local) &&
            comic.title.toLowerCase().contains(_search.toLowerCase()),
      )
      .toList();

  Future<void> _size(LocalComic comic) async {
    if (_measuring != null || _busy || ReadingActivity.instance.isReading) {
      return;
    }
    final key = _key(comic);
    setState(() => _measuring = key);
    var bytes = 0;
    var message = '无法统计';
    try {
      // User-requested scan only; no links, no automatic whole-library traversal.
      await for (final entity in Directory(
        comic.baseDir,
      ).list(recursive: true, followLinks: false)) {
        if (!mounted ||
            _busy ||
            ReadingActivity.instance.isReading ||
            ModalRoute.of(context)?.isCurrent != true) {
          return;
        }
        if (entity is File) {
          bytes += await entity.length();
        }
      }
      message = bytesToReadableString(bytes);
    } catch (_) {
      /* Some external/SAF paths do not expose filesystem sizes. */
    } finally {
      if (mounted) {
        setState(() {
          _sizes[key] = message;
          _measuring = null;
        });
      }
    }
  }

  Future<void> _pickChapters(LocalComic comic) async {
    final key = _key(comic);
    final initial = _selected.containsKey(key) && _selected[key] == null
        ? comic.downloadedChapters.toSet()
        : {...?_selected[key]};
    final chosen = await Navigator.of(context).push<Set<String>>(
      MaterialPageRoute(
        builder: (_) =>
            _ChapterPicker(comic: comic, manager: _library, selected: initial),
      ),
    );
    if (!mounted || chosen == null) {
      return;
    }
    setState(() {
      if (chosen.isEmpty) {
        _selected.remove(key);
      } else {
        _selected[key] = chosen;
      }
    });
  }

  List<LocalDownloadRemoval> _plan() => [
    for (final comic in _comics)
      if (_selected.containsKey(_key(comic)))
        LocalDownloadRemoval(
          comic,
          chapters: _selected[_key(comic)]?.toList(),
          protection: {
            for (final id
                in _selected[_key(comic)] ?? comic.downloadedChapters.toSet())
              id: _library.automaticChapterProtection(
                comic.id,
                comic.comicType,
                id,
              ),
          },
        ),
  ];

  Future<void> _remove() async {
    if (_busy || _selected.isEmpty) return;
    if (ReadingActivity.instance.isReading ||
        _library.downloadingTasks.isNotEmpty) {
      setState(() => _error = '请退出阅读器，并等待下载完成或取消下载任务后再清理。');
      return;
    }
    List<LocalDownloadRemoval> plan;
    try {
      plan = _plan();
    } catch (error) {
      setState(() => _error = '$error');
      return;
    }
    if (plan.isEmpty) return;
    final protected = plan.fold<int>(
      0,
      (count, entry) => count + entry.protectedCount,
    );
    final imported = plan
        .where((entry) => entry.comic.comicType == ComicType.local)
        .length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('删除所选本地下载？'),
        content: SizedBox(
          width: 480,
          height: 320,
          child: ListView.builder(
            itemCount: plan.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('将删除选中的本地文件，收藏和阅读记录保留。文件删除后无法撤销。'),
                    if (protected > 0)
                      Text('包含 $protected 个受保护的智能下载章节；本次手动删除也会删除它们。'),
                    if (imported > 0) Text('包含 $imported 本本地导入漫画，将删除其对应本地文件。'),
                    const SizedBox(height: 12),
                  ],
                );
              }
              final entry = plan[index - 1];
              return ListTile(
                title: Text(entry.comic.title),
                subtitle: Text(
                  entry.chapters == null
                      ? '整本本地内容（含封面）'
                      : '仅所选 ${entry.chapters!.length} 章，保留漫画条目',
                ),
              );
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认删除'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    final owner = WindowSelectionTask(context);
    if (!owner.canPresent) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var completed = 0;
    try {
      await owner.run((operation) async {
        final progress = showLoadingDialog(
          context,
          barrierDismissible: false,
          allowCancel: false,
          message: '正在删除所选下载',
          withProgress: true,
        );
        owner.retainPresentation(
          progress.close,
          isCurrent: () => progress.isCurrent,
        );
        for (final entry in plan) {
          operation.checkActive();
          progress.setMessage('正在删除：${entry.comic.title}');
          await _library.removeDownloadedContent(entry);
          completed++;
          if (mounted) {
            setState(() {
              _selected.remove(entry.key);
              _sizes.remove(entry.key);
            });
          }
          progress.setProgress(completed / plan.length);
        }
      }, reportFailureOnClose: true);
    } on SelectionCancelled {
      // Completed books remain deleted; do not start another accepted target.
    } catch (error) {
      if (mounted) {
        setState(
          () =>
              _error = '已完成 $completed/${plan.length} 本；其余未完成，请刷新后重选。\n$error',
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _busy = false;
          _load();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    return PopScope(
      canPop: !_busy,
      child: Scaffold(
        appBar: AppBar(
          title: const Text('本地下载清理'),
          actions: [
            IconButton(
              tooltip: '刷新并清空选择',
              icon: const Icon(Icons.refresh),
              onPressed: _busy
                  ? null
                  : () => setState(() {
                      _selected.clear();
                      _sizes.clear();
                      _error = null;
                      _load();
                    }),
            ),
          ],
        ),
        body: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(
              child: Column(
                children: [
                  const Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      '勾选整本删除，或进入“选章节”只清理部分下载。收藏和阅读记录保留；删除的章节需要重新下载才能离线阅读。',
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      decoration: const InputDecoration(
                        labelText: '搜索漫画',
                        prefixIcon: Icon(Icons.search),
                      ),
                      enabled: !_busy,
                      onChanged: (value) => setState(() => _search = value),
                    ),
                  ),
                  SwitchListTile(
                    title: const Text('显示本地导入内容'),
                    subtitle: const Text('默认隐藏；开启后也需要自行勾选'),
                    value: _imports,
                    onChanged: _busy
                        ? null
                        : (value) => setState(() {
                            _imports = value;
                            if (!value) {
                              for (final comic in _comics.where(
                                (c) => c.comicType == ComicType.local,
                              )) {
                                _selected.remove(_key(comic));
                              }
                            }
                          }),
                  ),
                  if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(12),
                      child: Text(
                        _error!,
                        style: TextStyle(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            if (visible.isEmpty)
              const SliverFillRemaining(
                hasScrollBody: false,
                child: Center(child: Text('没有符合条件的本地下载')),
              )
            else
              SliverList.builder(
                itemCount: visible.length,
                itemBuilder: (context, index) {
                  final comic = visible[index], key = _key(visible[index]);
                  final whole =
                      _selected.containsKey(key) && _selected[key] == null;
                  final partial = _selected[key];
                  return Card(
                    child: Column(
                      children: [
                        CheckboxListTile(
                          title: Text(comic.title),
                          tristate: true,
                          subtitle: Text(
                            '${comic.comicType == ComicType.local ? '本地导入' : '在线源下载'} · ${comic.downloadedChapters.length} 个已下载章节'
                            '${partial == null ? '' : ' · 已选 ${partial.length} 章'}',
                          ),
                          value: whole
                              ? true
                              : partial == null
                              ? false
                              : null,
                          onChanged: _busy
                              ? null
                              : (_) => setState(() {
                                  if (_selected.containsKey(key)) {
                                    _selected.remove(key);
                                  } else {
                                    _selected[key] = null;
                                  }
                                }),
                        ),
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 8),
                          child: Wrap(
                            spacing: 8,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              if (comic.chapters != null &&
                                  comic.downloadedChapters.isNotEmpty)
                                TextButton(
                                  onPressed: _busy
                                      ? null
                                      : () => _pickChapters(comic),
                                  child: const Text('选章节'),
                                ),
                              Text(_sizes[key] ?? '空间按需统计'),
                              TextButton(
                                onPressed: _busy || _measuring != null
                                    ? null
                                    : () => _size(comic),
                                child: Text(
                                  _measuring == key ? '统计中…' : '计算大小',
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
          ],
        ),
        bottomNavigationBar: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Wrap(
              alignment: WrapAlignment.end,
              spacing: 8,
              children: [
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => setState(() {
                          for (final comic in visible) {
                            _selected[_key(comic)] = null;
                          }
                        }),
                  child: const Text('全选当前列表'),
                ),
                TextButton(
                  onPressed: _busy ? null : () => setState(_selected.clear),
                  child: const Text('清空选择'),
                ),
                FilledButton(
                  onPressed: _busy || _selected.isEmpty ? null : _remove,
                  child: Text('删除所选（${_selected.length} 本）'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ChapterPicker extends StatefulWidget {
  const _ChapterPicker({
    required this.comic,
    required this.manager,
    required this.selected,
  });
  final LocalComic comic;
  final LocalManager manager;
  final Set<String> selected;
  @override
  State<_ChapterPicker> createState() => _ChapterPickerState();
}

class _ChapterPickerState extends State<_ChapterPicker> {
  late final Set<String> _selected = {...widget.selected};
  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('选择要删除的章节'),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, _selected),
          child: const Text('使用此选择'),
        ),
      ],
    ),
    body: Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: Text('${widget.comic.title}\n只列出已下载章节；选择不会立即删除文件。'),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: widget.comic.downloadedChapters.length,
            itemBuilder: (context, index) {
              final id = widget.comic.downloadedChapters[index];
              final protected =
                  widget.manager.automaticChapterProtection(
                    widget.comic.id,
                    widget.comic.comicType,
                    id,
                  ) ==
                  true;
              return CheckboxListTile(
                title: Text(widget.comic.chapters?[id] ?? id),
                subtitle: protected ? const Text('已保护：仍可明确选择手动删除') : null,
                secondary: protected ? const Icon(Icons.lock_outline) : null,
                value: _selected.contains(id),
                onChanged: (value) => setState(() {
                  if (value == true) {
                    _selected.add(id);
                  } else {
                    _selected.remove(id);
                  }
                }),
              );
            },
          ),
        ),
      ],
    ),
    bottomNavigationBar: SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Wrap(
          spacing: 12,
          children: [
            TextButton(
              onPressed: () => setState(
                () => _selected.addAll(widget.comic.downloadedChapters),
              ),
              child: const Text('全选章节'),
            ),
            TextButton(
              onPressed: () => setState(_selected.clear),
              child: const Text('清空选择'),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text('已选 ${_selected.length} 章'),
            ),
          ],
        ),
      ),
    ),
  );
}
