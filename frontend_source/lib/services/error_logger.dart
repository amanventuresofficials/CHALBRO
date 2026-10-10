import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../utils/app_info.dart';

/// Records problems so the admin panel's "Errors & Health" screen can show them.
///
/// Three categories (what the owner asked to see):
///   app       crashes and unexpected exceptions in the app itself
///   payment   anything that goes wrong while paying or being paid
///   database  failed reads/writes/uploads (Firestore, Storage)
///
/// Design rules:
///  * Never throws and never blocks the UI. Logging is fire-and-forget; if it
///    fails (offline, rules, anything) the failure is swallowed.
///  * Never logs personal data: only the user's uid, never names, phone numbers or
///    e-mails. Obvious e-mails/long numbers inside messages are masked.
///  * Never floods: a per-session cap, and the same problem is sent at most once
///    per [_repeatWindow]. The admin panel groups the rest by `fingerprint`.
///  * Only signed-in users can write (Firestore rules), so errors before sign-in
///    are not recorded.
class ErrorLogger {
  ErrorLogger._();
  static final ErrorLogger instance = ErrorLogger._();

  static const int _sessionCap = 25;
  static const Duration _repeatWindow = Duration(minutes: 10);
  static const int _maxMessage = 500;
  static const int _maxStack = 3500;
  static const int _maxContext = 160;

  int _sent = 0;
  bool _inside = false;
  final Map<String, DateTime> _lastSent = {};

