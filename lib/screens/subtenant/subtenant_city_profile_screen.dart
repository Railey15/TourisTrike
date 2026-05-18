import 'package:flutter/material.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantCityProfileScreen extends StatefulWidget {
  const SubTenantCityProfileScreen({super.key});

  @override
  State<SubTenantCityProfileScreen> createState() =>
      _SubTenantCityProfileScreenState();
}

class _SubTenantCityProfileScreenState
    extends State<SubTenantCityProfileScreen> {
  final SubTenantService _service = SubTenantService();
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();

  late Future<_SettingsLoad> _future;

  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _descriptionCtrl = TextEditingController();
  final _officeNameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _coverCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  final _websiteCtrl = TextEditingController();
  final _facebookCtrl = TextEditingController();
  final _hotlineCtrl = TextEditingController();
  final _sloganCtrl = TextEditingController();
  final _welcomeCtrl = TextEditingController();

  SubTenantProfile? _profile;
  SubTenantCityProfileData? _details;

  bool _saving = false;
  bool _dirty = false;
  int _selectedIndex = 0;

  String _defaultVisibility = 'visible';
  String _defaultSpotStatus = 'active';

  bool _enableAiSuggestions = true;
  bool _diversePlaceTypes = true;
  bool _prioritizePopular = true;
  bool _prioritizeNearby = true;
  bool _prioritizeFood = true;
  bool _prioritizeNature = true;
  bool _prioritizeHistorical = true;

  bool _requireSpotVerification = true;
  bool _requireMapPin = true;
  bool _requireCoverImage = true;
  bool _autoPublishSpots = false;

  bool _allowInstantBooking = false;
  bool _manualBookingConfirmation = true;
  bool _allowCancellation = true;

  bool _driverAutoApproval = false;
  bool _requireDriverDocuments = true;
  bool _requireTodaVerification = true;

  bool _bookingNotifications = true;
  bool _driverNotifications = true;
  bool _reviewNotifications = true;
  bool _emailNotifications = true;

  bool _revenueTracking = true;
  bool _spotPopularityTracking = true;
  bool _driverAnalytics = true;
  bool _monthlyReports = true;

  final List<_SettingsSection> _sections = const [
    _SettingsSection('General', Icons.settings_rounded),
    _SettingsSection('Tourism Office', Icons.business_rounded),
    _SettingsSection('Branding', Icons.palette_rounded),
    _SettingsSection('Packages', Icons.inventory_2_rounded),
    _SettingsSection('Bookings', Icons.confirmation_number_rounded),
    _SettingsSection('Drivers', Icons.directions_bike_rounded),
    _SettingsSection('Tourist Spots', Icons.place_rounded),
    _SettingsSection('AI Suggestions', Icons.auto_awesome_rounded),
    _SettingsSection('Notifications', Icons.notifications_rounded),
    _SettingsSection('Analytics', Icons.analytics_rounded),
    _SettingsSection('Security', Icons.security_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();

    for (final controller in [
      _descriptionCtrl,
      _officeNameCtrl,
      _contactCtrl,
      _emailCtrl,
      _addressCtrl,
      _coverCtrl,
      _logoCtrl,
      _websiteCtrl,
      _facebookCtrl,
      _hotlineCtrl,
      _sloganCtrl,
      _welcomeCtrl,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<_SettingsLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final details = await _service.loadCityProfile(profile);

    _profile = profile;
    _details = details;

    _cityCtrl.text = profile.assignedCity;
    _provinceCtrl.text = profile.province.isEmpty ? 'Bulacan' : profile.province;
    _descriptionCtrl.text = details.description;
    _officeNameCtrl.text = details.tourismOfficeName;
    _contactCtrl.text = details.contactNumber;
    _emailCtrl.text = details.email;
    _addressCtrl.text = details.officeAddress;
    _coverCtrl.text = details.coverImageUrl;
    _logoCtrl.text = details.logoImageUrl;

    return _SettingsLoad(profile: profile, details: details);
  }

  void _reload() {
    setState(() {
      _dirty = false;
      _future = _load();
    });
  }

  @override
  void dispose() {
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _descriptionCtrl.dispose();
    _officeNameCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _coverCtrl.dispose();
    _logoCtrl.dispose();
    _websiteCtrl.dispose();
    _facebookCtrl.dispose();
    _hotlineCtrl.dispose();
    _sloganCtrl.dispose();
    _welcomeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();
    if (!_formKey.currentState!.validate()) return;

    final profile = _profile;
    if (profile == null) return;

    setState(() => _saving = true);

    try {
      await _service.saveCityProfile(
        profile,
        SubTenantCityProfileData(
          city: profile.assignedCity,
          province: profile.province.isEmpty ? 'Bulacan' : profile.province,
          description: _descriptionCtrl.text.trim(),
          tourismOfficeName: _officeNameCtrl.text.trim(),
          contactNumber: _contactCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          officeAddress: _addressCtrl.text.trim(),
          coverImageUrl: _coverCtrl.text.trim(),
          logoImageUrl: _logoCtrl.text.trim(),
          detailsTableAvailable: true,
        ),
      );

      if (!mounted) return;
      setState(() => _dirty = false);
      showSubTenantSnack(context, 'Settings saved.', error: false);
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to save settings: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 6,
      title: 'Settings',
      subtitle: 'Manage your city tourism office, AI, booking, driver, and platform preferences.',
      actions: [
        if (_dirty)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: const Color(0xFFFFFBEB),
              borderRadius: BorderRadius.circular(999),
              border: Border.all(color: const Color(0xFFFDE68A)),
            ),
            child: const Text(
              'Unsaved changes',
              style: TextStyle(
                color: Color(0xFFB45309),
                fontSize: 12,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        IconButton(
          onPressed: _reload,
          tooltip: 'Refresh settings',
          icon: const Icon(Icons.refresh_rounded),
          color: SubTenantColors.text,
        ),
      ],
      child: FutureBuilder<_SettingsLoad>(
        future: _future,
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const SubTenantLoadingView();
          }

          if (snapshot.hasError) {
            return SubTenantErrorView(
              message: snapshot.error.toString(),
              onRetry: _reload,
            );
          }

          final data = snapshot.data!;

          return Form(
            key: _formKey,
            child: Responsive.isDesktop(context)
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _HeaderPreview(
                          details: data.details,
                          officeNameCtrl: _officeNameCtrl,
                          sloganCtrl: _sloganCtrl,
                          logoCtrl: _logoCtrl,
                          coverCtrl: _coverCtrl,
                        ),
                        const SizedBox(height: 12),
                        if (!data.details.detailsTableAvailable) ...[
                          const _ProfileNotice(),
                          const SizedBox(height: 12),
                        ],
                        Expanded(
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final h = constraints.maxHeight;
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: 270,
                                    height: h,
                                    child: _SettingsNav(
                                      sections: _sections,
                                      selectedIndex: _selectedIndex,
                                      onSelected: (index) {
                                        setState(() => _selectedIndex = index);
                                      },
                                    ),
                                  ),
                                  const SizedBox(width: 18),
                                  Expanded(
                                    child: SizedBox(
                                      height: h,
                                      child: SingleChildScrollView(
                                        child: ConstrainedBox(
                                          constraints: BoxConstraints(
                                            minHeight: h,
                                          ),
                                          child: _selectedContent(data),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          ),
                        ),
                        const SizedBox(height: 12),
                        _SaveBar(
                          dirty: _dirty,
                          saving: _saving,
                          onCancel: _reload,
                          onSave: _save,
                        ),
                      ],
                    ),
                  )
                : ResponsivePageContainer(
                    children: [
                      _HeaderPreview(
                        details: data.details,
                        officeNameCtrl: _officeNameCtrl,
                        sloganCtrl: _sloganCtrl,
                        logoCtrl: _logoCtrl,
                        coverCtrl: _coverCtrl,
                      ),
                      const SizedBox(height: 16),
                      if (!data.details.detailsTableAvailable) ...[
                        const _ProfileNotice(),
                        const SizedBox(height: 16),
                      ],
                      _MobileSettingsTabs(
                        sections: _sections,
                        selectedIndex: _selectedIndex,
                        onSelected: (index) {
                          setState(() => _selectedIndex = index);
                        },
                      ),
                      const SizedBox(height: 14),
                      _selectedContent(data),
                      const SizedBox(height: 18),
                      _SaveBar(
                        dirty: _dirty,
                        saving: _saving,
                        onCancel: _reload,
                        onSave: _save,
                      ),
                    ],
                  ),
          );
        },
      ),
    );
  }

  Widget _selectedContent(_SettingsLoad data) {
    switch (_selectedIndex) {
      case 0:
        return _generalSettings();
      case 1:
        return _tourismOfficeSettings();
      case 2:
        return _brandingSettings();
      case 3:
        return _packageSettings();
      case 4:
        return _bookingSettings();
      case 5:
        return _driverSettings();
      case 6:
        return _touristSpotSettings();
      case 7:
        return _aiSettings();
      case 8:
        return _notificationSettings();
      case 9:
        return _analyticsSettings();
      case 10:
        return _securitySettings(data.profile);
      default:
        return _generalSettings();
    }
  }

  Widget _generalSettings() {
    return _SettingsContent(
      title: 'General Settings',
      subtitle: 'Basic public identity and tenant-locked location.',
      children: [
        _TwoColumn(
          left: SubTenantTextField(
            controller: _cityCtrl,
            label: 'City / Municipality',
            enabled: false,
          ),
          right: SubTenantTextField(
            controller: _provinceCtrl,
            label: 'Province',
            enabled: false,
          ),
        ),
        const SizedBox(height: 14),
        SubTenantTextField(
          controller: _officeNameCtrl,
          label: 'Tourism Office Name',
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        SubTenantTextField(
          controller: _descriptionCtrl,
          label: 'Office Description',
          maxLines: 4,
        ),
      ],
    );
  }

  Widget _tourismOfficeSettings() {
    return _SettingsContent(
      title: 'Tourism Office',
      subtitle: 'Contact details used in tourist-facing pages and support.',
      children: [
        _TwoColumn(
          left: SubTenantTextField(
            controller: _contactCtrl,
            label: 'Contact Number',
            keyboardType: TextInputType.phone,
          ),
          right: SubTenantTextField(
            controller: _hotlineCtrl,
            label: 'Tourism Hotline',
            keyboardType: TextInputType.phone,
          ),
        ),
        const SizedBox(height: 14),
        SubTenantTextField(
          controller: _emailCtrl,
          label: 'Email Address',
          keyboardType: TextInputType.emailAddress,
        ),
        const SizedBox(height: 14),
        SubTenantTextField(
          controller: _addressCtrl,
          label: 'Office Address',
          maxLines: 3,
        ),
        const SizedBox(height: 14),
        _TwoColumn(
          left: SubTenantTextField(
            controller: _websiteCtrl,
            label: 'Website URL',
            keyboardType: TextInputType.url,
          ),
          right: SubTenantTextField(
            controller: _facebookCtrl,
            label: 'Facebook Page',
            keyboardType: TextInputType.url,
          ),
        ),
      ],
    );
  }

  Widget _brandingSettings() {
    return _SettingsContent(
      title: 'Branding',
      subtitle: 'Customize how this city appears to tourists.',
      children: [
        _TwoColumn(
          left: SubTenantTextField(
            controller: _coverCtrl,
            label: 'Cover Image URL',
            keyboardType: TextInputType.url,
          ),
          right: SubTenantTextField(
            controller: _logoCtrl,
            label: 'City Logo / Image URL',
            keyboardType: TextInputType.url,
          ),
        ),
        const SizedBox(height: 14),
        SubTenantTextField(
          controller: _sloganCtrl,
          label: 'Tourism Slogan',
          hint: 'e.g. Discover the heart of Bulacan',
        ),
        const SizedBox(height: 14),
        SubTenantTextField(
          controller: _welcomeCtrl,
          label: 'Welcome Message',
          maxLines: 3,
        ),
        const SizedBox(height: 16),
        _ImagePreviewRow(coverCtrl: _coverCtrl, logoCtrl: _logoCtrl),
      ],
    );
  }

  Widget _packageSettings() {
    return _SettingsContent(
      title: 'Package Settings',
      subtitle: 'Default rules for packages created by this city.',
      children: [
        _DropdownTile(
          title: 'Default Package Visibility',
          value: _defaultVisibility,
          items: const {
            'visible': 'Visible',
            'hidden': 'Hidden',
          },
          onChanged: (value) {
            setState(() {
              _defaultVisibility = value;
              _dirty = true;
            });
          },
        ),
        const SizedBox(height: 12),
        _SwitchTile(
          icon: Icons.fact_check_rounded,
          title: 'Require Review Before Publish',
          subtitle: 'Packages remain pending until reviewed.',
          value: true,
          onChanged: (_) {},
        ),
        _SwitchTile(
          icon: Icons.calendar_month_rounded,
          title: 'Allow Multi-day Packages',
          subtitle: 'Enable packages with several itinerary days.',
          value: true,
          onChanged: (_) {},
        ),
      ],
    );
  }

  Widget _bookingSettings() {
    return _SettingsContent(
      title: 'Booking Settings',
      subtitle: 'Control how tourists book packages.',
      children: [
        _SwitchTile(
          icon: Icons.flash_on_rounded,
          title: 'Allow Instant Booking',
          subtitle: 'Tourists can book without manual approval.',
          value: _allowInstantBooking,
          onChanged: (value) {
            setState(() {
              _allowInstantBooking = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.assignment_turned_in_rounded,
          title: 'Manual Confirmation Required',
          subtitle: 'City admin confirms bookings first.',
          value: _manualBookingConfirmation,
          onChanged: (value) {
            setState(() {
              _manualBookingConfirmation = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.cancel_schedule_send_rounded,
          title: 'Allow Cancellations',
          subtitle: 'Tourists may cancel before the cutoff period.',
          value: _allowCancellation,
          onChanged: (value) {
            setState(() {
              _allowCancellation = value;
              _dirty = true;
            });
          },
        ),
      ],
    );
  }

  Widget _driverSettings() {
    return _SettingsContent(
      title: 'Driver Settings',
      subtitle: 'Local rules for verified tricycle tour guides.',
      children: [
        _SwitchTile(
          icon: Icons.verified_user_rounded,
          title: 'Auto-approve Drivers',
          subtitle: 'New drivers are approved automatically.',
          value: _driverAutoApproval,
          onChanged: (value) {
            setState(() {
              _driverAutoApproval = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.description_rounded,
          title: 'Require Driver Documents',
          subtitle: 'License, vehicle, and clearance documents are required.',
          value: _requireDriverDocuments,
          onChanged: (value) {
            setState(() {
              _requireDriverDocuments = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.groups_rounded,
          title: 'Require TODA Verification',
          subtitle: 'Driver must be verified under a local TODA.',
          value: _requireTodaVerification,
          onChanged: (value) {
            setState(() {
              _requireTodaVerification = value;
              _dirty = true;
            });
          },
        ),
      ],
    );
  }

  Widget _touristSpotSettings() {
    return _SettingsContent(
      title: 'Tourist Spot Settings',
      subtitle: 'Rules for manual spot creation and publishing.',
      children: [
        _DropdownTile(
          title: 'Default Spot Status',
          value: _defaultSpotStatus,
          items: const {
            'active': 'Active',
            'maintenance': 'Maintenance',
            'archived': 'Archived',
          },
          onChanged: (value) {
            setState(() {
              _defaultSpotStatus = value;
              _dirty = true;
            });
          },
        ),
        const SizedBox(height: 12),
        _SwitchTile(
          icon: Icons.verified_rounded,
          title: 'Require Spot Verification',
          subtitle: 'New tourist spots start as pending.',
          value: _requireSpotVerification,
          onChanged: (value) {
            setState(() {
              _requireSpotVerification = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.location_on_rounded,
          title: 'Require Map Pin',
          subtitle: 'Latitude and longitude must come from a map pin.',
          value: _requireMapPin,
          onChanged: (value) {
            setState(() {
              _requireMapPin = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.image_rounded,
          title: 'Require Cover Image',
          subtitle: 'Spots need an image before publishing.',
          value: _requireCoverImage,
          onChanged: (value) {
            setState(() {
              _requireCoverImage = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.public_rounded,
          title: 'Auto-publish New Spots',
          subtitle: 'Created spots immediately become visible.',
          value: _autoPublishSpots,
          onChanged: (value) {
            setState(() {
              _autoPublishSpots = value;
              _dirty = true;
            });
          },
        ),
      ],
    );
  }

  Widget _aiSettings() {
    return _SettingsContent(
      title: 'AI Suggestions',
      subtitle: 'Configure the local AI recommendation engine for packages and tourist discovery.',
      children: [
        _SwitchTile(
          icon: Icons.auto_awesome_rounded,
          title: 'Enable AI Smart Suggestions',
          subtitle: 'Suggest spots for packages and tourist screens.',
          value: _enableAiSuggestions,
          onChanged: (value) {
            setState(() {
              _enableAiSuggestions = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.category_rounded,
          title: 'Suggest Diverse Place Types',
          subtitle: 'Balance nature, food, sports, historical, church, and museum spots.',
          value: _diversePlaceTypes,
          onChanged: (value) {
            setState(() {
              _diversePlaceTypes = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.trending_up_rounded,
          title: 'Prioritize Popular Spots',
          subtitle: 'Use views and frequent package usage as ranking signals.',
          value: _prioritizePopular,
          onChanged: (value) {
            setState(() {
              _prioritizePopular = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.near_me_rounded,
          title: 'Prioritize Nearby Spots',
          subtitle: 'Recommend locations close to selected itinerary stops.',
          value: _prioritizeNearby,
          onChanged: (value) {
            setState(() {
              _prioritizeNearby = value;
              _dirty = true;
            });
          },
        ),
        const SizedBox(height: 10),
        _PreferenceGrid(
          items: [
            _PreferenceItem(
              label: 'Food',
              selected: _prioritizeFood,
              icon: Icons.restaurant_rounded,
              onTap: () {
                setState(() {
                  _prioritizeFood = !_prioritizeFood;
                  _dirty = true;
                });
              },
            ),
            _PreferenceItem(
              label: 'Nature',
              selected: _prioritizeNature,
              icon: Icons.terrain_rounded,
              onTap: () {
                setState(() {
                  _prioritizeNature = !_prioritizeNature;
                  _dirty = true;
                });
              },
            ),
            _PreferenceItem(
              label: 'Historical',
              selected: _prioritizeHistorical,
              icon: Icons.account_balance_rounded,
              onTap: () {
                setState(() {
                  _prioritizeHistorical = !_prioritizeHistorical;
                  _dirty = true;
                });
              },
            ),
          ],
        ),
      ],
    );
  }

  Widget _notificationSettings() {
    return _SettingsContent(
      title: 'Notifications',
      subtitle: 'Choose which updates the city admin receives.',
      children: [
        _SwitchTile(
          icon: Icons.confirmation_number_rounded,
          title: 'Booking Notifications',
          subtitle: 'New bookings, cancellations, and updates.',
          value: _bookingNotifications,
          onChanged: (value) {
            setState(() {
              _bookingNotifications = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.directions_bike_rounded,
          title: 'Driver Notifications',
          subtitle: 'Driver applications and assignment updates.',
          value: _driverNotifications,
          onChanged: (value) {
            setState(() {
              _driverNotifications = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.reviews_rounded,
          title: 'Review Notifications',
          subtitle: 'Tourist ratings and feedback.',
          value: _reviewNotifications,
          onChanged: (value) {
            setState(() {
              _reviewNotifications = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.email_rounded,
          title: 'Email Notifications',
          subtitle: 'Send important alerts to the office email.',
          value: _emailNotifications,
          onChanged: (value) {
            setState(() {
              _emailNotifications = value;
              _dirty = true;
            });
          },
        ),
      ],
    );
  }

  Widget _analyticsSettings() {
    return _SettingsContent(
      title: 'Analytics',
      subtitle: 'Enable reports that help the LGU monitor tourism performance.',
      children: [
        _SwitchTile(
          icon: Icons.payments_rounded,
          title: 'Revenue Tracking',
          subtitle: 'Track estimated revenue from completed bookings.',
          value: _revenueTracking,
          onChanged: (value) {
            setState(() {
              _revenueTracking = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.place_rounded,
          title: 'Spot Popularity Tracking',
          subtitle: 'Track views and package usage of tourist spots.',
          value: _spotPopularityTracking,
          onChanged: (value) {
            setState(() {
              _spotPopularityTracking = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.badge_rounded,
          title: 'Driver Analytics',
          subtitle: 'Monitor driver assignments, ratings, and completed tours.',
          value: _driverAnalytics,
          onChanged: (value) {
            setState(() {
              _driverAnalytics = value;
              _dirty = true;
            });
          },
        ),
        _SwitchTile(
          icon: Icons.summarize_rounded,
          title: 'Generate Monthly Reports',
          subtitle: 'Prepare monthly tourism performance summaries.',
          value: _monthlyReports,
          onChanged: (value) {
            setState(() {
              _monthlyReports = value;
              _dirty = true;
            });
          },
        ),
      ],
    );
  }

  Widget _securitySettings(SubTenantProfile profile) {
    return _SettingsContent(
      title: 'Security',
      subtitle: 'Account and admin access information.',
      children: [
        _SecurityTile(
          icon: Icons.person_rounded,
          title: 'Signed in as',
          value: profile.email.isEmpty ? profile.displayName : profile.email,
        ),
        _SecurityTile(
          icon: Icons.lock_rounded,
          title: 'Password',
          value: 'Managed through authentication settings',
        ),
        _SecurityTile(
          icon: Icons.admin_panel_settings_rounded,
          title: 'Role',
          value: profile.role,
        ),
        _SecurityTile(
          icon: Icons.location_city_rounded,
          title: 'Tenant Scope',
          value: profile.assignedCity,
        ),
      ],
    );
  }
}

class _SettingsContent extends StatelessWidget {
  const _SettingsContent({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.max,
        children: [
          SubTenantSectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 18),
          ...children,
        ],
      ),
    );
  }
}

class _SettingsNav extends StatelessWidget {
  const _SettingsNav({
    required this.sections,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_SettingsSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings Menu',
            style: TextStyle(
              color: SubTenantColors.text,
              fontSize: 16,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: List.generate(sections.length, (index) {
            final section = sections[index];
            final selected = index == selectedIndex;

            return Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () => onSelected(index),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 160),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 11,
                  ),
                  decoration: BoxDecoration(
                    color: selected
                        ? SubTenantColors.blue.withValues(alpha: .10)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected
                          ? SubTenantColors.blue.withValues(alpha: .22)
                          : Colors.transparent,
                    ),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        section.icon,
                        size: 18,
                        color: selected
                            ? SubTenantColors.blue
                            : SubTenantColors.muted,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          section.label,
                          style: TextStyle(
                            color: selected
                                ? SubTenantColors.blue
                                : SubTenantColors.text,
                            fontSize: 13,
                            fontWeight:
                                selected ? FontWeight.w900 : FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MobileSettingsTabs extends StatelessWidget {
  const _MobileSettingsTabs({
    required this.sections,
    required this.selectedIndex,
    required this.onSelected,
  });

  final List<_SettingsSection> sections;
  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 46,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: sections.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = index == selectedIndex;
          final section = sections[index];

          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onSelected(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected ? SubTenantColors.blue : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: selected ? SubTenantColors.blue : SubTenantColors.line,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    section.icon,
                    size: 16,
                    color: selected ? Colors.white : SubTenantColors.muted,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    section.label,
                    style: TextStyle(
                      color: selected ? Colors.white : SubTenantColors.muted,
                      fontWeight: FontWeight.w900,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _HeaderPreview extends StatelessWidget {
  const _HeaderPreview({
    required this.details,
    required this.officeNameCtrl,
    required this.sloganCtrl,
    required this.logoCtrl,
    required this.coverCtrl,
  });

  final SubTenantCityProfileData details;
  final TextEditingController officeNameCtrl;
  final TextEditingController sloganCtrl;
  final TextEditingController logoCtrl;
  final TextEditingController coverCtrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        officeNameCtrl,
        sloganCtrl,
        logoCtrl,
        coverCtrl,
      ]),
      builder: (_, __) {
        final cover =
            coverCtrl.text.trim().isEmpty ? details.coverImageUrl : coverCtrl.text.trim();
        final logo =
            logoCtrl.text.trim().isEmpty ? details.logoImageUrl : logoCtrl.text.trim();
        final office = officeNameCtrl.text.trim().isEmpty
            ? details.tourismOfficeName
            : officeNameCtrl.text.trim();

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: cover.isEmpty ? SubTenantColors.gradient : null,
            image: cover.isEmpty
                ? null
                : DecorationImage(
                    image: NetworkImage(cover),
                    fit: BoxFit.cover,
                    colorFilter: ColorFilter.mode(
                      Colors.black.withValues(alpha: .38),
                      BlendMode.darken,
                    ),
                  ),
            boxShadow: [
              BoxShadow(
                color: SubTenantColors.blue.withValues(alpha: .16),
                blurRadius: 24,
                offset: const Offset(0, 14),
              ),
            ],
          ),
          child: Align(
            alignment: Alignment.bottomLeft,
            child: Row(
              children: [
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: .94),
                    borderRadius: BorderRadius.circular(20),
                    image: logo.isEmpty
                        ? null
                        : DecorationImage(
                            image: NetworkImage(logo),
                            fit: BoxFit.cover,
                          ),
                  ),
                  child: logo.isEmpty
                      ? const Icon(
                          Icons.location_city_rounded,
                          color: SubTenantColors.blue,
                        )
                      : null,
                ),
                const SizedBox(width: 13),
                Expanded(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        details.city,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: Responsive.isDesktop(context) ? 30 : 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        office.isEmpty ? '${details.province} Tourism Office' : office,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .92),
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      if (sloganCtrl.text.trim().isNotEmpty)
                        Text(
                          sloganCtrl.text.trim(),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: Colors.white.withValues(alpha: .82),
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.dirty,
    required this.saving,
    required this.onCancel,
    required this.onSave,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onCancel;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Row(
        children: [
          Icon(
            dirty ? Icons.edit_note_rounded : Icons.check_circle_rounded,
            color: dirty ? const Color(0xFFF59E0B) : const Color(0xFF16A34A),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              dirty ? 'You have unsaved changes.' : 'All changes are saved.',
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          TextButton(
            onPressed: saving || !dirty ? null : onCancel,
            child: const Text('Cancel'),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 170,
            child: SubTenantGradientButton(
              label: 'Save Settings',
              icon: Icons.save_rounded,
              loading: saving,
              onPressed: dirty ? onSave : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _TwoColumn extends StatelessWidget {
  const _TwoColumn({
    required this.left,
    required this.right,
  });

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isDesktop(context)) {
      return Column(
        children: [
          left,
          const SizedBox(height: 14),
          right,
        ],
      );
    }

    return Row(
      children: [
        Expanded(child: left),
        const SizedBox(width: 14),
        Expanded(child: right),
      ],
    );
  }
}

class _SwitchTile extends StatelessWidget {
  const _SwitchTile({
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
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SubTenantColors.backgroundAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              color: SubTenantColors.blue.withValues(alpha: .09),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(icon, color: SubTenantColors.blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    height: 1.25,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            activeColor: SubTenantColors.blue,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }
}

class _DropdownTile extends StatelessWidget {
  const _DropdownTile({
    required this.title,
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String title;
  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          style: const TextStyle(
            color: SubTenantColors.text,
            fontWeight: FontWeight.w900,
            fontSize: 13,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<String>(
          value: value,
          isExpanded: true,
          decoration: InputDecoration(
            filled: true,
            fillColor: Colors.white,
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 14,
              vertical: 14,
            ),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: SubTenantColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: SubTenantColors.line),
            ),
          ),
          items: items.entries
              .map(
                (entry) => DropdownMenuItem(
                  value: entry.key,
                  child: Text(entry.value),
                ),
              )
              .toList(),
          onChanged: (value) {
            if (value != null) onChanged(value);
          },
        ),
      ],
    );
  }
}

class _PreferenceGrid extends StatelessWidget {
  const _PreferenceGrid({required this.items});

  final List<_PreferenceItem> items;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 10,
      runSpacing: 10,
      children: items.map((item) {
        return InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: item.onTap,
          child: Container(
            width: 160,
            padding: const EdgeInsets.all(13),
            decoration: BoxDecoration(
              color: item.selected
                  ? SubTenantColors.blue.withValues(alpha: .10)
                  : Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                color: item.selected
                    ? SubTenantColors.blue.withValues(alpha: .25)
                    : SubTenantColors.line,
              ),
            ),
            child: Row(
              children: [
                Icon(
                  item.icon,
                  color: item.selected
                      ? SubTenantColors.blue
                      : SubTenantColors.muted,
                ),
                const SizedBox(width: 9),
                Expanded(
                  child: Text(
                    item.label,
                    style: TextStyle(
                      color: item.selected
                          ? SubTenantColors.blue
                          : SubTenantColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _ImagePreviewRow extends StatelessWidget {
  const _ImagePreviewRow({
    required this.coverCtrl,
    required this.logoCtrl,
  });

  final TextEditingController coverCtrl;
  final TextEditingController logoCtrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([coverCtrl, logoCtrl]),
      builder: (_, __) {
        return _TwoColumn(
          left: _ImageBox(label: 'Cover Preview', url: coverCtrl.text.trim()),
          right: _ImageBox(label: 'Logo Preview', url: logoCtrl.text.trim()),
        );
      },
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({
    required this.label,
    required this.url,
  });

  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 150,
      clipBehavior: Clip.hardEdge,
      decoration: BoxDecoration(
        color: const Color(0xFFE4ECF7),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: url.isEmpty
          ? Center(
              child: Text(
                label,
                style: const TextStyle(
                  color: SubTenantColors.lightMuted,
                  fontWeight: FontWeight.w800,
                ),
              ),
            )
          : Image.network(
              url,
              fit: BoxFit.cover,
              width: double.infinity,
              errorBuilder: (_, __, ___) => Center(
                child: Text(
                  'Invalid $label',
                  style: const TextStyle(color: SubTenantColors.lightMuted),
                ),
              ),
            ),
    );
  }
}

class _SecurityTile extends StatelessWidget {
  const _SecurityTile({
    required this.icon,
    required this.title,
    required this.value,
  });

  final IconData icon;
  final String title;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SubTenantColors.backgroundAlt,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: SubTenantColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              style: const TextStyle(
                color: SubTenantColors.text,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
          Flexible(
            child: Text(
              value,
              textAlign: TextAlign.right,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileNotice extends StatelessWidget {
  const _ProfileNotice();

  @override
  Widget build(BuildContext context) {
    return DashboardSectionCard(
      child: Row(
        children: [
          const Icon(Icons.info_outline_rounded, color: SubTenantColors.blue),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'subtenant_details is not available. Contact and address fields will save to profiles as a fallback.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: SubTenantColors.muted,
                    fontWeight: FontWeight.w700,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SettingsSection {
  const _SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _PreferenceItem {
  const _PreferenceItem({
    required this.label,
    required this.selected,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final IconData icon;
  final VoidCallback onTap;
}

class _SettingsLoad {
  const _SettingsLoad({
    required this.profile,
    required this.details,
  });

  final SubTenantProfile profile;
  final SubTenantCityProfileData details;
}