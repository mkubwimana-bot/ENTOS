/// Derives the 3-letter prefix for auto-generated product codes.
///
/// Rules:
/// - 3+ words: first letter of the first three words (e.g. "rubber sole original" → rso)
/// - 1 word: first three letters (e.g. "fanta" → fan)
/// - 2 words: first letter of word 1 + first two letters of word 2
String deriveProductCodePrefix(String productName) {
  final words = productName
      .trim()
      .toLowerCase()
      .split(RegExp(r'\s+'))
      .where((word) => word.isNotEmpty)
      .toList();

  String lettersOnly(String value) =>
      value.replaceAll(RegExp(r'[^a-z0-9]'), '');

  if (words.isEmpty) return 'prd';

  if (words.length >= 3) {
    return words.take(3).map((word) {
      final cleaned = lettersOnly(word);
      return cleaned.isEmpty ? 'x' : cleaned[0];
    }).join();
  }

  if (words.length == 2) {
    final first = lettersOnly(words[0]);
    final second = lettersOnly(words[1]);
    final c0 = first.isNotEmpty ? first[0] : 'x';
    final c1 = second.isNotEmpty ? second[0] : 'x';
    final c2 = second.length > 1
        ? second[1]
        : (first.length > 1 ? first[1] : 'x');
    return '$c0$c1$c2';
  }

  final word = lettersOnly(words[0]);
  if (word.length >= 3) return word.substring(0, 3);
  return word.padRight(3, 'x');
}

String formatProductCodeSuffix(int sequence) =>
    sequence.toString().padLeft(3, '0');

String buildProductCode(String prefix, int sequence) =>
    '$prefix${formatProductCodeSuffix(sequence)}';
