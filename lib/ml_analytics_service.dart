// services/analytics_service.dart
import 'dart:math' show sqrt;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart' show debugPrint, visibleForTesting;
import 'package:ml_algo/ml_algo.dart';
import 'package:ml_dataframe/ml_dataframe.dart';

class AnalyticsService {
  // Resolved on first use, so the calculations below can run in tests
  // without initializing Firebase.
  late final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  
  // Alert Thresholds
  static const double budgetWarning = 0.75;
  static const double budgetCritical = 0.90;
  static const double savingsGoalProgress = 0.5;
  static const double spendingSpike = 2.0;
  static const double incomeDrop = 0.3;

  /// Completed months of expenses needed before a monthly forecast is made.
  static const int minForecastMonths = 3;

  // Priority categories for special focus
  static const List<String> priorityCategories = [
    "Food/Grocery",
    "Transportation", 
    "Utility Bills",
    "Subscriptions",
    "Shopping/Other"
  ];

  /// Expense categories that move money into savings instead of spending it.
  /// Deposits made on the Savings page are stored as expenses in the "Funds"
  /// category, and the dashboard offers a "Savings" category for money set
  /// aside. Reports count both as saved, not spent.
  static const Set<String> savingsCategories = {'Funds', 'Savings'};

  /// Get comprehensive financial insights for reports
  Future<Map<String, dynamic>> getFinancialInsights(String userId) async {
    final transactions = await _getHistoricalTransactions(userId, months: 6);
    return computeInsights(transactions);
  }

  /// Calculates the report insights from already-fetched [transactions].
  ///
  /// Each transaction is a map with `type` ("income" or "expense"),
  /// `amount`, `category`, and `date` (a [DateTime]), as produced by the
  /// Firestore fetch. Kept apart from that fetch so it can be tested without
  /// Firebase. [now] sets the current date and defaults to the real one.
  @visibleForTesting
  Future<Map<String, dynamic>> computeInsights(
    List<Map<String, dynamic>> transactions, {
    DateTime? now,
  }) async {
    if (transactions.isEmpty) {
      return _getEmptyInsights();
    }
    final today = now ?? DateTime.now();

    final basicInsights = _getBasicFinancialMetrics(transactions);
    final predictions = await _predictFutureExpenses(transactions, today);
    final recommendations = _getPersonalizedRecommendations(transactions, basicInsights);
    final alerts = _generateRealTimeAlerts(transactions, today);

    return {
      'basicMetrics': basicInsights,
      'predictions': predictions,
      'recommendations': recommendations,
      'alerts': alerts,
      'spendingTrends': _analyzeSpendingTrends(transactions),
      'categoryBreakdown': _getCategoryBreakdown(transactions),
      'savingsAnalysis': _analyzeSavingsPattern(transactions, basicInsights),
    };
  }

