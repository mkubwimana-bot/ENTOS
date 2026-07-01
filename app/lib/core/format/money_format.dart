/// Formats amounts in Rwanda Francs (whole numbers, no decimals).
String formatRwf(num amount) {
  final rounded = amount.round();
  final negative = rounded < 0;
  final digits = rounded.abs().toString();
  final buffer = StringBuffer(negative ? '-' : '');
  buffer.write('RWF ');
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) {
      buffer.write(',');
    }
    buffer.write(digits[i]);
  }
  return buffer.toString();
}
