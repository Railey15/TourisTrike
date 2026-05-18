import 'package:flutter/material.dart';

class PaymentHistoryScreen extends StatelessWidget {
  const PaymentHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    final transactions = <PaymentTransaction>[];

    final totalSpent = transactions
        .where((t) => t.status == PaymentStatus.paid)
        .fold<double>(0.0, (sum, t) => sum + t.amount);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // ==========================
            // HEADER
            // ==========================
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _TopCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Payment History',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                      ),
                    ),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  // ==========================
                  // SUMMARY CARD
                  // ==========================
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: line),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 18,
                          offset: const Offset(0, 12),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 50,
                          height: 50,
                          decoration: BoxDecoration(
                            color: const Color(0xFFEAF2FF),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.payments_rounded,
                            color: blue,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Total Spent',
                                style: TextStyle(
                                  fontWeight: FontWeight.w900,
                                  color: textMid,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                'â‚± ${totalSpent.toStringAsFixed(0)}',
                                style: const TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.w900,
                                  color: textDark,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '${transactions.length} transactions',
                          style: const TextStyle(
                            fontWeight: FontWeight.w800,
                            color: textMid,
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  const Text(
                    'Transactions',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                    ),
                  ),

                  const SizedBox(height: 10),

                  if (transactions.isEmpty)
                    const _EmptyState()
                  else
                    ...transactions.map(
                      (t) => Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _TransactionCard(transaction: t),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TransactionCard extends StatelessWidget {
  const _TransactionCard({required this.transaction});

  final PaymentTransaction transaction;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const green = Color(0xFF16A34A);
    const red = Color(0xFFDC2626);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    final statusColor = transaction.status == PaymentStatus.paid ? green : red;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
      ),
      child: Row(
        children: [
          const Icon(Icons.receipt_long_rounded, color: blue, size: 30),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  transaction.title,
                  style: const TextStyle(
                    fontWeight: FontWeight.w900,
                    color: textDark,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  transaction.date,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textMid,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  transaction.method,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textMid,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                'â‚± ${transaction.amount.toStringAsFixed(0)}',
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: blue,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                transaction.status == PaymentStatus.paid ? 'Paid' : 'Refunded',
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: statusColor,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: const BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
        ),
        child: Icon(icon, color: Color(0xFF0F172A)),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(30),
        child: Text(
          'No payments yet.',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: Color(0xFF64748B),
          ),
        ),
      ),
    );
  }
}

enum PaymentStatus { paid, refunded }

class PaymentTransaction {
  final String title;
  final String date;
  final String method;
  final double amount;
  final PaymentStatus status;

  PaymentTransaction({
    required this.title,
    required this.date,
    required this.method,
    required this.amount,
    required this.status,
  });
}
