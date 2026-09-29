// lib/utils/language_provider.dart
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'app_strings.dart';

const String _kLangKey = 'app_language';
const String _kFirstRunKey = 'language_first_run_done';

class LanguageProvider extends ChangeNotifier {
  String _lang = 'en';
  bool _firstRunDone = true;

  String get currentLang => _lang;
  bool get isHindi => _lang == 'hi';
  bool get isFirstRun => !_firstRunDone;
  AppStrings get strings => _lang == 'hi' ? AppStrings.hi : AppStrings.en;

  LanguageProvider() {
    _load();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    _lang = prefs.getString(_kLangKey) ?? 'en';
    _firstRunDone = prefs.getBool(_kFirstRunKey) ?? false;
    notifyListeners();
  }

  Future<void> completeFirstRun(String lang) async {
    _lang = lang;
    _firstRunDone = true;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, lang);
    await prefs.setBool(_kFirstRunKey, true);
    notifyListeners();
  }

  Future<void> setLanguage(String lang) async {
    if (_lang == lang) return;
    _lang = lang;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kLangKey, lang);
    notifyListeners();
  }
}
