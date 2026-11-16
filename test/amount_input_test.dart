import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlyfunds_v1/amount_input.dart';

void main() {
  group('validateAmount', () {
    test('requires a value', () {
      expect(validateAmount(null), 'Amount is required');
      expect(validateAmount(''), 'Amount is required');
      expect(validateAmount('   '), 'Amount is required');
    });

    test('rejects text that is not a usable number', () {
      for (final text in ['abc', '12abc', 'NaN', 'Infinity', '-Infinity', '1e400']) {
        expect(validateAmount(text), 'Enter a valid number', reason: text);
      }
    });

    test('rejects zero and negative amounts', () {
      expect(validateAmount('0'), 'Amount must be greater than 0');
      expect(validateAmount('0.00'), 'Amount must be greater than 0');
      expect(validateAmount('-5'), 'Amount must be greater than 0');
    });

    test('accepts positive amounts', () {
      expect(validateAmount('1'), isNull);
      expect(validateAmount('12.50'), isNull);
      expect(validateAmount(' 1000 '), isNull);
    });
  });

  group('amountInputFormatters', () {
    String format(String text) {
      var value = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
      for (final formatter in amountInputFormatters) {
        value = formatter.formatEditUpdate(TextEditingValue.empty, value);
      }
      return value.text;
    }

    test('keeps digits with up to two decimal places', () {
      expect(format('1250'), '1250');
      expect(format('12.5'), '12.5');
      expect(format('12.34'), '12.34');
    });

    test('drops letters and digits past two decimal places', () {
      expect(format('abc'), '');
      expect(format('NaN'), '');
      expect(format('12.345'), '12.34');
    });
  });
}
