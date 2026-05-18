import 'package:flutter/material.dart';

class RideDetailsScreen extends StatelessWidget {
  const RideDetailsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const textLight = Color(0xFF94A3B8);
    const line = Color(0xFFE7EEF7);

    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: bg,
      body: Column(
        children: [
          // ===== MAP HEADER =====
          SizedBox(
            height: 240,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.asset(
                  'assets/images/map_mock.png',
                  fit: BoxFit.cover,
                ),
                Positioned(
                  top: 50,
                  left: 16,
                  child: _CircleBtn(
                    icon: Icons.arrow_back,
                    onTap: () => Navigator.pop(context),
                  ),
                ),
                Positioned(
                  top: 50,
                  right: 16,
                  child: _CircleBtn(
                    icon: Icons.notifications_none,
                    onTap: () {},
                  ),
                ),
              ],
            ),
          ),

          // ===== CONTENT =====
          Expanded(
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 18, 18, 0),
              decoration: const BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Date + Status
                  Row(
                    children: const [
                      Text(
                        'MON, 12 DEC • 10:10 AM',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w800,
                          color: textLight,
                        ),
                      ),
                      Spacer(),
                      _StatusChip(),
                    ],
                  ),

                  const SizedBox(height: 6),

                  const Text(
                    'Trip Details',
                    style: TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                      color: textDark,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // ===== DRIVER CARD (Compact) =====
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: blue, width: 1.8),
                    ),
                    child: Row(
                      children: [
                        const CircleAvatar(
                          radius: 24,
                          backgroundColor: Color(0xFFEAF2FF),
                          child: Icon(Icons.person, color: blue),
                        ),
                        const SizedBox(width: 12),
                        const Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Juan Dela Cruz',
                                style: TextStyle(
                                  fontSize: 17,
                                  fontWeight: FontWeight.w900,
                                  color: textDark,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                'Green Tricycle   ABC-1234',
                                style: TextStyle(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700,
                                  color: textMid,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFFF1F5F9),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: const Row(
                            children: [
                              Text(
                                '4.9',
                                style: TextStyle(
                                    fontWeight: FontWeight.w900),
                              ),
                              SizedBox(width: 4),
                              Icon(Icons.star,
                                  size: 16, color: Color(0xFFF59E0B)),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ===== PICKUP / DROPOFF CARD =====
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(color: line),
                    ),
                    child: Column(
                      children: const [
                        _LocationRow(
                          icon: Icons.my_location,
                          iconColor: blue,
                          title: 'PICK-UP (CURRENT LOCATION)',
                          value: 'Pickup location',
                        ),
                        Divider(height: 26),
                        _LocationRow(
                          icon: Icons.location_on,
                          iconColor: Color(0xFFEF4444),
                          title: 'DROP-OFF (BUSTOS AREA)',
                          value: 'Destination',
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 18),

                  // ===== DISTANCE & DURATION =====
                  Row(
                    children: const [
                      Expanded(
                        child: _MetricCard(
                          title: 'DISTANCE',
                          value: '3.2 KM',
                        ),
                      ),
                      SizedBox(width: 14),
                      Expanded(
                        child: _MetricCard(
                          title: 'DURATION',
                          value: '15 min EST',
                        ),
                      ),
                    ],
                  ),

                  const Spacer(),

                  // ===== BUTTON (Slimmer) =====
                  SizedBox(
                    width: double.infinity,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: () => Navigator.pop(context),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF79AEE3),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                      ),
                      child: const Text(
                        'Back to Navigation',
                        style: TextStyle(
                          fontWeight: FontWeight.w900,
                          fontSize: 16,
                        ),
                      ),
                    ),
                  ),

                  SizedBox(height: bottomInset + 14),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
class _CircleBtn extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;

  const _CircleBtn({required this.icon, required this.onTap});

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

class _StatusChip extends StatelessWidget {
  const _StatusChip();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        border: Border.all(color: Color(0xFF2A86FF)),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'ONGOING',
        style: TextStyle(
          fontWeight: FontWeight.w900,
          fontSize: 12,
          color: Color(0xFF2A86FF),
        ),
      ),
    );
  }
}

class _LocationRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String value;

  const _LocationRow({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        CircleAvatar(
          radius: 20,
          backgroundColor: iconColor.withOpacity(0.12),
          child: Icon(icon, color: iconColor),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                value,
                style: const TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                  color: Color(0xFF0F172A),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;

  const _MetricCard({required this.title, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w900,
              color: Color(0xFF94A3B8),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w900,
              color: Color(0xFF2A86FF),
            ),
          ),
        ],
      ),
    );
  }
}
