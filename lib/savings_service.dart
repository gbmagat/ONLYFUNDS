import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';

class SavingsService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  /// Add a new savings goal for the current month
  Future<void> addSavingsGoal({
  required String category,
  required double amount,
}) async {
  final user = _auth.currentUser;
  if (user == null) throw Exception("No user logged in");

  final String monthId = _getMonthId();
  final DateTime now = DateTime.now();

  final monthRef = _firestore
      .collection("users")
      .doc(user.uid)
      .collection("monthly_records")
      .doc(monthId);

  final goalsRef = monthRef.collection("goals").doc(category);
  final summaryRef = monthRef.collection("summary").doc("record");

  // Raise the category's goal and the month's combined target together, in
  // one batch. Increments need no prior read, so a change saved in the
  // meantime, such as a new transaction, can no longer be overwritten with
  // stale totals. Merging leaves the summary's other fields untouched, and a
  // missing field counts as zero.
  final batch = _firestore.batch();
  batch.set(goalsRef, {
    "amount": FieldValue.increment(amount),
    "lastUpdated": now,
  }, SetOptions(merge: true));
  batch.set(summaryRef, {
    "targetSavings": FieldValue.increment(amount),
    "lastUpdated": now,
  }, SetOptions(merge: true));
  await batch.commit();
}

  /// Moves [amount] from this month's balance into savings.
  ///
  /// One Firestore transaction checks the amount against the balance and the
  /// remaining goal, records it as an expense in the "Funds" category, and
  /// updates the expense total, balance, and saved amount together, so a
  /// failure can no longer deduct the money without recording the saving.
  ///
  /// Throws a [SavingsDepositException], with a message for the user, when
  /// the amount is more than the balance or the remaining goal.
  Future<void> depositToSavings(double amount) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception("No user logged in");

    final DateTime now = DateTime.now();
    final monthRef = _firestore
        .collection("users")
        .doc(user.uid)
        .collection("monthly_records")
        .doc(_getMonthId());
    final summaryRef = monthRef.collection("summary").doc("record");
    // Generated up front so a retried attempt rewrites the same record.
    final depositRef = monthRef.collection("transactions").doc();

    await _firestore.runTransaction((transaction) async {
      final snapshot = await transaction.get(summaryRef);
      final data = snapshot.data() ?? <String, dynamic>{};
      final double totalExpense = (data["totalExpense"] ?? 0).toDouble();
      final double balance = (data["balance"] ?? 0).toDouble();
      final double targetSavings = (data["targetSavings"] ?? 0).toDouble();
      final double amountSaved = (data["amountSaved"] ?? 0).toDouble();
      final double remaining = targetSavings - amountSaved;

      if (amount > balance) {
        throw SavingsDepositException(
            "Deposit exceeds available balance (₱${balance.toStringAsFixed(2)})");
      }
      if (amount > remaining) {
        throw SavingsDepositException(
            "Deposit exceeds remaining goal (₱${remaining.toStringAsFixed(2)})");
      }

      transaction.set(depositRef, {
        "label": "Savings",
        "category": "Funds",
        "description": "",
        "amount": amount,
        "type": "expense",
        "date_added": now,
      });
      transaction.set(summaryRef, {
        "totalExpense": totalExpense + amount,
        "balance": balance - amount,
        "amountSaved": amountSaved + amount,
        "lastUpdated": now,
      }, SetOptions(merge: true));
    });
  }

  /// Get savings goal for a category
  Stream<DocumentSnapshot> getGoal(String category) {
    final user = _auth.currentUser;
    if (user == null) throw Exception("No user logged in");

    final monthId = _getMonthId();
    return _firestore
        .collection("users")
        .doc(user.uid)
        .collection("monthly_records")
        .doc(monthId)
        .collection("goals")
        .doc(category)
        .snapshots();
  }

  /// Get summary (totalIncome, totalExpense, balance, targetSavings, amountSaved)
  Stream<DocumentSnapshot> getSummary() {
    final user = _auth.currentUser;
    if (user == null) throw Exception("No user logged in");

    final monthId = _getMonthId();
    return _firestore
        .collection("users")
        .doc(user.uid)
        .collection("monthly_records")
        .doc(monthId)
        .collection("summary")
        .doc("record")
        .snapshots();
  }

  String _getMonthId() {
    final now = DateTime.now();
    return "${now.year}-${now.month.toString().padLeft(2, '0')}";
  }

  Stream<double> currentAmountSaved() => _getSummaryField("amountSaved");
  Stream<double> currentTargetSavings() => _getSummaryField("targetSavings");

  /// Streams how much is left to reach this month's savings target: the
  /// combined goal amount minus what has already been saved.
  Stream<double> remainingToTarget() {
    return getSummary().map((doc) {
      if (!doc.exists) return 0.0;
      final data = doc.data() as Map<String, dynamic>;
      final double target = (data["targetSavings"] ?? 0).toDouble();
      final double saved = (data["amountSaved"] ?? 0).toDouble();
      return target - saved;
    });
  }
  
  Stream<double> _getSummaryField(String field) {
    final user = _auth.currentUser;
    if (user == null) throw Exception("No user logged in");

    return _firestore
        .collection("users")
        .doc(user.uid)
        .collection("monthly_records")
        .doc(_getMonthId())
        .collection("summary")
        .doc("record")
        .snapshots()
        .map((doc) {
      if (!doc.exists) return 0.0;
      final data = doc.data() as Map<String, dynamic>;
      return (data[field] ?? 0).toDouble();
    });
  }

  Stream<double> savedAmount(String category) {
  final user = _auth.currentUser;
  if (user == null) throw Exception("No user logged in");

  final monthId = _getMonthId();
  return _firestore
      .collection("users")
      .doc(user.uid)
      .collection("monthly_records")
      .doc(monthId)
      .collection("goals")
      .doc(category)
      .snapshots()
      .map((doc) {
    if (!doc.exists) return 0.0;
    final data = doc.data() as Map<String, dynamic>;
    return (data["amount"]?.toDouble() ?? 0.0);
  });
}
}

/// A savings deposit that cannot be made, with a message for the user.
class SavingsDepositException implements Exception {
  const SavingsDepositException(this.message);

  final String message;

  @override
  String toString() => message;
}