  /// Hooks Flutter's global handlers. Call once, right after Firebase.initializeApp.
  void install() {
    final previousFlutterHandler = FlutterError.onError;
    FlutterError.onError = (FlutterErrorDetails details) {
      // Keep the normal behaviour (console output in debug builds).
      if (previousFlutterHandler != null) {
        previousFlutterHandler(details);
      } else {
        FlutterError.presentError(details);
      }
      log(
        error: details.exception,
        stack: details.stack,
        context: details.context?.toDescription() ?? details.library ?? 'Flutter framework',
      );
    };

    final previousPlatformHandler = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      log(error: error, stack: stack, context: 'Uncaught error');
      if (previousPlatformHandler != null) return previousPlatformHandler(error, stack);
      return true; // handled: do not crash the app
    };
  }

  /// Records [error]. [category] is 'app' | 'payment' | 'database'; the global
  /// handlers pass 'app' and the classifier moves Firestore/Storage/Functions
  /// exceptions to the right category.
  Future<void> log({
    required Object error,
    StackTrace? stack,
    String category = 'app',
    String severity = 'error', // 'fatal' | 'error' | 'warning'
    String context = '',
    String? taskId,
    Map<String, String>? extra,
  }) async {
    if (_inside) return; // never log while logging
    _inside = true;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return; // rules only allow signed-in users
      if (_isNoise(error)) return;
      if (_sent >= _sessionCap) return;

      final String type = _typeOf(error);
      final String cat = _classify(category, error);
      final String message = _clean(_messageOf(error), _maxMessage);
      final String fp = fingerprint(cat, type, message, stack, context: context);

      final now = DateTime.now();
      final last = _lastSent[fp];
      if (last != null && now.difference(last) < _repeatWindow) return;
      _lastSent[fp] = now;
      _sent++;

      final data = <String, dynamic>{
        'category': cat,
        'severity': severity,
        'message': message,
        'errorType': _clean(type, 80),
        'fingerprint': fp,
        'context': _clean(context, _maxContext),
        'uid': user.uid,
        'appVersion': AppInfo.full,
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'status': 'open',
        'source': 'client',
        'createdAt': FieldValue.serverTimestamp(),
        if (stack != null) 'stack': _clean(stack.toString(), _maxStack),
        if (taskId != null && taskId.isNotEmpty) 'taskId': taskId,
        if (extra != null && extra.isNotEmpty)
          'extra': {
            for (final e in extra.entries.take(8)) _clean(e.key, 40): _clean(e.value, 160),
          },
      };

      // Fire and forget: offline writes queue up and the future would only finish
      // once the server answers, so it must never be awaited by UI code.
      unawaited(FirebaseFirestore.instance
          .collection('errorLogs')
          .add(data)
          .then<void>((_) {}, onError: (_) {}));
    } catch (_) {
      // Logging must never be the thing that breaks the app.
    } finally {
      _inside = false;
    }
  }

  // ─── Classification ────────────────────────────────────────────────────────

  static String _classify(String requested, Object error) {
    if (requested != 'app') return requested;
    if (error is FirebaseException) {
      final plugin = error.plugin;
      if (plugin == 'cloud_firestore' || plugin == 'firebase_storage') return 'database';
      if (plugin == 'cloud_functions') return 'payment'; // only payments use callables
    }
    if (error is FirebaseFunctionsException) return 'payment';
    return requested;
  }

  static String _typeOf(Object error) {
    if (error is FirebaseException) return '${error.plugin}/${error.code}';
    return error.runtimeType.toString();
  }

  static String _messageOf(Object error) {
    if (error is FirebaseException) return error.message ?? error.code;
    return error.toString();
  }

  /// Connectivity problems and user-cancelled flows are not bugs; recording them
  /// would only bury the real errors.
  static bool _isNoise(Object error) {
    final s = '${_typeOf(error)} ${_messageOf(error)}'.toLowerCase();
    const quiet = [
      'socketexception',
      'failed host lookup',
      'network-request-failed',
      'network_error',
      'sign_in_canceled',
      'sign_in_failed: 12501',
      'user-cancelled',
      'cloud_firestore/unavailable',
      'clientexception: connection',
      'xmlhttprequest error', // browser reports every offline fetch this way
      'imageprovider', // broken remote image URLs
      'networkimageloadexception',
    ];
    return quiet.any(s.contains);
  }

  // ─── Fingerprint & cleaning ────────────────────────────────────────────────

  /// Same underlying problem -> same fingerprint, whatever ids or numbers the
  /// message happens to contain. The admin panel groups by this.
  @visibleForTesting
  static String fingerprint(String category, String type, String message, StackTrace? stack, {String context = ''}) {
    final normalized = message
        .toLowerCase()
        .replaceAll(RegExp(r'https?://\S+'), '<url>')
        .replaceAll(RegExp(r'[0-9a-z_\-]{14,}'), '<id>') // document ids, tokens
        .replaceAll(RegExp(r'\d+'), '0');
    // The same message in two different places (say "permission denied" on the home
    // screen and in the wallet) is two different problems, so where it happened
    // is part of the fingerprint.
    return _fnv1a('$category|$type|$normalized|${_firstFrame(stack)}|${context.toLowerCase()}');
  }

  static String _firstFrame(StackTrace? stack) {
    if (stack == null) return '';
    for (final line in stack.toString().split('\n')) {
      if (line.contains('package:chalbroo/')) {
        // keep "Class.method (file.dart" and drop line/column numbers
        return line.replaceAll(RegExp(r'^#\d+\s+'), '').replaceAll(RegExp(r':\d+:\d+\)?$'), '').trim();
      }
    }
    final lines = stack.toString().split('\n').where((l) => l.trim().isNotEmpty);
    return lines.isEmpty ? '' : lines.first.replaceAll(RegExp(r'\d+'), '0');
  }

  static String _fnv1a(String input) {
    var hash = 0x811c9dc5;
    for (final unit in input.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0xffffffff;
    }
    return hash.toRadixString(16).padLeft(8, '0');
  }

  /// Truncates and masks e-mail addresses and long digit runs (phone numbers).
  static String _clean(String text, int max) {
    var s = text
        .replaceAll(RegExp(r'[\w.+\-]+@[\w\-]+(\.[\w\-]+)+'), '<email>')
        .replaceAll(RegExp(r'\+?\d[\d\s\-]{8,}\d'), '<number>');
    if (s.length > max) s = '${s.substring(0, max - 1)}…';
    return s;
  }
}

/// `stream.logErrors('Home: open tasks')` records any error the stream raises and
/// passes it on unchanged, so screens keep behaving exactly as before.
///
/// Built on a StreamController rather than `transform`: a stream declared as
/// Stream<QuerySnapshot<Object?>> really carries QuerySnapshot<Map<String, dynamic>>,
/// and any typed StreamTransformer is rejected at run time in that case (the Home
/// screen crashed with "_StreamHandlerTransformer ... is not a subtype of ...").
extension LogStreamErrors<T> on Stream<T> {
  Stream<T> logErrors(String context, {String category = 'database'}) {
    final Stream<T> source = this;
    late final StreamController<T> controller;
    StreamSubscription<T>? subscription;

    void start() {
      subscription = source.listen(
        controller.add,
        onError: (Object error, StackTrace stack) {
          ErrorLogger.instance.log(error: error, stack: stack, category: category, context: context);
          controller.addError(error, stack);
        },
        onDone: controller.close,
      );
    }

    Future<void>? stop() {
      final s = subscription;
      subscription = null;
      return s?.cancel();
    }

    controller = source.isBroadcast
        ? StreamController<T>.broadcast(onListen: start, onCancel: stop)
        : StreamController<T>(
            onListen: start,
            onPause: () => subscription?.pause(),
            onResume: () => subscription?.resume(),
            onCancel: stop,
          );
    return controller.stream;
  }
}