  /// ML: forecast of next calendar month's total expenses.
  ///
  /// Fits a linear regression to the expense totals of completed months and
  /// extends the line one month past the current one. The current month is
  /// left out of the fit because its total is still growing, and savings
  /// transfers are left out because they are not spending.
  Future<Map<String, dynamic>> _predictFutureExpenses(
      List<Map<String, dynamic>> transactions, DateTime now) async {
    try {
      final currentMonthNumber = _monthNumber(now);

      // Spending total for each completed month, keyed by month number.
      final totalsByMonth = <int, double>{};
      for (final transaction in transactions) {
        if (!_isSpending(transaction)) continue;
        final monthNumber = _monthNumber(transaction['date'] as DateTime);
        if (monthNumber >= currentMonthNumber) continue;
        final amount = _safeConvertToDouble(transaction['amount']);
        totalsByMonth.update(
          monthNumber,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
      }

      if (totalsByMonth.length < minForecastMonths) {
        return {
          'predictedAmount': null,
          'confidence': 0.0,
          'message': 'Need at least $minForecastMonths full months of expenses for a monthly forecast',
        };
      }

      // Oldest month first. The feature is months since the oldest month.
      final monthNumbers = totalsByMonth.keys.toList()..sort();
      final originMonth = monthNumbers.first;
      final List<double> monthlyTotals =
          monthNumbers.map((monthNumber) => totalsByMonth[monthNumber]!).toList();
      final List<List<double>> monthlyData = [
        for (final monthNumber in monthNumbers)
          [(monthNumber - originMonth).toDouble(), totalsByMonth[monthNumber]!],
      ];

      // headerExists must be false: by default DataFrame treats the first row
      // as column names and drops it from the data.
      final dataframe = DataFrame(
        monthlyData,
        headerExists: false,
        header: ['month', 'total'],
      );
      
      // Train linear regression model
      final model = LinearRegressor(
        dataframe,
        'total', // target column
        fitIntercept: true,
      );
      
      // Predict the calendar month after the current one
      final nextMonth = DateTime(now.year, now.month + 1);
      
      final predictionData = DataFrame(
        [[(currentMonthNumber + 1 - originMonth).toDouble()]],
        headerExists: false,
        header: ['month'],
      );
      
      final prediction = model.predict(predictionData);
      
      // Extract the prediction value safely
      double predictedAmount = 0.0;
      if (prediction.rows.isNotEmpty && prediction.rows.first.isNotEmpty) {
        predictedAmount = _safeConvertToDouble(prediction.rows.first.first);
      }
      final hasForecast = predictedAmount.isFinite && predictedAmount > 0;

      return {
        'predictedAmount': hasForecast ? predictedAmount : null,
        'nextMonth': nextMonth,
        'monthsUsed': monthlyTotals.length,
        'confidence': _calculatePredictionConfidence(monthlyTotals),
        'trend': _calculateExpenseTrend(monthlyTotals),
        if (!hasForecast) 'message': 'No forecast is available for the current data',
      };
    } catch (e) {
      debugPrint('ML Prediction error: $e');
      return {
        'error': 'Prediction unavailable',
        'message': 'Add more expense data to enable predictions'
      };
    }
  }

  /// Running month number, so consecutive calendar months differ by one.
  int _monthNumber(DateTime date) => date.year * 12 + date.month - 1;

  /// ML: Personalized Budget Recommendations
  Map<String, dynamic> _getPersonalizedRecommendations(
    List<Map<String, dynamic>> transactions, 
    Map<String, dynamic> metrics
  ) {
    final categorySpending = _getCategorySpending(transactions);
    final savingsRate = _safeConvertToDouble(metrics['savingsRate']);
    final totalIncome = _safeConvertToDouble(metrics['totalIncome']);

    final recommendations = <String, Map<String, dynamic>>{};
    String overallAdvice = '';

    // Analyze each priority category
    for (final category in priorityCategories) {
      final spent = _safeConvertToDouble(categorySpending[category]);
      final percentage = totalIncome > 0 ? (spent / totalIncome) * 100 : 0.0;
      
      String advice;
      double suggestedBudget;

      if (percentage > 30) {
        advice = 'High spending area. Consider reducing by 15-20%.';
        suggestedBudget = spent * 0.8; // 20% reduction
      } else if (percentage > 15) {
        advice = 'Moderate spending. Look for optimization opportunities.';
        suggestedBudget = spent * 0.9; // 10% reduction
      } else {
        advice = 'Well controlled. Maintain current level.';
        suggestedBudget = spent;
      }

      recommendations[category] = {
        'currentSpending': spent,
        'percentage': percentage,
        'advice': advice,
        'suggestedBudget': suggestedBudget,
        'potentialSavings': spent - suggestedBudget,
      };
    }

    // Overall financial advice based on savings rate
    if (savingsRate > 20) {
      overallAdvice = 'Excellent savings rate! Consider increasing investments.';
    } else if (savingsRate > 10) {
      overallAdvice = 'Good financial health. Focus on debt reduction if any.';
    } else if (savingsRate > 0) {
      overallAdvice = 'Positive savings. Look for areas to optimize spending.';
    } else {
      overallAdvice = 'Spending exceeds income. Review essential vs. discretionary expenses.';
    }

    return {
      'categoryRecommendations': recommendations,
      'overallAdvice': overallAdvice,
      'savingsRate': savingsRate,
    };
  }

  /// Real-time Alert Generation
  ///
  /// Every alert compares the current calendar month against the monthly
  /// average of the earlier months in the fetched history, so both sides of
  /// each comparison cover the same length of time.
  List<Map<String, dynamic>> _generateRealTimeAlerts(
      List<Map<String, dynamic>> transactions, DateTime currentDate) {
    final alerts = <Map<String, dynamic>>[];
    final daysInMonth = DateTime(currentDate.year, currentDate.month + 1, 0).day;
    final monthProgress = currentDate.day / daysInMonth;
    final currentMonthKey = _monthKey(currentDate);

    final currentMonth = <Map<String, dynamic>>[];
    final earlierMonths = <Map<String, dynamic>>[];
    final earlierMonthKeys = <String>{};
    for (final transaction in transactions) {
      final key = _monthKey(transaction['date'] as DateTime);
      if (key == currentMonthKey) {
        currentMonth.add(transaction);
      } else {
        earlierMonths.add(transaction);
        earlierMonthKeys.add(key);
      }
    }
    final earlierMonthCount = earlierMonthKeys.length;

    final currentIncome = _sumByType(currentMonth, 'income');
    // Money moved into savings counts as saved, so only spending is subtracted.
    final currentSavings =
        currentIncome - _sumAmounts(currentMonth.where(_isSpending));

    // Spending spike alerts: this month's spending in a category is already
    // well above what a whole month usually costs. Needs earlier history.
    if (earlierMonthCount > 0) {
      final currentSpending = _getCategorySpending(currentMonth);
      final earlierSpending = _getCategorySpending(earlierMonths);

      for (final category in priorityCategories) {
        final spent = currentSpending[category] ?? 0.0;
        final typicalMonth = (earlierSpending[category] ?? 0.0) / earlierMonthCount;

        if (typicalMonth > 0 && spent > typicalMonth * 1.5) {
          alerts.add({
            'type': 'spending_spike',
            'category': category,
            'message': 'Unusual spending spike in $category detected',
            'severity': 'high',
            'amount': spent - typicalMonth,
          });
        }
      }
    }

    // Savings progress alert, checked once the month is more than half over
    if (currentIncome > 0 && monthProgress > savingsGoalProgress) {
      final savingsTarget = (currentIncome * 0.2); // 20% savings target
      if (currentSavings < savingsTarget * savingsGoalProgress) {
        alerts.add({
          'type': 'savings_alert',
          'message': 'You\'re behind on savings goals for this month',
          'severity': 'medium',
          'needed': savingsTarget - currentSavings,
        });
      }
    }

    // Income drop alert: this month against the earlier monthly average.
    // Also waits for mid-month, since income often arrives partway through.
    final typicalIncome = earlierMonthCount > 0
        ? _sumByType(earlierMonths, 'income') / earlierMonthCount
        : 0.0;
    if (typicalIncome > 0 &&
        monthProgress > 0.5 &&
        currentIncome < typicalIncome * (1 - incomeDrop)) {
      alerts.add({
        'type': 'income_drop',
        'message': 'Income is lower than usual this month',
        'severity': 'medium',
        'dropPercentage': ((typicalIncome - currentIncome) / typicalIncome * 100).round(),
      });
    }

    return alerts;
  }

  String _monthKey(DateTime date) =>
      "${date.year}-${date.month.toString().padLeft(2, '0')}";

  double _sumByType(List<Map<String, dynamic>> transactions, String type) {
    return transactions
        .where((t) => _safeConvertToString(t['type']) == type)
        .fold(0.0, (sum, item) => sum + _safeConvertToDouble(item['amount']));
  }

  /// Whether [transaction] moves money into savings; see [savingsCategories].
  bool _isSavingsTransfer(Map<String, dynamic> transaction) =>
      _safeConvertToString(transaction['type']) == 'expense' &&
      savingsCategories.contains(_safeConvertToString(transaction['category']));

  /// Whether [transaction] is spending: an expense that is not a savings
  /// transfer.
  bool _isSpending(Map<String, dynamic> transaction) =>
      _safeConvertToString(transaction['type']) == 'expense' &&
      !_isSavingsTransfer(transaction);

  double _sumAmounts(Iterable<Map<String, dynamic>> transactions) =>
      transactions.fold(
          0.0, (sum, item) => sum + _safeConvertToDouble(item['amount']));

  /// FIXED: Proper type handling for Firestore data
  Future<List<Map<String, dynamic>>> _getHistoricalTransactions(String userId, {int months = 6}) async {
    final List<Map<String, dynamic>> allTransactions = [];
    final now = DateTime.now();
    
    for (int i = 0; i < months; i++) {
      final date = DateTime(now.year, now.month - i);
      final monthId = "${date.year}-${date.month.toString().padLeft(2, '0')}";
      
      try {
        final querySnapshot = await _firestore
            .collection("users")
            .doc(userId)
            .collection("monthly_records")
            .doc(monthId)
            .collection("transactions")
            .get();

        for (final doc in querySnapshot.docs) {
          final data = doc.data();
          
          // SAFE TYPE CONVERSION - don't cast directly
          final transaction = {
            'id': doc.id,
            'amount': _safeConvertToDouble(data['amount']),
            'category': _safeConvertToString(data['category']),
            'type': _safeConvertToString(data['type']),
            'date': data['date_added'] is Timestamp 
                ? (data['date_added'] as Timestamp).toDate()
                : DateTime.now(),
            'label': _safeConvertToString(data['label']),
          };
          
          allTransactions.add(transaction);
        }
      } catch (e) {
        debugPrint('Error fetching transactions for $monthId: $e');
      }
    }

    return allTransactions;
  }

  /// FIXED: Safe type conversion methods
  double _safeConvertToDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    if (value is num) return value.toDouble();
    return 0.0;
  }

