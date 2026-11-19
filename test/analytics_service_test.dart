import 'package:flutter_test/flutter_test.dart';
import 'package:onlyfunds_v1/ml_analytics_service.dart';

/// Builds a transaction in the shape the Firestore fetch produces.
Map<String, dynamic> _tx(
  String type,
  double amount,
  DateTime date, {
  String category = 'Food/Grocery',
}) {
  return {
    'id': '$type-${date.toIso8601String()}-$amount',
    'type': type,
    'amount': amount,
    'category': category,
    'date': date,
    'label': 'test',
  };
}

Map<String, dynamic> _income(double amount, DateTime date) =>
    _tx('income', amount, date, category: 'Income/Allowance');

void main() {
  final service = AnalyticsService();
  // Two-thirds of the way through June 2026, past the mid-month checks.
  final now = DateTime(2026, 6, 20);

  Future<Map<String, dynamic>> predictionsFor(
      List<Map<String, dynamic>> transactions) async {
    final insights = await service.computeInsights(transactions, now: now);
    return insights['predictions'] as Map<String, dynamic>;
  }

  Future<List<Map<String, dynamic>>> alertsFor(
    List<Map<String, dynamic>> transactions, {
    DateTime? at,
  }) async {
    final insights =
        await service.computeInsights(transactions, now: at ?? now);
    return (insights['alerts'] as List).cast<Map<String, dynamic>>();
  }

  group('monthly expense forecast', () {
    test('extends a steady monthly increase to next month', () async {
      final predictions = await predictionsFor([
        _tx('expense', 1000, DateTime(2026, 2, 10)),
        _tx('expense', 1100, DateTime(2026, 3, 10)),
        // Several expenses in one month are added together.
        _tx('expense', 700, DateTime(2026, 4, 5)),
        _tx('expense', 500, DateTime(2026, 4, 25)),
        _tx('expense', 1300, DateTime(2026, 5, 10)),
        // The current month is still in progress and is left out.
        _tx('expense', 9999, DateTime(2026, 6, 2)),
      ]);

      // February to May total 1000, 1100, 1200, and 1300, so the line
      // reaches 1500 in July, the month after June.
      expect(predictions['predictedAmount'], closeTo(1500, 1));
      expect(predictions['monthsUsed'], 4);
      expect(predictions['nextMonth'], DateTime(2026, 7));
      expect(predictions['trend'], 'stable');
    });

    test('ignores income when forecasting expenses', () async {
      final predictions = await predictionsFor([
        _income(50000, DateTime(2026, 3, 1)),
        _tx('expense', 1000, DateTime(2026, 3, 10)),
        _tx('expense', 1000, DateTime(2026, 4, 10)),
        _tx('expense', 1000, DateTime(2026, 5, 10)),
      ]);

      expect(predictions['predictedAmount'], closeTo(1000, 1));
    });

    test('needs three completed months of expenses', () async {
      final predictions = await predictionsFor([
        _tx('expense', 1000, DateTime(2026, 4, 10)),
        _tx('expense', 1100, DateTime(2026, 5, 10)),
        _tx('expense', 500, DateTime(2026, 6, 10)),
      ]);

      expect(predictions['predictedAmount'], isNull);
      expect(predictions['message'], contains('3 full months'));
    });

    test('gives no forecast when the trend falls below zero', () async {
      final predictions = await predictionsFor([
        _tx('expense', 3000, DateTime(2026, 3, 10)),
        _tx('expense', 2000, DateTime(2026, 4, 10)),
        _tx('expense', 1000, DateTime(2026, 5, 10)),
      ]);

      expect(predictions['predictedAmount'], isNull);
      expect(predictions['trend'], 'decreasing');
    });
  });

  group('alerts', () {
    test('flags a category already well above its usual month', () async {
      final alerts = await alertsFor([
        _income(10000, DateTime(2026, 3, 1)),
        _tx('expense', 1000, DateTime(2026, 3, 10)),
        _income(10000, DateTime(2026, 4, 1)),
        _tx('expense', 1000, DateTime(2026, 4, 10)),
        _income(10000, DateTime(2026, 5, 1)),
        _tx('expense', 1000, DateTime(2026, 5, 10)),
        _income(10000, DateTime(2026, 6, 1)),
        _tx('expense', 2000, DateTime(2026, 6, 5)),
      ]);

      final spike = alerts.singleWhere((a) => a['type'] == 'spending_spike');
      expect(spike['category'], 'Food/Grocery');
      expect(spike['amount'], closeTo(1000, 0.001));
      expect(alerts.where((a) => a['type'] == 'income_drop'), isEmpty);
    });

    test('does not flag spending in line with earlier months', () async {
      final alerts = await alertsFor([
        _tx('expense', 1000, DateTime(2026, 4, 10)),
        _tx('expense', 1000, DateTime(2026, 5, 10)),
        _tx('expense', 1200, DateTime(2026, 6, 5)),
      ]);

      expect(alerts.where((a) => a['type'] == 'spending_spike'), isEmpty);
    });

    test('flags income well below the usual monthly income', () async {
      final alerts = await alertsFor([
        _income(10000, DateTime(2026, 3, 1)),
        _income(10000, DateTime(2026, 4, 1)),
        _income(10000, DateTime(2026, 5, 1)),
        _income(4000, DateTime(2026, 6, 1)),
      ]);

      final drop = alerts.singleWhere((a) => a['type'] == 'income_drop');
      expect(drop['dropPercentage'], 60);
    });

    test('waits until mid-month before flagging an income drop', () async {
      final alerts = await alertsFor([
        _income(10000, DateTime(2026, 4, 1)),
        _income(10000, DateTime(2026, 5, 1)),
        _income(4000, DateTime(2026, 6, 1)),
      ], at: DateTime(2026, 6, 10));

      expect(alerts.where((a) => a['type'] == 'income_drop'), isEmpty);
    });
  });

  group('savings transfers', () {
    test('count as saved, not spent, in the summary', () async {
      final insights = await service.computeInsights([
        _income(10000, DateTime(2026, 6, 1)),
        _tx('expense', 500, DateTime(2026, 6, 2)),
        _tx('expense', 200, DateTime(2026, 6, 3), category: 'Transportation'),
        // A deposit made on the Savings page.
        _tx('expense', 1000, DateTime(2026, 6, 4), category: 'Funds'),
      ], now: now);
      final metrics = insights['basicMetrics'] as Map<String, dynamic>;
      final breakdown = insights['categoryBreakdown'] as Map<String, double>;

      expect(metrics['totalExpenses'], closeTo(700, 0.001));
      expect(metrics['savings'], closeTo(9300, 0.001));
      expect(metrics['savingsTransfers'], closeTo(1000, 0.001));
      expect(metrics['savingsRate'], closeTo(93, 0.001));
      expect(breakdown.keys, isNot(contains('Funds')));
    });

    test('include expenses recorded in the Savings category', () async {
      final insights = await service.computeInsights([
        _income(5000, DateTime(2026, 6, 1)),
        _tx('expense', 1000, DateTime(2026, 6, 2)),
        _tx('expense', 500, DateTime(2026, 6, 3), category: 'Savings'),
      ], now: now);
      final metrics = insights['basicMetrics'] as Map<String, dynamic>;

      expect(metrics['totalExpenses'], closeTo(1000, 0.001));
      expect(metrics['savings'], closeTo(4000, 0.001));
      expect(metrics['savingsTransfers'], closeTo(500, 0.001));
    });
  });

  test('returns the empty state when there are no transactions', () async {
    final insights = await service.computeInsights([], now: now);
    final predictions = insights['predictions'] as Map<String, dynamic>;

    expect(predictions['message'], 'Add more transactions to get predictions');
    expect(insights['alerts'], isEmpty);
  });
}
