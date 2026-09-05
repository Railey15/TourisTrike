import 'package:flutter/material.dart';

enum ProvincialAdminDestination {
  dashboard,
  cityTenants,
  registrations,
  packages,
  tourismData,
  reports,
  feedback,
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
    destination: ProvincialAdminDestination.packages,
    label: 'Packages',
    icon: Icons.inventory_2_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.tourismData,
    label: 'Spots',
    icon: Icons.travel_explore_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.reports,
    label: 'Reports',
    icon: Icons.query_stats_rounded,
  ),
  ProvincialAdminNavItem(
    destination: ProvincialAdminDestination.feedback,
    label: 'Feedback',
    icon: Icons.rate_review_rounded,
  ),
];

String provincialAdminDestinationTitle(ProvincialAdminDestination destination) {
  for (final item in provincialAdminNavItems) {
    if (item.destination == destination) return item.label;
  }
  if (destination == ProvincialAdminDestination.registrations) {
    return 'City Tenants';
  }
  return 'Dashboard';
}