  String _safeConvertToString(dynamic value) {
    if (value == null) return '';
    if (value is String) return value;
    return value.toString();
  }

  /// FIXED: Safe map access in basic metrics
  Map<String, dynamic> _getBasicFinancialMetrics(List<Map<String, dynamic>> transactions) {
    // Money moved into savings is not spending: it is left out of expenses,
    // so it counts toward savings and the savings rate.
    final spending = transactions.where(_isSpending).toList();
    final income = transactions
        .where((t) => _safeConvertToString(t['type']) == 'income')
        .toList();

    final totalExpenses = _sumAmounts(spending);
    final totalIncome = _sumAmounts(income);
    final savings = totalIncome - totalExpenses;
    final savingsRate = totalIncome > 0 ? (savings / totalIncome) * 100 : 0;

    return {
      'totalExpenses': totalExpenses,
      'totalIncome': totalIncome,
      'savings': savings,
      'savingsTransfers': _sumAmounts(transactions.where(_isSavingsTransfer)),
      'savingsRate': savingsRate,
      'categorySpending': _getCategorySpending(transactions),
      'averageMonthlyExpense': _calculateAverageMonthly(spending),
      'averageMonthlyIncome': _calculateAverageMonthly(income),
      'transactionCount': transactions.length,
    };
  }

