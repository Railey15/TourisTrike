import 'package:flutter/material.dart';

enum MainTenantDestination {
  dashboard,
  cityTenants,
  registrations,
  packages,
  tourismData,
  reports,
  disputes,
  feedback,
  settings,
}

class MainTenantNavItem {
  const MainTenantNavItem({
    required this.destination,
    required this.label,
    required this.icon,
  });

  final MainTenantDestination destination;
  final String label;
  final IconData icon;
}

const mainTenantNavItems = [
  MainTenantNavItem(
    destination: MainTenantDestination.dashboard,
    label: 'Dashboard',
    icon: Icons.grid_view_rounded,
  ),
  MainTenantNavItem(
    destination: MainTenantDestination.cityTenants,
    label: 'Local Administrators',
    icon: Icons.location_city_rounded,
  ),
  MainTenantNavItem(
    destination: MainTenantDestination.packages,
    label: 'Packages',
    icon: Icons.inventory_2_rounded,
  ),
  MainTenantNavItem(
    destination: MainTenantDestination.tourismData,
    label: 'Spots',
    icon: Icons.travel_explore_rounded,
  ),
  MainTenantNavItem(
    destination: MainTenantDestination.reports,
    label: 'Reports',
    icon: Icons.query_stats_rounded,
  ),
  MainTenantNavItem(
    destination: MainTenantDestination.disputes,
    label: 'Disputes & Cases',
    icon: Icons.gavel_rounded,
  ),
  MainTenantNavItem(
    destination: MainTenantDestination.feedback,
    label: 'Feedback',
    icon: Icons.rate_review_rounded,
  ),
  MainTenantNavItem(
    destination: MainTenantDestination.settings,
    label: 'Settings',
    icon: Icons.settings_rounded,
  ),
];

String mainTenantDestinationTitle(MainTenantDestination destination) {
  for (final item in mainTenantNavItems) {
    if (item.destination == destination) return item.label;
  }
  if (destination == MainTenantDestination.registrations) {
    return 'Local Administrators';
  }
  return 'Dashboard';
}
