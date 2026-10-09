/// Server-calculated remaining balance components. Active accrual is shown
/// separately until departure finalizes the charge into remaining_balance.
class BookingWaitingBalance {
  const BookingWaitingBalance({
    required this.packageRemaining,
    required this.finalizedWaiting,
    required this.accruedWaiting,
    required this.totalRemaining,
  });

  factory BookingWaitingBalance.fromJson(Map<String, dynamic> json) {
    double amount(String name) {
      final value = json[name];
      final parsed = value is num
          ? value.toDouble()
          : double.tryParse('$value');
      if (parsed == null || !parsed.isFinite || parsed < 0) {
        throw FormatException('Invalid server waiting balance: $name');
      }
      return parsed;
    }

    return BookingWaitingBalance(
      packageRemaining: amount('package_remaining'),
      finalizedWaiting: amount('finalized_waiting'),
      accruedWaiting: amount('accrued_waiting'),
      totalRemaining: amount('total_remaining'),
    );
  }

  final double packageRemaining;
  final double finalizedWaiting;
  final double accruedWaiting;
  final double totalRemaining;

  // The summary retains all historical finalized fees, including fees paid
  // with an earlier remaining-balance receipt. Show only the amount still due.
  double get payableWaiting {
    final currentDue = totalRemaining - accruedWaiting - packageRemaining;
    return currentDue <= 0
        ? 0
        : currentDue < finalizedWaiting
        ? currentDue
        : finalizedWaiting;
  }

  double get finalizedTotal => packageRemaining + payableWaiting;
}