  /// FIXED: Safe category spending calculation
  Map<String, double> _getCategorySpending(List<Map<String, dynamic>> transactions) {
    final Map<String, double> categoryMap = {};
    // Savings transfers are not spending, so they are left out.
    final expenses = transactions.where(_isSpending);
    
    for (final expense in expenses) {
      final category = _safeConvertToString(expense['category']);
      final amount = _safeConvertToDouble(expense['amount']);
      
      categoryMap.update(
        category,
        (value) => value + amount,
        ifAbsent: () => amount,
      );
    }
    
    return categoryMap;
  }

  double _calculateAverageMonthly(List<Map<String, dynamic>> transactions) {
    if (transactions.isEmpty) return 0;
    
    final dates = transactions.map((t) => t['date'] as DateTime? ?? DateTime.now()).toList();
    final firstDate = dates.reduce((a, b) => a.isBefore(b) ? a : b);
    final lastDate = dates.reduce((a, b) => a.isAfter(b) ? a : b);
    final months = (lastDate.difference(firstDate).inDays / 30).ceil();
    
    final total = transactions.fold(0.0, (sum, item) => sum + _safeConvertToDouble(item['amount']));
    return total / (months > 0 ? months : 1);
  }

  /// Heuristic confidence for the monthly forecast: more months of history
  /// and steadier monthly totals score higher. It is not a measured accuracy.
  double _calculatePredictionConfidence(List<double> monthlyTotals) {
    if (monthlyTotals.length < 2) return 0.0;

    // History score is full once the six-month window is covered.
    final historyScore = (monthlyTotals.length / 6).clamp(0.0, 1.0);

    final mean = monthlyTotals.reduce((a, b) => a + b) / monthlyTotals.length;
    if (mean <= 0) return 0.0;
    final variance = monthlyTotals.map((a) => (a - mean) * (a - mean)).reduce((a, b) => a + b) / monthlyTotals.length;
    // Spread relative to a typical month (coefficient of variation).
    final consistency = (1.0 - sqrt(variance) / mean).clamp(0.0, 1.0);

    return (historyScore * 0.6 + consistency * 0.4).clamp(0.0, 1.0);
  }

