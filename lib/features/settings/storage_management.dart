import 'dart:async';
import 'package:flutter/material.dart';
import 'package:venera_next/foundation/cache_manager.dart';
import 'package:venera_next/foundation/cache_storage_snapshot.dart';
import 'package:venera_next/foundation/file_system.dart';
import 'package:venera_next/foundation/comic_type.dart';
import 'package:venera_next/features/history/history_manager.dart';
import 'package:venera_next/features/local_comics/local.dart';

class StorageManagementPage extends StatefulWidget {
  const StorageManagementPage({super.key});
  @override
  State<StorageManagementPage> createState() => _StorageManagementPageState();
}

class _StorageManagementPageState extends State<StorageManagementPage> {
  CacheStorageSnapshot? _snapshot;
  final _selected = <String>{};
  final _downloadSizes = <({String title, int? bytes})>[];
  int _keepDays = 7;
  DateTime _scanTime = DateTime.now();
  bool _busy = false, _scanningDownloads = false;
  String? _error;
  DateTime? get _keepSince =>
      _keepDays == 0 ? null : _scanTime.subtract(Duration(days: _keepDays));

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final snapshot = await CacheManager().storageSnapshot();
      if (!mounted) return;
      setState(() {
        _snapshot = snapshot;
        _scanTime = DateTime.now();
        _selected.clear();
        _error = null;
      });
    } catch (error) {
      if (mounted) setState(() => _error = '无法读取缓存占用：$error');
    }
  }

  Future<void> _scanDownloads() async {
    setState(() {
      _scanningDownloads = true;
      _downloadSizes.clear();
    });
    try {
      final comics = LocalManager().getComics(LocalSortType.name);
      final seen = <String>{};
      for (final comic in comics) {
        if (!mounted) return;
        int? bytes;
        try {
          final path = comic.baseDir;
          if (!seen.add(path)) continue;
          var size = 0;
          await for (final entity in Directory(
            path,
          ).list(recursive: true, followLinks: false)) {
            if (!mounted) return;
            if (entity is File) size += await entity.length();
          }
          bytes = size;
        } catch (_) {
          /* Keep unreadable books visible as unknown. */
        }
        if (mounted) {
          setState(
            () => _downloadSizes.add((title: comic.title, bytes: bytes)),
          );
        }
      }
    } catch (error) {
      if (mounted) setState(() => _error = '扫描未完成：$error');
    } finally {
      if (mounted) setState(() => _scanningDownloads = false);
    }
  }

  String _title(CacheStorageEntry entry) {
    final comic = entry.comic;
    if (comic == null) return '封面、旧版本及其他临时缓存';
    try {
      return HistoryManager()
              .find(comic[1], ComicType.fromKey(comic[0]))
              ?.title ??
          '未记录标题的漫画';
    } catch (_) {
      return '未记录标题的漫画';
    }
  }

  Future<void> _clear() async {
    final snapshot = _snapshot;
    if (_busy || snapshot == null) return;
    final selected = Set.of(_selected), keepSince = _keepSince;
    final estimate = snapshot.estimate(selected, keepSince: keepSince);
    final accepted = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('清理临时缓存？'),
        content: Text(
          '预计释放 ${bytesToReadableString(estimate)}。已下载漫画、收藏、阅读进度和原文件会保留。${_keepDays == 0 ? '' : '\n保留最近 $_keepDays 天使用的缓存。'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('清理'),
          ),
        ],
      ),
    );
    if (!mounted || accepted != true) return;
    setState(() => _busy = true);
    try {
      final bytes = await CacheManager().clearSnapshot(
        snapshot,
        selected,
        keepSince: keepSince,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('已释放 ${bytesToReadableString(bytes)}')),
        );
      }
      await _load();
    } catch (error) {
      if (mounted) setState(() => _error = '清理未完成：$error');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final groups = <String, List<CacheStorageEntry>>{};
    for (final entry in _snapshot?.entries ?? const <CacheStorageEntry>[]) {
      (groups[entry.group] ??= []).add(entry);
    }
    final ordered = groups.entries.toList()
      ..sort(
        (a, b) => b.value
            .fold(0, (n, e) => n + e.bytes)
            .compareTo(a.value.fold(0, (n, e) => n + e.bytes)),
      );
    return Scaffold(
      appBar: AppBar(
        title: const Text('空间管理'),
        actions: [
          IconButton(
            tooltip: '重新统计',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          const Text(
            '临时缓存',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Text('这里的清理只影响临时缓存；之后阅读可重新加载。旧版本缓存会集中显示。'),
          if (_error != null) Text(_error!),
          if (_snapshot == null && _error == null)
            const LinearProgressIndicator(),
          DropdownButton<int>(
            value: _keepDays,
            isExpanded: true,
            items: const [
              DropdownMenuItem(value: 7, child: Text('保留最近 7 天使用的缓存')),
              DropdownMenuItem(value: 30, child: Text('保留最近 30 天使用的缓存')),
              DropdownMenuItem(value: 0, child: Text('不保留最近使用的缓存')),
            ],
            onChanged: _busy
                ? null
                : (value) => setState(() => _keepDays = value!),
          ),
          TextButton(
            onPressed: _busy
                ? null
                : () => setState(() {
                    if (_selected.length == groups.length) {
                      _selected.clear();
                    } else {
                      _selected.addAll(groups.keys);
                    }
                  }),
            child: Text(_selected.length == groups.length ? '取消全选' : '全选缓存'),
          ),
          for (final group in ordered)
            CheckboxListTile(
              title: Text(_title(group.value.first)),
              subtitle: Text(
                '${group.value.length} 个文件 · ${bytesToReadableString(group.value.fold(0, (n, e) => n + e.bytes))}',
              ),
              value: _selected.contains(group.key),
              onChanged: _busy
                  ? null
                  : (value) => setState(() {
                      if (value == true) {
                        _selected.add(group.key);
                      } else {
                        _selected.remove(group.key);
                      }
                    }),
            ),
          if (_snapshot != null && groups.isEmpty) const Text('没有可清理的临时缓存。'),
          FilledButton.icon(
            onPressed:
                _busy ||
                    (_snapshot?.estimate(_selected, keepSince: _keepSince) ??
                            0) ==
                        0
                ? null
                : _clear,
            icon: const Icon(Icons.cleaning_services),
            label: Text(
              _busy
                  ? '正在清理…'
                  : '清理所选 · ${bytesToReadableString(_snapshot?.estimate(_selected, keepSince: _keepSince) ?? 0)}',
            ),
          ),
          const Divider(height: 32),
          const Text(
            '下载与本地漫画',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
          const Text('扫描可能需要一些时间。这里仅查看占用，不会删除漫画。'),
          TextButton.icon(
            onPressed: _scanningDownloads ? null : _scanDownloads,
            icon: const Icon(Icons.folder_outlined),
            label: Text(_scanningDownloads ? '正在扫描…' : '扫描漫画占用'),
          ),
          for (final book in _downloadSizes)
            ListTile(
              title: Text(book.title),
              trailing: Text(
                book.bytes == null
                    ? '无法读取'
                    : bytesToReadableString(book.bytes!),
              ),
            ),
        ],
      ),
    );
  }
}
