import 'package:flutter/material.dart';

enum ProvincialAdminDestination {
  dashboard,
  cityTenants,
  registrations,
  packages,
  tourismData,
  reports,
  revenue,
  feedback,
  settings,
}

class ProvincialAdminNavItem {
  const ProvincialAdminNavItem({
    required this.destination,
    required this.label,
    required this.icon,
  });

  final ProvincialAdminDestination destination;
  final String label;
  final IconData icon;
}

const provincialAdminNavItems = [
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.dashboard,
    label: 'Dashboard',
    icon: Icons.grid_view_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.cityTenants,
    label: 'City Tenants',
    icon: Icons.location_city_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.registrations,
    label: 'Registrations',
    icon: Icons.how_to_reg_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.packages,
    label: 'Packages',
    icon: Icons.inventory_2_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.tourismData,
    label: 'Tourism Data',
    icon: Icons.travel_explore_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.reports,
    label: 'Reports',
    icon: Icons.query_stats_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.revenue,
    label: 'Revenue',
    icon: Icons.payments_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.feedback,
    label: 'Feedback',
    icon: Icons.rate_review_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.settings,
    label: 'Settings',
    icon: Icons.settings_rounded,
  ),
];

String provincialAdminDestinationTitle(ProvincialAdminDestination destination) {
  return provincialAdminNavItems
      .firstWhere((item) => item.destination == destination)
      .label;
}