  /// Direction of the two most recent completed months, oldest first.
  String _calculateExpenseTrend(List<double> monthlyTotals) {
    if (monthlyTotals.length < 2) return 'stable';

    final recent = monthlyTotals[monthlyTotals.length - 1];
    final previous = monthlyTotals[monthlyTotals.length - 2];

    if (previous == 0) return 'stable';

    final change = (recent - previous) / previous;

    if (change > 0.1) return 'increasing';
    if (change < -0.1) return 'decreasing';
    return 'stable';
  }

  Map<String, dynamic> _analyzeSpendingTrends(List<Map<String, dynamic>> transactions) {
    // Group by month and analyze trends
    final monthlyData = <String, double>{};
    
    for (final transaction in transactions) {
      final date = transaction['date'] as DateTime;
      final monthKey = "${date.year}-${date.month.toString().padLeft(2, '0')}";
      
      if (_isSpending(transaction)) {
        final amount = _safeConvertToDouble(transaction['amount']);
        monthlyData.update(
          monthKey,
          (value) => value + amount,
          ifAbsent: () => amount,
        );
      }
    }
    
    return {
      'monthlySpending': monthlyData,
      'trend': _calculateMonthlyTrend(monthlyData),
    };
  }

  Map<String, double> _getCategoryBreakdown(List<Map<String, dynamic>> transactions) {
    return _getCategorySpending(transactions);
  }

  Map<String, dynamic> _analyzeSavingsPattern(
    List<Map<String, dynamic>> transactions, 
    Map<String, dynamic> metrics
  ) {
    final savingsRate = _safeConvertToDouble(metrics['savingsRate']);
    String profile = 'Balanced';
    
    if (savingsRate > 25) {
      profile = 'Super Saver';
    } else if (savingsRate > 15) {
      profile = 'Good Saver';
    } else if (savingsRate > 5) {
      profile = 'Moderate Saver';
    } else if (savingsRate >= 0) {
      profile = 'Minimal Saver';
    } else {
      profile = 'Over Spender';
    }

    return {
      'savingsProfile': profile,
      'savingsRate': savingsRate,
      'recommendedTarget': (_safeConvertToDouble(metrics['totalIncome']) * 0.2), // 20% target
    };
  }

  String _calculateMonthlyTrend(Map<String, double> monthlyData) {
    if (monthlyData.length < 2) return 'stable';
    
    final sortedKeys = monthlyData.keys.toList()..sort();
    final recent = monthlyData[sortedKeys.last] ?? 0.0;
    final previous = monthlyData[sortedKeys[sortedKeys.length - 2]] ?? 0.0;
    
    if (previous == 0) return 'stable';
    
    final change = (recent - previous) / previous;
    
    if (change > 0.05) return 'increasing';
    if (change < -0.05) return 'decreasing';
    return 'stable';
  }

  Map<String, dynamic> _getEmptyInsights() {
    return {
      'basicMetrics': {
        'totalExpenses': 0.0,
        'totalIncome': 0.0,
        'savings': 0.0,
        'savingsTransfers': 0.0,
        'savingsRate': 0.0,
        'categorySpending': <String, double>{},
        'averageMonthlyExpense': 0.0,
        'averageMonthlyIncome': 0.0,
        'transactionCount': 0,
      },
      'predictions': {'message': 'Add more transactions to get predictions'},
      'recommendations': {'overallAdvice': 'Start adding transactions to get personalized insights'},
      'alerts': [],
      'spendingTrends': {'trend': 'stable'},
      'categoryBreakdown': <String, double>{},
      'savingsAnalysis': {'savingsProfile': 'New User'},
    };
  }
}