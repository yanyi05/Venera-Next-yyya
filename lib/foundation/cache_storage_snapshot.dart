import 'dart:convert';

class CacheStorageEntry {
  const CacheStorageEntry({
    required this.key,
    required this.directory,
    required this.name,
    required this.expires,
    required this.bytes,
    required this.group,
  });
  final String key, directory, name, group;
  final int expires, bytes;
  DateTime get lastUsed => DateTime.fromMillisecondsSinceEpoch(
    expires,
  ).subtract(const Duration(days: 7));
  List<String>? get comic {
    try {
      final value = jsonDecode(group);
      if (value is List &&
          value.length == 2 &&
          value.every((v) => v is String)) {
        return value.cast<String>();
      }
    } catch (_) {}
    return null;
  }
}

class CacheStorageSnapshot {
  CacheStorageSnapshot(Iterable<CacheStorageEntry> entries)
    : entries = List.unmodifiable(entries);
  final List<CacheStorageEntry> entries;
  int estimate(Set<String> groups, {DateTime? keepSince}) => eligible(
    groups,
    keepSince: keepSince,
  ).fold(0, (total, entry) => total + entry.bytes);
  Iterable<CacheStorageEntry> eligible(
    Set<String> groups, {
    DateTime? keepSince,
  }) => entries.where(
    (entry) =>
        groups.contains(entry.group) &&
        (keepSince == null || entry.lastUsed.isBefore(keepSince)),
  );
}
