/// Helpers for showing people's names without exposing more than intended.
class NameUtils {
  /// "SAHIL SHARMA" -> "Sahil". Used wherever a person is shown before they
  /// have been hired.
  static String firstName(String fullName) {
    final trimmed = fullName.trim();
    if (trimmed.isEmpty) return 'User';
    final first = trimmed.split(RegExp(r'\s+')).first;
    if (first.length == 1) return first.toUpperCase();
    return first[0].toUpperCase() + first.substring(1).toLowerCase();
  }

  /// First letter for avatar circles (never sent to a third-party service).
  static String initial(String name) {
    final trimmed = name.trim();
    return trimmed.isEmpty ? 'U' : trimmed[0].toUpperCase();
  }
}
