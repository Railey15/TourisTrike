enum AppRole {
  administrator('administrator', 'System Administrator'),
  mainTenant('main_tenant', 'Provincial Administrator'),
  subtenant('subtenant', 'City/Municipal Administrator'),
  driver('driver', 'Driver-Tour Guide'),
  tourist('tourist', 'Tourist');

  const AppRole(this.databaseValue, this.displayName);

  final String databaseValue;
  final String displayName;

  static AppRole? tryParse(String? value, {bool acceptLegacyAdmin = true}) {
    final normalized = (value ?? '').trim().toLowerCase();
    if (acceptLegacyAdmin && normalized == 'admin') {
      return AppRole.mainTenant;
    }

    for (final role in AppRole.values) {
      if (role.databaseValue == normalized) return role;
    }
    return null;
  }
}
