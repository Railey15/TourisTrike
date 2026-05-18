import 'package:flutter/material.dart';

/// Notifications Settings Screen
/// - Simple toggles that make sense for a tricycle + tour app
/// - Grouped cards, same visual language (blue, rounded, soft shadows)
///
/// Navigate:
/// Navigator.push(context, MaterialPageRoute(builder: (_) => const NotificationsScreen()));
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  // Trip/Ride
  bool _rideUpdates = true;
  bool _driverMessages = true;
  bool _pickupReminders = true;

  // Tours
  bool _tourUpdates = true;
  bool _tourReminders = true;

  // App
  bool _promos = false;
  bool _safetyAlerts = true;

  // Quiet hours
  bool _quietHours = false;
  TimeOfDay _quietFrom = const TimeOfDay(hour: 22, minute: 0);
  TimeOfDay _quietTo = const TimeOfDay(hour: 7, minute: 0);

  Future<void> _pickTime({required bool isFrom}) async {
    final initial = isFrom ? _quietFrom : _quietTo;
    final picked = await showTimePicker(context: context, initialTime: initial);
    if (picked == null) return;

    setState(() {
      if (isFrom) {
        _quietFrom = picked;
      } else {
        _quietTo = picked;
      }
    });
  }

  void _resetDefaults() {
    setState(() {
      _rideUpdates = true;
      _driverMessages = true;
      _pickupReminders = true;

      _tourUpdates = true;
      _tourReminders = true;

      _promos = false;
      _safetyAlerts = true;

      _quietHours = false;
      _quietFrom = const TimeOfDay(hour: 22, minute: 0);
      _quietTo = const TimeOfDay(hour: 7, minute: 0);
    });

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Notification settings reset.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textLight = Color(0xFF94A3B8);
    const line = Color(0xFFE7EEF7);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Column(
          children: [
            // =========================
            // TOP BAR
            // =========================
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
                      'Notifications',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: _resetDefaults,
                    style: TextButton.styleFrom(
                      foregroundColor: blue,
                      textStyle: const TextStyle(fontWeight: FontWeight.w900),
                    ),
                    child: const Text('Reset'),
                  ),
                ],
              ),
            ),

            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                children: [
                  // =========================
                  // RIDE
                  // =========================
                  const _SectionTitle('Ride'),
                  const SizedBox(height: 10),
                  _Card(
                    child: Column(
                      children: [
                        _SwitchRow(
                          icon: Icons.notifications_active_rounded,
                          title: 'Ride updates',
                          subtitle:
                              'Accepted, arriving, started, completed, cancelled',
                          value: _rideUpdates,
                          onChanged: (v) => setState(() => _rideUpdates = v),
                        ),
                        const Divider(height: 18, color: line),
                        _SwitchRow(
                          icon: Icons.chat_bubble_rounded,
                          title: 'Driver messages',
                          subtitle: 'Messages from your driver',
                          value: _driverMessages,
                          onChanged: (v) => setState(() => _driverMessages = v),
                        ),
                        const Divider(height: 18, color: line),
                        _SwitchRow(
                          icon: Icons.alarm_rounded,
                          title: 'Pickup reminders',
                          subtitle: 'Remind you before pickup time',
                          value: _pickupReminders,
                          onChanged: (v) =>
                              setState(() => _pickupReminders = v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // =========================
                  // TOURS
                  // =========================
                  const _SectionTitle('Tours'),
                  const SizedBox(height: 10),
                  _Card(
                    child: Column(
                      children: [
                        _SwitchRow(
                          icon: Icons.tour_rounded,
                          title: 'Tour updates',
                          subtitle:
                              'Booking confirmed, changes, guide assigned',
                          value: _tourUpdates,
                          onChanged: (v) => setState(() => _tourUpdates = v),
                        ),
                        const Divider(height: 18, color: line),
                        _SwitchRow(
                          icon: Icons.event_available_rounded,
                          title: 'Tour reminders',
                          subtitle: 'Remind you before tour starts',
                          value: _tourReminders,
                          onChanged: (v) => setState(() => _tourReminders = v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // =========================
                  // APP
                  // =========================
                  const _SectionTitle('App'),
                  const SizedBox(height: 10),
                  _Card(
                    child: Column(
                      children: [
                        _SwitchRow(
                          icon: Icons.local_offer_rounded,
                          title: 'Promotions',
                          subtitle: 'Discounts, announcements, offers',
                          value: _promos,
                          onChanged: (v) => setState(() => _promos = v),
                        ),
                        const Divider(height: 18, color: line),
                        _SwitchRow(
                          icon: Icons.shield_rounded,
                          title: 'Safety alerts',
                          subtitle:
                              'Important safety updates and emergency notices',
                          value: _safetyAlerts,
                          onChanged: (v) => setState(() => _safetyAlerts = v),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // =========================
                  // QUIET HOURS
                  // =========================
                  const _SectionTitle('Quiet Hours'),
                  const SizedBox(height: 10),
                  _Card(
                    child: Column(
                      children: [
                        _SwitchRow(
                          icon: Icons.nights_stay_rounded,
                          title: 'Enable quiet hours',
                          subtitle: 'Silence non-urgent notifications',
                          value: _quietHours,
                          onChanged: (v) => setState(() => _quietHours = v),
                        ),
                        if (_quietHours) ...[
                          const Divider(height: 18, color: line),
                          _TimeRow(
                            icon: Icons.bedtime_rounded,
                            title: 'From',
                            time: _quietFrom,
                            onTap: () => _pickTime(isFrom: true),
                          ),
                          const Divider(height: 18, color: line),
                          _TimeRow(
                            icon: Icons.wb_sunny_rounded,
                            title: 'To',
                            time: _quietTo,
                            onTap: () => _pickTime(isFrom: false),
                          ),
                          const SizedBox(height: 6),
                          const Align(
                            alignment: Alignment.centerLeft,
                            child: Text(
                              'Safety alerts may still notify you.',
                              style: TextStyle(
                                fontWeight: FontWeight.w800,
                                color: textLight,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                        ],
                      ],
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

// ============================================================
// UI PIECES
// ============================================================

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
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    const line = Color(0xFFE7EEF7);
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: line),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    const textDark = Color(0xFF0F172A);
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16.5,
        fontWeight: FontWeight.w900,
        color: textDark,
        letterSpacing: -0.2,
      ),
    );
  }
}

class _SwitchRow extends StatelessWidget {
  const _SwitchRow({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    required this.onChanged,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: const Color(0xFFEAF2FF),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Icon(icon, color: blue),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textDark,
                  fontSize: 15.5,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitle,
                style: const TextStyle(
                  fontWeight: FontWeight.w800,
                  color: textMid,
                  fontSize: 12.5,
                ),
              ),
            ],
          ),
        ),
        Switch(value: value, onChanged: onChanged),
      ],
    );
  }
}

class _TimeRow extends StatelessWidget {
  const _TimeRow({
    required this.icon,
    required this.title,
    required this.time,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final TimeOfDay time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const line = Color(0xFFE7EEF7);

    final label = time.format(context);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                title,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textDark,
                  fontSize: 15.5,
                ),
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFF8FAFF),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: line),
              ),
              child: Text(
                label,
                style: const TextStyle(
                  fontWeight: FontWeight.w900,
                  color: textMid,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
