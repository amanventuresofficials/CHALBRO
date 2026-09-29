import 'dart:convert';
import 'package:flutter/foundation.dart';

typedef StorageItemKey = String;

abstract class StorageBase {
  @protected
  void warn(String op, StorageItemKey key, Object? e) {
    debugPrint('[storage] $op($key) failed: $e');
  }

  @protected
  T? retrieve<T>(String? raw, T fallback) {
    if (raw == null) return fallback;
    try {
      final decoded = jsonDecode(raw);
      return decoded as T;
    } catch (e) {
      warn("retrieve", "parse error", e);
      return fallback;
    }
  }

  Future<T?> getItem<T>(String key, T fallback);
  Future<bool> setItem<T>(String key, T value);
  Future<bool> removeItem(String key);

  Future<T?> secureGet<T>(String key, T fallback);
  Future<bool> secureSet<T>(String key, T value);
  Future<bool> secureRemove(String key);
}
