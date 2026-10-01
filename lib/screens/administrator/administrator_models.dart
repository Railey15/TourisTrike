  import 'package:touristrike/core/auth/app_role.dart';
  import 'package:touristrike/core/maintenance/maintenance_settings.dart';

  class AdministratorProfile {
    const AdministratorProfile({
      required this.id,
      required this.name,
      required this.role,
      required this.email,
    });

    final String id;
    final String name;
    final AppRole role;
    final String email;
  }

  enum PlatformAccountStatus { active, pendingVerification, suspended, unknown }

  enum AdministratorSuspensionReason {
    policyViolation('policy_violation', 'Policy violation'),
    fraudulentActivity(
      'fraudulent_activity',
      'Fraudulent or suspicious activity',
    ),
    inappropriateBehavior('inappropriate_behavior', 'Inappropriate behavior'),
    accountMisuse('account_misuse', 'Account misuse'),
    verificationIssue('verification_issue', 'Verification issue'),
    securityConcern('security_concern', 'Security concern'),
    other('other', 'Other');

    const AdministratorSuspensionReason(this.databaseValue, this.displayName);

    final String databaseValue;
    final String displayName;

    static AdministratorSuspensionReason? tryParse(String? value) {
      final normalized = (value ?? '').trim().toLowerCase();
      for (final reason in values) {
        if (reason.databaseValue == normalized) return reason;
      }
      return null;
    }
  }

  enum AdministratorSuspensionDuration {
    oneDay,
    threeDays,
    sevenDays,
    fourteenDays,
    thirtyDays,
    custom,
    permanent,
  }

  String administratorSuspensionReasonLabel(
    AdministratorSuspensionReason reason,
  ) => reason.displayName;

  String administratorSuspensionDurationLabel(
    AdministratorSuspensionDuration duration,
  ) {
    return switch (duration) {
      AdministratorSuspensionDuration.oneDay => '1 day',
      AdministratorSuspensionDuration.threeDays => '3 days',
      AdministratorSuspensionDuration.sevenDays => '7 days',
      AdministratorSuspensionDuration.fourteenDays => '14 days',
      AdministratorSuspensionDuration.thirtyDays => '30 days',
      AdministratorSuspensionDuration.custom => 'Custom duration',
      AdministratorSuspensionDuration.permanent =>
        'Permanent / Until manually reactivated',
    };
  }

  class AdministratorSuspensionRequest {
    const AdministratorSuspensionRequest({
      required this.reason,
      required this.details,
      required this.startedAt,
      required this.suspendedUntil,
      required this.isPermanent,
    });

    final AdministratorSuspensionReason reason;
    final String details;
    final DateTime startedAt;
    final DateTime? suspendedUntil;
    final bool isPermanent;

    String get reasonLabel => administratorSuspensionReasonLabel(reason);

    int? get totalDays {
      if (isPermanent || suspendedUntil == null) return null;
      final difference = suspendedUntil!.difference(startedAt);
      if (difference.inHours <= 0) return 0;
      return (difference.inHours / 24).ceil();
    }
  }

  class AdministratorSuspensionRecord {
    const AdministratorSuspensionRecord({
      required this.id,
      required this.reason,
      required this.details,
      required this.suspendedAt,
      required this.suspendedUntil,
      required this.isPermanent,
      this.suspendedById = '',
      this.suspendedByName = '',
    });

    final String id;
    final AdministratorSuspensionReason reason;
    final String details;
    final DateTime suspendedAt;
    final DateTime? suspendedUntil;
    final bool isPermanent;
    final String suspendedById;
    final String suspendedByName;

    String get reasonLabel => administratorSuspensionReasonLabel(reason);

    bool get isActive =>
        isPermanent ||
        (suspendedUntil != null &&
            suspendedUntil!.isAfter(DateTime.now().toUtc()));

    int? get totalDays {
      if (isPermanent || suspendedUntil == null) return null;
      final difference = suspendedUntil!.difference(suspendedAt);
      if (difference.inHours <= 0) return 0;
      return (difference.inHours / 24).ceil();
    }
  }

  class PlatformAccountSummary {
    const PlatformAccountSummary({
      required this.id,
      required this.name,
      required this.email,
      required this.role,
      required this.city,
      required this.province,
      required this.profileCreatedAt,
      required this.authCreatedAt,
      required this.emailConfirmedAt,
      required this.lastSignInAt,
      required this.bannedUntil,
      required this.authMetadataAvailable,
      this.suspension,
    });

    final String id;
    final String name;
    final String email;
    final AppRole role;
    final String city;
    final String province;
    final DateTime? profileCreatedAt;
    final DateTime? authCreatedAt;
    final DateTime? emailConfirmedAt;
    final DateTime? lastSignInAt;
    final DateTime? bannedUntil;
    final bool authMetadataAvailable;
    final AdministratorSuspensionRecord? suspension;

    PlatformAccountStatus get status {
      if (!authMetadataAvailable) return PlatformAccountStatus.unknown;
      if (suspension?.isActive ?? false) {
        return PlatformAccountStatus.suspended;
      }
      final banEnd = bannedUntil;
      if (banEnd != null && banEnd.isAfter(DateTime.now().toUtc())) {
        return PlatformAccountStatus.suspended;
      }
      if (emailConfirmedAt == null) {
        return PlatformAccountStatus.pendingVerification;
      }
      return PlatformAccountStatus.active;
    }

    DateTime? get createdAt => authCreatedAt ?? profileCreatedAt;

    bool matches(String query) {
      final value = query.trim().toLowerCase();
      if (value.isEmpty) return true;
      return [
        name,
        email,
        role.displayName,
        role.databaseValue,
        city,
        province,
        id,
      ].any((candidate) => candidate.toLowerCase().contains(value));
    }
  }

  enum TenantOfficeKind { provincial, cityMunicipal }

  class TenantOfficeSummary {
    const TenantOfficeSummary({
      required this.accountId,
      required this.officeName,
      required this.kind,
      required this.city,
      required this.province,
      required this.contactPerson,
      required this.email,
      required this.verificationStatus,
      required this.isActive,
      required this.updatedAt,
    });

    final String accountId;
    final String officeName;
    final TenantOfficeKind kind;
    final String city;
    final String province;
    final String contactPerson;
    final String email;
    final String verificationStatus;
    final bool isActive;
    final DateTime? updatedAt;

    String get scopeLabel => switch (kind) {
      TenantOfficeKind.provincial => 'Province-wide',
      TenantOfficeKind.cityMunicipal => city.isEmpty ? 'Municipality' : city,
    };

    String get statusLabel {
      if (kind == TenantOfficeKind.provincial) return 'Active';
      if (!isActive) {
        return verificationStatus.isEmpty ? 'Inactive' : verificationStatus;
      }
      return verificationStatus.isEmpty ? 'Active' : verificationStatus;
    }

    bool matches(String query) {
      final value = query.trim().toLowerCase();
      if (value.isEmpty) return true;
      return [
        officeName,
        city,
        province,
        contactPerson,
        email,
        verificationStatus,
        accountId,
      ].any((candidate) => candidate.toLowerCase().contains(value));
    }
  }

  class PlatformAuditEntry {
    const PlatformAuditEntry({
      required this.id,
      required this.actorId,
      required this.action,
      required this.tableName,
      required this.recordId,
      required this.description,
      required this.createdAt,
    });

    final String id;
    final String actorId;
    final String action;
    final String tableName;
    final String recordId;
    final String description;
    final DateTime? createdAt;

    bool matches(String query, {String actorName = ''}) {
      final value = query.trim().toLowerCase();
      if (value.isEmpty) return true;
      return [
        id,
        actorId,
        actorName,
        action,
        tableName,
        recordId,
        description,
      ].any((candidate) => candidate.toLowerCase().contains(value));
    }
  }

  enum PlatformHealthState { operational, degraded }

  class PlatformHealthCheck {
    const PlatformHealthCheck({
      required this.name,
      required this.description,
      required this.state,
      required this.latency,
      required this.checkedAt,
      this.detail = '',
    });

    final String name;
    final String description;
    final PlatformHealthState state;
    final Duration latency;
    final DateTime checkedAt;
    final String detail;

    bool get isOperational => state == PlatformHealthState.operational;
  }

  class AdministratorPortalData {
    const AdministratorPortalData({
      required this.profile,
      required this.accounts,
      required this.tenants,
      required this.auditEntries,
      required this.healthChecks,
      this.maintenance = const MaintenanceSettings.operational(),
    });

    final AdministratorProfile profile;
    final List<PlatformAccountSummary> accounts;
    final List<TenantOfficeSummary> tenants;
    final List<PlatformAuditEntry> auditEntries;
    final List<PlatformHealthCheck> healthChecks;
    final MaintenanceSettings maintenance;

    int countFor(AppRole role) =>
        accounts.where((account) => account.role == role).length;

    int statusCount(PlatformAccountStatus status) =>
        accounts.where((account) => account.status == status).length;

    int get operationalHealthChecks =>
        healthChecks.where((check) => check.isOperational).length;

    int get activeLocalTenants => tenants
        .where(
          (tenant) =>
              tenant.kind == TenantOfficeKind.cityMunicipal && tenant.isActive,
        )
        .length;

    Map<String, String> get accountNamesById => {
      for (final account in accounts) account.id: account.name,
    };

    Map<String, AdministratorSuspensionRecord> get activeSuspensionsByAccountId {
      final suspensions = <String, AdministratorSuspensionRecord>{};
      for (final account in accounts) {
        final suspension = account.suspension;
        if (suspension != null) suspensions[account.id] = suspension;
      }
      return suspensions;
    }
  }

  enum AdministratorDeveloperBookingFilter {
    all('all', 'All bookings'),
    upcoming('upcoming', 'Upcoming'),
    active('active', 'In progress');

    const AdministratorDeveloperBookingFilter(this.databaseValue, this.label);

    final String databaseValue;
    final String label;
  }

  enum AdministratorDeveloperTestFilter {
    all('all', 'All test states'),
    active('active', 'Test active'),
    inactive('inactive', 'Test inactive');

    const AdministratorDeveloperTestFilter(this.databaseValue, this.label);

    final String databaseValue;
    final String label;
  }

  class AdministratorDeveloperToolsQuery {
    const AdministratorDeveloperToolsQuery({
      this.search = '',
      this.bookingFilter = AdministratorDeveloperBookingFilter.all,
      this.testFilter = AdministratorDeveloperTestFilter.all,
      this.limit = 25,
      this.offset = 0,
    });

    final String search;
    final AdministratorDeveloperBookingFilter bookingFilter;
    final AdministratorDeveloperTestFilter testFilter;
    final int limit;
    final int offset;

    AdministratorDeveloperToolsQuery copyWith({
      String? search,
      AdministratorDeveloperBookingFilter? bookingFilter,
      AdministratorDeveloperTestFilter? testFilter,
      int? limit,
      int? offset,
    }) => AdministratorDeveloperToolsQuery(
      search: search ?? this.search,
      bookingFilter: bookingFilter ?? this.bookingFilter,
      testFilter: testFilter ?? this.testFilter,
      limit: limit ?? this.limit,
      offset: offset ?? this.offset,
    );
  }

  class AdministratorDeveloperTestingOverview {
    const AdministratorDeveloperTestingOverview({
      required this.enabled,
      required this.eligibleBookings,
      required this.activeSessions,
      required this.upcomingBookings,
      required this.expiringSoon,
      this.updatedBy = '',
      this.updatedAt,
    });

    final bool enabled;
    final int eligibleBookings;
    final int activeSessions;
    final int upcomingBookings;
    final int expiringSoon;
    final String updatedBy;
    final DateTime? updatedAt;
  }

  class AdministratorDeveloperTestDriver {
    const AdministratorDeveloperTestDriver({
      required this.id,
      required this.name,
    });

    final String id;
    final String name;
  }

  class AdministratorDeveloperTestBooking {
    const AdministratorDeveloperTestBooking({
      required this.id,
      required this.reference,
      required this.touristId,
      required this.touristName,
      required this.packageId,
      required this.packageName,
      required this.municipality,
      required this.bookingStatus,
      required this.tourStatus,
      required this.drivers,
      required this.requiredDrivers,
      required this.assignedDriverCount,
      required this.downpaymentReady,
      required this.remainingPaymentReady,
      required this.validTourist,
      required this.driversReady,
      required this.bookingStateValid,
      required this.eligible,
      required this.eligibilityReason,
      required this.testSessionActive,
      required this.bypassScheduledStart,
      this.scheduledStartAt,
      this.estimatedEndAt,
      this.testSessionId = '',
      this.activatedBy = '',
      this.activatedByName = '',
      this.activatedAt,
      this.expiresAt,
      this.reason = '',
    });

    final String id;
    final String reference;
    final String touristId;
    final String touristName;
    final int packageId;
    final String packageName;
    final String municipality;
    final DateTime? scheduledStartAt;
    final DateTime? estimatedEndAt;
    final String bookingStatus;
    final String tourStatus;
    final List<AdministratorDeveloperTestDriver> drivers;
    final int requiredDrivers;
    final int assignedDriverCount;
    final bool downpaymentReady;
    final bool remainingPaymentReady;
    final bool validTourist;
    final bool driversReady;
    final bool bookingStateValid;
    final bool eligible;
    final String eligibilityReason;
    final String testSessionId;
    final bool testSessionActive;
    final String activatedBy;
    final String activatedByName;
    final DateTime? activatedAt;
    final DateTime? expiresAt;
    final String reason;
    final bool bypassScheduledStart;

    bool get canActivate => eligible && !testSessionActive;
  }

  class AdministratorDeveloperToolsData {
    const AdministratorDeveloperToolsData({
      required this.overview,
      required this.bookings,
      required this.totalCount,
      required this.query,
    });

    final AdministratorDeveloperTestingOverview overview;
    final List<AdministratorDeveloperTestBooking> bookings;
    final int totalCount;
    final AdministratorDeveloperToolsQuery query;

    bool get hasPreviousPage => query.offset > 0;
    bool get hasNextPage => query.offset + bookings.length < totalCount;
  }

  class AdministratorDeveloperTestActivation {
    const AdministratorDeveloperTestActivation({
      required this.reason,
      required this.expiresAt,
    });

    final String reason;
    final DateTime expiresAt;
  }
