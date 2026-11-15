import 'package:flutter/services.dart';

// Shared rules for peso amount fields.
//
// `double.tryParse` accepts "NaN", "Infinity", and exponents such as
// "1e400". None of those is a usable amount, and once saved they would
// corrupt the month's running totals, so amount fields use these helpers
// instead of a bare parse.

/// Limits typing and pasting to digits with at most one decimal point and
/// two decimal places.
final List<TextInputFormatter> amountInputFormatters = [
  FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,2}')),
];

/// Form validator for amount fields: required, numeric, finite, above zero.
String? validateAmount(String? text) {
  final trimmed = (text ?? '').trim();
  if (trimmed.isEmpty) {
    return "Amount is required";
  }
  final value = double.tryParse(trimmed);
  if (value == null || !value.isFinite) {
    return "Enter a valid number";
  }
  if (value <= 0) {
    return "Amount must be greater than 0";
  }
  return null;
}
