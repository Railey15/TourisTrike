import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:touristrike/widgets/driver_page_header.dart';

void main() {
  const widths = <double>[430, 390, 360, 320];

  for (final width in widths) {
    testWidgets('driver headers stay equal and overflow-free at ${width}px', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(Size(width, 932));
      addTearDown(() => tester.binding.setSurfaceSize(null));

      for (final (index, header) in _headerVariants().indexed) {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: MediaQuery(
                data: const MediaQueryData(padding: EdgeInsets.only(top: 24)),
                child: Column(
                  children: [
                    KeyedSubtree(key: const Key('header'), child: header),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(
          tester.takeException(),
          isNull,
          reason: 'Header variant $index overflowed at ${width}px',
        );
        expect(
          tester.getSize(find.byKey(const Key('header'))).height,
          DriverPageHeader.standardHeight + 24,
        );
      }
    });
  }
}

List<Widget> _headerVariants() {
  return [
    DriverPageHeader.custom(
      headerContent: Row(
        children: [
          Container(
            width: DriverPageHeader.profileAvatarSize,
            height: DriverPageHeader.profileAvatarSize,
            decoration: const BoxDecoration(
              color: Colors.white24,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Good evening',
                  style: TextStyle(color: Colors.white, fontSize: 11.5),
                ),
                SizedBox(height: 3),
                Text(
                  'Ange Villafania',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    height: 1.1,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Available for tours',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.white, fontSize: 10.5),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          DriverHeaderActionButton(
            icon: Icons.notifications_none_rounded,
            onPressed: _noop,
          ),
          const SizedBox(width: 7),
          DriverHeaderActionButton(
            icon: Icons.person_outline_rounded,
            onPressed: _noop,
          ),
        ],
      ),
      stats: const [
        DriverHeaderStat(
          icon: Icons.route_rounded,
          value: 'None',
          label: 'Active Tour',
        ),
        DriverHeaderStat(
          icon: Icons.payments_outlined,
          value: 'PHP 0.00',
          label: "Today's Earnings",
        ),
      ],
    ),
    DriverPageHeader(
      icon: Icons.work_outline_rounded,
      title: 'Package Jobs',
      subtitle: 'New tour assignments available to you',
      onRefresh: _noop,
      stats: const [
        DriverHeaderStat(
          icon: Icons.assignment_outlined,
          value: '0',
          label: 'Available',
        ),
        DriverHeaderStat(
          icon: Icons.check_circle_outline_rounded,
          value: '0',
          label: 'Accepted',
        ),
        DriverHeaderStat(
          icon: Icons.location_on_outlined,
          value: 'Baliwag',
          label: 'Area',
        ),
      ],
    ),
    DriverPageHeader(
      icon: Icons.history_rounded,
      title: 'Activity',
      subtitle: 'Track your accepted and completed tours',
      onRefresh: _noop,
      stats: const [
        DriverHeaderStat(
          icon: Icons.luggage_outlined,
          value: '0',
          label: 'Bookings',
        ),
        DriverHeaderStat(
          icon: Icons.navigation_outlined,
          value: '0',
          label: 'Active',
        ),
        DriverHeaderStat(
          icon: Icons.check_circle_outline_rounded,
          value: '0',
          label: 'Completed',
        ),
      ],
    ),
    const DriverPageHeader(
      icon: Icons.account_balance_wallet_outlined,
      title: 'Earnings',
      subtitle: 'Your direct GCash payment records',
      action: DriverHeaderBadge(
        icon: Icons.verified_user_outlined,
        label: 'RECORD ONLY',
      ),
      stats: [
        DriverHeaderStat(
          icon: Icons.account_balance_wallet_outlined,
          value: '₱0.00',
          label: 'Total Recorded',
        ),
        DriverHeaderStat(
          icon: Icons.today_outlined,
          value: '₱0.00',
          label: 'Today',
        ),
        DriverHeaderStat(
          icon: Icons.check_circle_outline_rounded,
          value: '0',
          label: 'Confirmed',
        ),
      ],
    ),
  ];
}

void _noop() {}
