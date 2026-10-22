import 'dart:io';
import 'package:venera_next/network/request_scope.dart';

/// Exclusive data access is never held across a network request.
abstract interface class RecordSyncApplication {
  String get dataPath;
  String get cachePath;
  String get excludedFields;
  Future<T> exclusive<T>(Future<T> Function() action);
  Future<void> capture(Directory staging);
  Future<void> apply(
    Directory staging,
    RequestScope scope,
    void Function(void Function())? publish,
  );
  Future<void> recordSyncTime();
}
