import 'dart:io';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:venera_next/features/local_comics/local_comics.dart';
import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/foundation/file_system.dart'
    show bytesToReadableString;
import 'package:venera_next/foundation/reading_activity.dart';
import 'settings_task_presenter.dart';

class CacheCleanupSettings extends StatefulWidget {
  const CacheCleanupSettings({super.key, this.manager});
  final CacheManager? manager;
  @override
  State<CacheCleanupSettings> createState() => _CacheCleanupSettingsState();
}

class _CacheCleanupSettingsState extends State<CacheCleanupSettings> {
  late final _cache = widget.manager ?? CacheManager();
  final _tasks = SettingsTaskPresenter();
  ({int entries, int expired, int bytes})? _summary;
  bool _busy = false;
  String? _error;
  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    try {
      final result = await _cache.summary();
      if (mounted) {
        setState(() {
          _summary = result;
          _error = null;
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() => _error = '$error');
      }
    }
  }

  Future<void> _checkSeparation() async {
    final library = LocalManager.current;
    if (library == null) return;
    if (library.downloadingTasks.isNotEmpty) {
      throw StateError('请等待下载完成或取消下载任务后再清理');
    }
    final root = await Directory(
      _cache.managedDirectoryPath,
    ).resolveSymbolicLinks();
    // Existing registered local files must never be treated as disposable cache.
    for (final comic in library.getComics(LocalSortType.name)) {
      if (comic.baseDir.startsWith('content:')) {
        continue;
      }
      final directory = Directory(comic.baseDir);
      if (!await directory.exists()) continue;
      final path = await directory.resolveSymbolicLinks();
      if (p.equals(root, path) ||
          p.isWithin(root, path) ||
          p.isWithin(path, root)) {
        throw StateError('缓存目录与本地漫画目录重叠，请先调整存储路径');
      }
    }
  }

  Future<void> _clear({required bool expiredOnly}) async {
    if (_busy) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(expiredOnly ? '仅清理过期缓存？' : '清理全部临时缓存？'),
        content: const SingleChildScrollView(
          child: Text(
            '只删除缓存管理器保存的临时图片和请求数据。\n\n保留本地下载、智能预下载、本地导入、收藏、阅读进度、裁切／遮罩设置和浏览器登录信息。\n\n在线图片与裁切结果可能需要重新联网加载或生成；清理期间不安排阅读。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('确认清理'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _busy = true);
    try {
      await _tasks.run(
        context,
        task: (_) => ReadingActivity.instance.runMaintenance(() async {
          await _checkSeparation();
          if (ReadingActivity.instance.isReading) {
            throw StateError('请退出阅读器后清理缓存');
          }
          if (expiredOnly) {
            await _cache.clearExpired();
          } else {
            await _cache.clear();
          }
          return null;
        }),
        errorMessage: '缓存清理失败，请确认已退出阅读器且下载队列空闲',
        successMessage: '缓存清理完成',
        onSuccess: () {
          _refresh();
        },
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _memory() async {
    if (_busy || ReadingActivity.instance.isReading) {
      setState(() => _error = '请退出阅读器后释放图片内存');
      return;
    }
    PaintingBinding.instance.imageCache.clear();
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final memory = PaintingBinding.instance.imageCache;
    return Scaffold(
      appBar: AppBar(title: const Text('缓存管理')),
      body: ListView(
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text('临时缓存和本地下载分别管理。清理缓存不会删除正常存放的下载漫画；要删除下载，请使用下方“本地下载清理”。'),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          ListTile(
            title: const Text('磁盘临时缓存'),
            subtitle: Text(
              _summary == null
                  ? '正在读取…'
                  : '${bytesToReadableString(_summary!.bytes)} · ${_summary!.entries} 条缓存记录\n其中 ${_summary!.expired} 条已过期；正在加载的图片可能使缓存重新增加',
            ),
            trailing: IconButton(
              onPressed: _busy ? null : _refresh,
              icon: const Icon(Icons.refresh),
              tooltip: '刷新统计',
            ),
          ),
          ListTile(
            title: const Text('仅清理过期缓存'),
            subtitle: const Text('保留仍在有效期内的缓存，减少重新加载'),
            trailing: TextButton(
              onPressed: _busy ? null : () => _clear(expiredOnly: true),
              child: const Text('清理'),
            ),
          ),
          ListTile(
            title: const Text('清理全部临时缓存'),
            subtitle: const Text('清除缓存管理器内的图片、原图副本、处理结果及请求缓存'),
            trailing: TextButton(
              onPressed: _busy ? null : () => _clear(expiredOnly: false),
              child: const Text('清理'),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('可回收的图片内存缓存'),
            subtitle: Text(
              '${bytesToReadableString(memory.currentSizeBytes)} · ${memory.currentSize} 张\n只释放内存缓存，不删除磁盘文件；不是应用总内存',
            ),
            trailing: TextButton(
              onPressed: _busy ? null : _memory,
              child: const Text('释放'),
            ),
          ),
          const Divider(),
          ListTile(
            title: const Text('本地下载清理'),
            subtitle: const Text('自行选择整本漫画或已下载章节；删除前确认清单'),
            trailing: const Icon(Icons.chevron_right),
            onTap: _busy
                ? null
                : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const LocalDownloadCleanupPage(),
                    ),
                  ),
          ),
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              '此处不清理浏览器 Cookie、登录令牌、同步配置、阅读历史或收藏图片文件。清理后，在线内容离线可用性可能降低；已下载的漫画仍可从本地阅读。',
            ),
          ),
        ],
      ),
    );
  }
}
