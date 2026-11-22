import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

class TransactionCard extends StatelessWidget {
  final String label;
  final DateTime? date;
  final double amount;
  final String type; 
  final String category; 

  const TransactionCard({
    super.key,
    required this.label,
    required this.date,
    required this.amount,
    required this.type,
    required this.category, 
  });


  IconData _getCategoryIcon(String category) {
    switch (category.toLowerCase()) {
      case "income/allowance":
        return Icons.attach_money_rounded; 
      case "utility bills":
        return Icons.lightbulb_outline_rounded; 
      case "transportation":
        return Icons.directions_bus_rounded;
      case "food/grocery":
        return Icons.restaurant_rounded;
      case "subscriptions":
        return Icons.subscriptions_rounded; 
      case "savings":
        return Icons.savings_rounded; 
      case "shopping/other":
        return Icons.shopping_bag_rounded;
      case "funds":
        return Icons.account_balance_wallet_rounded;  
      default:
        return Icons.circle_outlined;
    }
  }

  @override
  Widget build(BuildContext context) {
    String formattedDate = "";
    final added = date;
    if (added != null) {
      final now = DateTime.now();
      // Count calendar days rather than 24-hour periods, so an entry from
      // late last night reads "Yesterday" instead of a time. Comparing UTC
      // dates keeps daylight-saving shifts out of the count.
      final difference = DateTime.utc(now.year, now.month, now.day)
          .difference(DateTime.utc(added.year, added.month, added.day))
          .inDays;

      if (difference <= 0) {
        final timeFormat = DateFormat.jm(); // e.g., 3:45 PM
        formattedDate = timeFormat.format(added);
      } else if (difference == 1) {
        formattedDate = "Yesterday";
      } else {
        formattedDate = "$difference days ago";
      }
    }

    return Card(
      margin: const EdgeInsets.symmetric(vertical: 6, horizontal: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ListTile(
        leading: Icon(
          _getCategoryIcon(category),
          color: type == "income" ? Colors.green : Colors.red,
        ),
        title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
        subtitle: Text(formattedDate),
        trailing: Text(
          (type == "income" ? "+" : "-") + NumberFormat.currency(locale: 'en_PH', symbol: "₱").format(amount),
          style: TextStyle(
            color: type == "income" ? Colors.green : Colors.red,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }
}
