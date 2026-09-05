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
  final _contactPersonCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();
  final _coverCtrl = TextEditingController();
  final _logoCtrl = TextEditingController();
  final _baseFareCtrl = TextEditingController();
  final _farePerKmCtrl = TextEditingController();
  final _minimumFareCtrl = TextEditingController();
  final _waitingFeeCtrl = TextEditingController();

  SubTenantProfile? _profile;

  bool _saving = false;
  bool _dirty = false;
  bool _hydrating = false;
  int _selectedIndex = 0;

  bool _officeNameCustomized = false;
  String _generatedOfficeName = '';
  String _localGovernmentType = 'municipality';

  final List<_SettingsSection> _sections = const [
    _SettingsSection('Office Settings', Icons.business_rounded),
    _SettingsSection('Branding', Icons.palette_rounded),
    _SettingsSection('Fare Matrix', Icons.payments_rounded),
    _SettingsSection('Security', Icons.security_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _future = _load();

    for (final controller in [
      _descriptionCtrl,
      _officeNameCtrl,
      _contactPersonCtrl,
      _contactCtrl,
      _emailCtrl,
      _addressCtrl,
      _coverCtrl,
      _logoCtrl,
      _baseFareCtrl,
      _farePerKmCtrl,
      _minimumFareCtrl,
      _waitingFeeCtrl,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (_hydrating) return;
    _officeNameCustomized =
        _officeNameCtrl.text.trim().toLowerCase() !=
        _generatedOfficeName.toLowerCase();
    if (!_dirty && mounted) setState(() => _dirty = true);
  }

  Future<_SettingsLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final results = await Future.wait([
      _service.loadCityProfile(profile),
      _service.loadFareSettings(profile),
    ]);
    final details = results[0] as SubTenantCityProfileData;
    final fare = results[1] as SubTenantFareSettings;

    _profile = profile;
    _hydrating = true;
    _cityCtrl.text = profile.assignedCity;
    _provinceCtrl.text = profile.province.isEmpty
        ? 'Bulacan'
        : profile.province;
    _descriptionCtrl.text = details.description;
    _officeNameCtrl.text = details.tourismOfficeName;
    _contactPersonCtrl.text = details.contactPerson;
    _contactCtrl.text = details.contactNumber;
    _emailCtrl.text = details.email;
    _addressCtrl.text = details.officeAddress;
    _coverCtrl.text = details.coverImageUrl;
    _logoCtrl.text = details.logoImageUrl;
    _generatedOfficeName = defaultTourismOfficeName(
      assignedLocation: profile.assignedCity,
      localGovernmentType: details.localGovernmentType,
    );
    _localGovernmentType = details.localGovernmentType;
    _officeNameCustomized = details.officeNameCustomized;
    _baseFareCtrl.text = _moneyText(fare.baseFare);
    _farePerKmCtrl.text = _moneyText(fare.farePerKm);
    _minimumFareCtrl.text = _moneyText(fare.minimumFare);
    _waitingFeeCtrl.text = _moneyText(fare.waitingFee);
    _hydrating = false;
    _dirty = false;

    return _SettingsLoad(profile: profile, details: details, fare: fare);
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
    _contactPersonCtrl.dispose();
    _contactCtrl.dispose();
    _emailCtrl.dispose();
    _addressCtrl.dispose();
    _coverCtrl.dispose();
    _logoCtrl.dispose();
    _baseFareCtrl.dispose();
    _farePerKmCtrl.dispose();
    _minimumFareCtrl.dispose();
    _waitingFeeCtrl.dispose();
    super.dispose();
  }

  double _moneyValue(TextEditingController controller) {
    return double.tryParse(controller.text.trim().replaceAll(',', '')) ?? 0;
  }

  String _moneyText(double value) {
    if (value == 0) return '0';
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  String? _nonNegativeMoneyValidator(String? value) {
    final parsed = double.tryParse((value ?? '').trim().replaceAll(',', ''));
    if (parsed == null) return 'Enter a valid amount';
    if (parsed < 0) return 'Amount cannot be negative';
    return null;
  }

  SubTenantFareSettings _fareFromState(SubTenantProfile profile) {
    return SubTenantFareSettings(
      subtenantId: profile.id,
      city: profile.assignedCity,
      baseFare: _moneyValue(_baseFareCtrl),
      farePerKm: _moneyValue(_farePerKmCtrl),
      minimumFare: _moneyValue(_minimumFareCtrl),
      waitingFee: _moneyValue(_waitingFeeCtrl),
    );
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
          contactPerson: _contactPersonCtrl.text.trim(),
          contactNumber: _contactCtrl.text.trim(),
          email: _emailCtrl.text.trim(),
          officeAddress: _addressCtrl.text.trim(),
          coverImageUrl: _coverCtrl.text.trim(),
          logoImageUrl: _logoCtrl.text.trim(),
          localGovernmentType: _localGovernmentType,
          officeNameCustomized: _officeNameCustomized,
          detailsTableAvailable: true,
        ),
      );
      await _service.saveFareSettings(profile, _fareFromState(profile));

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
      subtitle: 'Manage your tourism office profile and active fare settings.',
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
                          logoCtrl: _logoCtrl,
                          coverCtrl: _coverCtrl,
                        ),
                        const SizedBox(height: 12),
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
                        logoCtrl: _logoCtrl,
                        coverCtrl: _coverCtrl,
                      ),
                      const SizedBox(height: 16),
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
        return _officeSettings();
      case 1:
        return _brandingSettings();
      case 2:
        return _fareMatrixSettings(data.profile);
      case 3:
        return _securitySettings(data.profile);
      default:
        return _officeSettings();
    }
  }

  Widget _officeSettings() {
    return _SettingsContent(
      title: 'Office Settings',
      subtitle:
          'Public office identity and contact details. Assignment is managed by the Provincial Admin.',
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
          label: 'Office Name',
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        SubTenantTextField(
          controller: _contactPersonCtrl,
          label: 'Contact Person',
          validator: (value) =>
              (value ?? '').trim().isEmpty ? 'Required' : null,
        ),
        const SizedBox(height: 14),
        SubTenantTextField(
          controller: _contactCtrl,
          label: 'Contact Number',
          keyboardType: TextInputType.phone,
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
        SubTenantTextField(
          controller: _descriptionCtrl,
          label: 'Office Description',
          maxLines: 4,
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
        const SizedBox(height: 16),
        _ImagePreviewRow(coverCtrl: _coverCtrl, logoCtrl: _logoCtrl),
      ],
    );
  }

  Widget _fareMatrixSettings(SubTenantProfile profile) {
    final fare = _fareFromState(profile);
    final sample = fare.calculate(routeDistanceKm: 8);

    return _SettingsContent(
      title: 'Fare Matrix',
      subtitle:
          'Pricing basis used to suggest package budgets from route distance and waiting time.',
      children: [
        _TwoColumn(
          left: SubTenantTextField(
            controller: _baseFareCtrl,
            label: 'Base Fare (PHP)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _nonNegativeMoneyValidator,
          ),
          right: SubTenantTextField(
            controller: _farePerKmCtrl,
            label: 'Fare per Kilometer',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _nonNegativeMoneyValidator,
          ),
        ),
        const SizedBox(height: 14),
        _TwoColumn(
          left: SubTenantTextField(
            controller: _minimumFareCtrl,
            label: 'Minimum Fare',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _nonNegativeMoneyValidator,
          ),
          right: SubTenantTextField(
            controller: _waitingFeeCtrl,
            label: 'Waiting Fee (PHP / hour)',
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            validator: _nonNegativeMoneyValidator,
          ),
        ),
        const SizedBox(height: 16),
        _FarePreview(calculation: sample),
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
                                  fontWeight: selected
                                      ? FontWeight.w900
                                      : FontWeight.w700,
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
        separatorBuilder: (_, _) => const SizedBox(width: 8),
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
    required this.logoCtrl,
    required this.coverCtrl,
  });

  final SubTenantCityProfileData details;
  final TextEditingController officeNameCtrl;
  final TextEditingController logoCtrl;
  final TextEditingController coverCtrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([officeNameCtrl, logoCtrl, coverCtrl]),
      builder: (_, _) {
        final cover = coverCtrl.text.trim().isEmpty
            ? details.coverImageUrl
            : coverCtrl.text.trim();
        final logo = logoCtrl.text.trim().isEmpty
            ? details.logoImageUrl
            : logoCtrl.text.trim();
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
                        office.isEmpty
                            ? '${details.province} Tourism Office'
                            : office,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white.withValues(alpha: .92),
                          fontWeight: FontWeight.w800,
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

class _FarePreview extends StatelessWidget {
  const _FarePreview({required this.calculation});

  final FareCalculation calculation;

  String _money(double value) => 'PHP ${value.toStringAsFixed(0)}';

  @override
  Widget build(BuildContext context) {
    final rows = [
      ('Base fare', calculation.baseFare),
      ('Distance fee sample', calculation.distanceFee),
      ('Waiting fee (per hour sample)', calculation.waitingFee),
      ('Minimum fare adjustment', calculation.minimumFareAdjustment),
    ];

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SubTenantColors.blue.withValues(alpha: .07),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.blue.withValues(alpha: .14)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Sample suggested package price',
            style: TextStyle(
              color: SubTenantColors.text,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'For an 8 km route with 4 passengers. Package forms use the same formula.',
            style: TextStyle(
              color: SubTenantColors.muted,
              fontSize: 12,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          ...rows.map(
            (row) => Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      row.$1,
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  Text(
                    _money(row.$2),
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
          ),
          const Divider(height: 18, color: SubTenantColors.line),
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Suggested total',
                  style: TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
              Text(
                _money(calculation.total),
                style: const TextStyle(
                  color: SubTenantColors.blue,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ],
      ),
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
      child: LayoutBuilder(
        builder: (context, constraints) {
          final status = Row(
            children: [
              Icon(
                dirty ? Icons.edit_note_rounded : Icons.check_circle_rounded,
                color: dirty
                    ? const Color(0xFFF59E0B)
                    : const Color(0xFF16A34A),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  dirty
                      ? 'You have unsaved changes.'
                      : 'All changes are saved.',
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          );
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
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
          );

          if (constraints.maxWidth < 560) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                const SizedBox(height: 12),
                Align(alignment: Alignment.centerRight, child: actions),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 16),
              actions,
            ],
          );
        },
      ),
    );
  }
}

class _TwoColumn extends StatelessWidget {
  const _TwoColumn({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (!Responsive.isDesktop(context)) {
      return Column(children: [left, const SizedBox(height: 14), right]);
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

class _ImagePreviewRow extends StatelessWidget {
  const _ImagePreviewRow({required this.coverCtrl, required this.logoCtrl});

  final TextEditingController coverCtrl;
  final TextEditingController logoCtrl;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([coverCtrl, logoCtrl]),
      builder: (_, _) {
        return _TwoColumn(
          left: _ImageBox(label: 'Cover Preview', url: coverCtrl.text.trim()),
          right: _ImageBox(label: 'Logo Preview', url: logoCtrl.text.trim()),
        );
      },
    );
  }
}

class _ImageBox extends StatelessWidget {
  const _ImageBox({required this.label, required this.url});

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
              errorBuilder: (_, _, _) => Center(
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

class _SettingsSection {
  const _SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _SettingsLoad {
  const _SettingsLoad({
    required this.profile,
    required this.details,
    required this.fare,
  });

  final SubTenantProfile profile;
  final SubTenantCityProfileData details;
  final SubTenantFareSettings fare;
}
