import 'app_role.dart';

enum AppRoleDestination {
  administratorPortal,
  mainTenantPortal,
  subtenantPortal,
  driverApp,
  touristApp,
}

AppRoleDestination destinationForRole(AppRole role) {
  return switch (role) {
    AppRole.administrator => AppRoleDestination.administratorPortal,
    AppRole.mainTenant => AppRoleDestination.mainTenantPortal,
    AppRole.subtenant => AppRoleDestination.subtenantPortal,
    AppRole.driver => AppRoleDestination.driverApp,
    AppRole.tourist => AppRoleDestination.touristApp,
  };
}

bool roleCanAccessDestination(AppRole role, AppRoleDestination destination) {
  return destinationForRole(role) == destination;
}
