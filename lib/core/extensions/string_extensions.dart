/// Utility extensions for String.
extension StringExtensions on String {
  /// Capitalize the first letter.
  String get capitalize {
    if (isEmpty) return this;
    return '${this[0].toUpperCase()}${substring(1)}';
  }

  /// Check if string is a valid email.
  bool get isValidEmail {
    return RegExp(
      r'^[\w-]+(\.[\w-]+)*@([\w-]+\.)+[a-zA-Z]{2,7}$',
    ).hasMatch(this);
  }

  /// Check if string is a valid phone number.
  bool get isValidPhoneNumber {
    return RegExp(
      r'^\+?[1-9]\d{1,14}$',
    ).hasMatch(replaceAll(RegExp(r'[\s\-()]'), ''));
  }
}
