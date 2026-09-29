import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'storage_base.dart';

class Storage extends StorageBase {
  final FlutterSecureStorage _secureStore = const FlutterSecureStorage();

  @override
  Future<T?> getItem<T>(String key, T fallback) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(key);
      return retrieve<T>(raw, fallback);
    } catch (e) {
      warn('getItem', key, e);
      return fallback;
    }
  }

  @override
  Future<bool> setItem<T>(String key, T value) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(key, jsonEncode(value));
      return true;
    } catch (e) {
      warn('setItem', key, e);
      return false;
    }
  }

  @override
  Future<bool> removeItem(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(key);
      return true;
    } catch (e) {
      warn('removeItem', key, e);
      return false;
    }
  }

  @override
  Future<T?> secureGet<T>(String key, T fallback) async {
    try {
      final raw = await _secureStore.read(key: key);
      return retrieve<T>(raw, fallback);
    } catch (e) {
      warn('secureGet', key, e);
      return fallback;
    }
  }

  @override
  Future<bool> secureSet<T>(String key, T value) async {
    try {
      await _secureStore.write(key: key, value: jsonEncode(value));
      return true;
    } catch (e) {
      warn('secureSet', key, e);
      return false;
    }
  }

  @override
  Future<bool> secureRemove(String key) async {
    try {
      await _secureStore.delete(key: key);
      return true;
    } catch (e) {
      warn('secureRemove', key, e);
      return false;
    }
  }
}

final storage = Storage();
