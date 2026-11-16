import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:onlyfunds_v1/widgets/widgets.dart';

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  group('TransactionCard', () {
    testWidgets('shows income as a green, positive peso amount', (tester) async {
      await tester.pumpWidget(_host(const TransactionCard(
        label: 'Allowance',
        date: null,
        amount: 1500,
        type: 'income',
        category: 'Income/Allowance',
      )));

      expect(find.text('Allowance'), findsOneWidget);
      final amount = tester.widget<Text>(find.text('+₱1,500.00'));
      expect(amount.style?.color, Colors.green);
      expect(find.byIcon(Icons.attach_money_rounded), findsOneWidget);
    });

    testWidgets('shows an expense as a red, negative peso amount', (tester) async {
      await tester.pumpWidget(_host(TransactionCard(
        label: 'Groceries',
        date: DateTime.now().subtract(const Duration(days: 3)),
        amount: 250.5,
        type: 'expense',
        category: 'Food/Grocery',
      )));

      final amount = tester.widget<Text>(find.text('-₱250.50'));
      expect(amount.style?.color, Colors.red);
      expect(find.text('3 days ago'), findsOneWidget);
      expect(find.byIcon(Icons.restaurant_rounded), findsOneWidget);
    });
  });

  group('Button', () {
    testWidgets('calls onPressed when tapped', (tester) async {
      var taps = 0;
      await tester.pumpWidget(_host(Button(text: 'Save', onPressed: () => taps++)));

      await tester.tap(find.text('Save'));

      expect(taps, 1);
    });

    testWidgets('is disabled when onPressed is null', (tester) async {
      await tester.pumpWidget(_host(const Button(text: 'Save', onPressed: null)));

      final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
      expect(button.enabled, isFalse);
    });
  });
}
