import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/admin/admin_models.dart';
import 'package:touristrike/screens/admin/layouts/provincial_admin_shell.dart';
import 'package:touristrike/screens/admin/provincial_admin_nav.dart';
import 'package:touristrike/screens/admin/provincial_admin_service.dart';
import 'package:touristrike/screens/admin/widgets/admin_common.dart';
import 'package:touristrike/screens/admin/widgets/admin_section_card.dart';
import 'package:touristrike/screens/admin/widgets/provincial_admin_style.dart';

class ProvincialAdminSettingsScreen extends StatefulWidget {
  const ProvincialAdminSettingsScreen({super.key});

  @override
  State<ProvincialAdminSettingsScreen> createState() =>
      _ProvincialAdminSettingsScreenState();
}

class _ProvincialAdminSettingsScreenState
    extends State<ProvincialAdminSettingsScreen> {
  final ProvincialAdminService _service = ProvincialAdminService();

  late Future<ProvincialAdminSettingsData> _future;
  ProvincialAdminSettingsData? _original;
  int _selectedSection = 0;
  bool _hydrating = false;
  bool _saving = false;
  bool _uploadingLogo = false;
  bool _uploadingCover = false;
  bool _savingPassword = false;
  bool _obscurePassword = true;
  bool _obscureConfirmation = true;

  final _officeName = TextEditingController();
  final _province = TextEditingController();
  final _officeAddress = TextEditingController();
  final _contactPerson = TextEditingController();
  final _contactNumber = TextEditingController();
  final _officialEmail = TextEditingController();
  final _displayName = TextEditingController();
  final _logoUrl = TextEditingController();
  final _coverUrl = TextEditingController();
  final _cancellationHours = TextEditingController();
  final _terms = TextEditingController();
  final _cancellationPolicy = TextEditingController();
  final _privacy = TextEditingController();
  final _newPassword = TextEditingController();
  final _confirmPassword = TextEditingController();

  bool _cityApplications = true;
  bool _driverUpdates = true;
  bool _bookingIssues = true;
  bool _paymentDisputes = true;

  static const _sections = <_SettingsSection>[
    _SettingsSection('Provincial Office', Icons.account_balance_rounded),
    _SettingsSection('Branding', Icons.imagesearch_roller_rounded),
    _SettingsSection('Booking Policies', Icons.policy_rounded),
    _SettingsSection('Notifications', Icons.notifications_active_rounded),
    _SettingsSection('Security & Account', Icons.security_rounded),
  ];

  List<TextEditingController> get _settingsControllers => [
    _officeName,
    _officeAddress,
    _contactPerson,
    _contactNumber,
    _officialEmail,
    _displayName,
    _logoUrl,
    _coverUrl,
    _cancellationHours,
    _terms,
    _cancellationPolicy,
    _privacy,
  ];

  @override
  void initState() {
    super.initState();
    for (final controller in _settingsControllers) {
      controller.addListener(_onDraftChanged);
    }
    _future = _load();
  }

  @override
  void dispose() {
    for (final controller in [
      ..._settingsControllers,
      _province,
      _newPassword,
      _confirmPassword,
    ]) {
      controller.dispose();
    }
    super.dispose();
  }

  void _onDraftChanged() {
    if (!_hydrating && mounted) setState(() {});
  }

  Future<ProvincialAdminSettingsData> _load() async {
    final data = await _service.loadAdminSettings();
    if (!mounted) return data;
    _hydrate(data);
    return data;
  }

  void _hydrate(ProvincialAdminSettingsData data) {
    _hydrating = true;
    _original = data;
    _officeName.text = data.office.officeName;
    _province.text = data.profile.province;
    _officeAddress.text = data.office.officeAddress;
    _contactPerson.text = data.office.contactPerson;
    _contactNumber.text = data.office.contactNumber;
    _officialEmail.text = data.office.officialEmail;
    _displayName.text = data.office.displayName;
    _logoUrl.text = data.office.logoUrl;
    _coverUrl.text = data.office.coverImageUrl;
    _cancellationHours.text = data.bookingPolicies.freeCancellationHours
        .toString();
    _terms.text = data.bookingPolicies.termsAndConditions;
    _cancellationPolicy.text = data.bookingPolicies.cancellationPolicy;
    _privacy.text = data.bookingPolicies.dataPrivacyNotice;
    _cityApplications = data.notifications.cityApplications;
    _driverUpdates = data.notifications.driverStatusUpdates;
    _bookingIssues = data.notifications.bookingIssues;
    _paymentDisputes = data.notifications.paymentDisputes;
    _hydrating = false;
  }

  void _reload() {
    setState(() => _future = _load());
  }

  bool get _officeDirty {
    final original = _original?.office;
    return original != null &&
        (_officeName.text.trim() != original.officeName ||
            _officeAddress.text.trim() != original.officeAddress ||
            _contactPerson.text.trim() != original.contactPerson ||
            _contactNumber.text.trim() != original.contactNumber ||
            _officialEmail.text.trim() != original.officialEmail);
  }

  bool get _brandingDirty {
    final original = _original?.office;
    return original != null &&
        (_displayName.text.trim() != original.displayName ||
            _logoUrl.text.trim() != original.logoUrl ||
            _coverUrl.text.trim() != original.coverImageUrl);
  }

  bool get _policiesDirty {
    final original = _original?.bookingPolicies;
    return original != null &&
        (_cancellationHours.text.trim() !=
                original.freeCancellationHours.toString() ||
            _terms.text.trim() != original.termsAndConditions ||
            _cancellationPolicy.text.trim() != original.cancellationPolicy ||
            _privacy.text.trim() != original.dataPrivacyNotice);
  }

  bool get _notificationsDirty {
    final original = _original?.notifications;
    return original != null &&
        (_cityApplications != original.cityApplications ||
            _driverUpdates != original.driverStatusUpdates ||
            _bookingIssues != original.bookingIssues ||
            _paymentDisputes != original.paymentDisputes);
  }

  bool get _currentDirty => switch (_selectedSection) {
    0 => _officeDirty,
    1 => _brandingDirty,
    2 => _policiesDirty,
    3 => _notificationsDirty,
    _ => false,
  };

  bool get _hasDirty =>
      _officeDirty || _brandingDirty || _policiesDirty || _notificationsDirty;

  ProvincialOfficeSettings get _officeDraft {
    return ProvincialOfficeSettings(
      officeName: _officeName.text.trim(),
      officeAddress: _officeAddress.text.trim(),
      contactPerson: _contactPerson.text.trim(),
      contactNumber: _contactNumber.text.trim(),
      officialEmail: _officialEmail.text.trim(),
      displayName: _displayName.text.trim(),
      logoUrl: _logoUrl.text.trim(),
      coverImageUrl: _coverUrl.text.trim(),
    );
  }

  ProvincialBookingPolicySettings get _policyDraft {
    final original = _original!.bookingPolicies;
    return ProvincialBookingPolicySettings(
      freeCancellationHours: int.tryParse(_cancellationHours.text.trim()) ?? 0,
      termsAndConditions: _terms.text.trim(),
      cancellationPolicy: _cancellationPolicy.text.trim(),
      dataPrivacyNotice: _privacy.text.trim(),
      termsPolicyId: original.termsPolicyId,
      cancellationPolicyId: original.cancellationPolicyId,
      privacyPolicyId: original.privacyPolicyId,
    );
  }

  ProvincialNotificationPreferences get _notificationDraft =>
      ProvincialNotificationPreferences(
        cityApplications: _cityApplications,
        driverStatusUpdates: _driverUpdates,
        bookingIssues: _bookingIssues,
        paymentDisputes: _paymentDisputes,
      );

  String? _validateCurrentSection() {
    if (_selectedSection == 0) {
      if (_officeName.text.trim().isEmpty) return 'Office Name is required.';
      if (_contactPerson.text.trim().isEmpty) {
        return 'Contact Person is required.';
      }
      final email = _officialEmail.text.trim();
      if (email.isEmpty ||
          !RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(email)) {
        return 'Enter a valid official email address.';
      }
    }
    if (_selectedSection == 1 && _displayName.text.trim().isEmpty) {
      return 'Display Name is required.';
    }
    if (_selectedSection == 2) {
      final hours = int.tryParse(_cancellationHours.text.trim());
      if (hours == null || hours < 1 || hours > 720) {
        return 'Cancellation cutoff must be from 1 to 720 hours.';
      }
      if (_terms.text.trim().isEmpty ||
          _cancellationPolicy.text.trim().isEmpty ||
          _privacy.text.trim().isEmpty) {
        return 'All policy documents must contain text.';
      }
    }
    return null;
  }

  Future<void> _saveCurrent() async {
    if (_saving || !_currentDirty) return;
    final validation = _validateCurrentSection();
    if (validation != null) {
      showAdminSnack(context, validation);
      return;
    }

    FocusScope.of(context).unfocus();
    setState(() => _saving = true);
    try {
      switch (_selectedSection) {
        case 0:
          await _service.updateProvincialOffice(office: _officeDraft);
        case 1:
          await _service.updateBranding(
            displayName: _displayName.text,
            logoUrl: _logoUrl.text,
            coverImageUrl: _coverUrl.text,
          );
        case 2:
          await _service.updateBookingPolicies(policies: _policyDraft);
        case 3:
          await _service.updateNotificationPreferences(_notificationDraft);
      }
      if (!mounted) return;
      showAdminSnack(
        context,
        '${_sections[_selectedSection].label} saved.',
        error: false,
      );
      setState(() => _future = _load());
    } catch (error) {
      if (mounted) showAdminSnack(context, 'Unable to save settings: $error');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _resetCurrent() {
    final original = _original;
    if (original == null) return;
    _hydrating = true;
    switch (_selectedSection) {
      case 0:
        _officeName.text = original.office.officeName;
        _officeAddress.text = original.office.officeAddress;
        _contactPerson.text = original.office.contactPerson;
        _contactNumber.text = original.office.contactNumber;
        _officialEmail.text = original.office.officialEmail;
      case 1:
        _displayName.text = original.office.displayName;
        _logoUrl.text = original.office.logoUrl;
        _coverUrl.text = original.office.coverImageUrl;
      case 2:
        _cancellationHours.text = original.bookingPolicies.freeCancellationHours
            .toString();
        _terms.text = original.bookingPolicies.termsAndConditions;
        _cancellationPolicy.text = original.bookingPolicies.cancellationPolicy;
        _privacy.text = original.bookingPolicies.dataPrivacyNotice;
      case 3:
        _cityApplications = original.notifications.cityApplications;
        _driverUpdates = original.notifications.driverStatusUpdates;
        _bookingIssues = original.notifications.bookingIssues;
        _paymentDisputes = original.notifications.paymentDisputes;
    }
    _hydrating = false;
    setState(() {});
  }

  Future<void> _pickBrandingImage({required bool logo}) async {
    final profile = _original?.profile;
    if (profile == null || _uploadingLogo || _uploadingCover) return;
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: logo ? 1200 : 2200,
      imageQuality: 88,
    );
    if (file == null) return;

    final extension = file.name.contains('.')
        ? file.name.split('.').last.toLowerCase()
        : '';
    const supported = {'jpg', 'jpeg', 'png', 'webp'};
    if (!supported.contains(extension)) {
      if (mounted) {
        showAdminSnack(context, 'Use JPG, PNG, or WebP images only.');
      }
      return;
    }
    final bytes = await file.readAsBytes();
    if (bytes.length > 5 * 1024 * 1024) {
      if (mounted) showAdminSnack(context, 'Image must be 5 MB or smaller.');
      return;
    }

    setState(() {
      if (logo) {
        _uploadingLogo = true;
      } else {
        _uploadingCover = true;
      }
    });
    try {
      final url = await _service.uploadProvincialBranding(
        province: profile.province,
        fileName: file.name,
        bytes: bytes,
        contentType: switch (extension) {
          'png' => 'image/png',
          'webp' => 'image/webp',
          _ => 'image/jpeg',
        },
      );
      if (!mounted) return;
      (logo ? _logoUrl : _coverUrl).text = url;
      showAdminSnack(
        context,
        '${logo ? 'Logo' : 'Banner'} uploaded. Save Branding to publish it.',
        error: false,
      );
    } catch (error) {
      if (mounted) showAdminSnack(context, 'Image upload failed: $error');
    } finally {
      if (mounted) {
        setState(() {
          _uploadingLogo = false;
          _uploadingCover = false;
        });
      }
    }
  }

  List<String> _passwordErrors(String password) {
    final errors = <String>[];
    if (password.length < 8) errors.add('At least 8 characters');
    if (!RegExp(r'[A-Z]').hasMatch(password)) errors.add('An uppercase letter');
    if (!RegExp(r'[a-z]').hasMatch(password)) errors.add('A lowercase letter');
    if (!RegExp(r'\d').hasMatch(password)) errors.add('A number');
    if (!RegExp(
      r'''[!@#$%^&*(),.?":{}|<>_\-+=\[\]\\;'`~/]''',
    ).hasMatch(password)) {
      errors.add('A special character');
    }
    return errors;
  }

  Future<void> _changePassword() async {
    final password = _newPassword.text;
    final confirmation = _confirmPassword.text;
    final errors = _passwordErrors(password);
    if (errors.isNotEmpty) {
      showAdminSnack(context, 'Password needs ${errors.first.toLowerCase()}.');
      return;
    }
    if (password != confirmation) {
      showAdminSnack(context, 'New password and confirmation do not match.');
      return;
    }
    setState(() => _savingPassword = true);
    try {
      await _service.changePassword(password);
      if (!mounted) return;
      _newPassword.clear();
      _confirmPassword.clear();
      showAdminSnack(context, 'Password updated successfully.', error: false);
    } catch (error) {
      if (mounted) showAdminSnack(context, 'Unable to update password: $error');
    } finally {
      if (mounted) setState(() => _savingPassword = false);
    }
  }

  Future<void> _confirmDiscardAndPop() async {
    final discard = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Discard unsaved changes?'),
        content: const Text(
          'Your changes have not been saved and will be lost.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep editing'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Discard'),
          ),
        ],
      ),
    );
    if (discard == true && mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return ProvincialAdminShell(
      current: ProvincialAdminDestination.settings,
      title: 'Settings',
      subtitle:
          'Manage provincial office information, policies, notifications, and account security.',
      child: PopScope(
        canPop: !_hasDirty,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop && _hasDirty) _confirmDiscardAndPop();
        },
        child: FutureBuilder<ProvincialAdminSettingsData>(
          future: _future,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const AdminLoadingView();
            }
            if (snapshot.hasError) {
              return AdminErrorView(
                message: snapshot.error.toString(),
                onRetry: _reload,
              );
            }
            return _buildLoaded(snapshot.data!);
          },
        ),
      ),
    );
  }

  Widget _buildLoaded(ProvincialAdminSettingsData data) {
    if (Responsive.isDesktop(context)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _HeaderPreview(
              data: data,
              officeNameController: _officeName,
              displayNameController: _displayName,
              logoController: _logoUrl,
              coverController: _coverUrl,
            ),
            const SizedBox(height: 12),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final height = constraints.maxHeight;
                  return Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 270,
                        height: height,
                        child: _SettingsNavigation(
                          sections: _sections,
                          selected: _selectedSection,
                          onSelected: (value) =>
                              setState(() => _selectedSection = value),
                        ),
                      ),
                      const SizedBox(width: 18),
                      Expanded(
                        child: SizedBox(
                          height: height,
                          child: SingleChildScrollView(
                            child: ConstrainedBox(
                              constraints: BoxConstraints(minHeight: height),
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
              dirty: _currentDirty,
              saving: _saving,
              onReset: _resetCurrent,
              onSave: _saveCurrent,
            ),
          ],
        ),
      );
    }

    return AdminPageContainer(
      children: [
        _HeaderPreview(
          data: data,
          officeNameController: _officeName,
          displayNameController: _displayName,
          logoController: _logoUrl,
          coverController: _coverUrl,
        ),
        const SizedBox(height: 16),
        _MobileSectionPicker(
          sections: _sections,
          selected: _selectedSection,
          onSelected: (value) => setState(() => _selectedSection = value),
        ),
        const SizedBox(height: 14),
        _selectedContent(data),
        const SizedBox(height: 18),
        _SaveBar(
          dirty: _currentDirty,
          saving: _saving,
          onReset: _resetCurrent,
          onSave: _saveCurrent,
        ),
      ],
    );
  }

  Widget _selectedContent(ProvincialAdminSettingsData data) {
    return switch (_selectedSection) {
      0 => _officeSection(),
      1 => _brandingSection(),
      2 => _policiesSection(),
      3 => _notificationsSection(),
      _ => _securitySection(data.profile),
    };
  }

  Widget _officeSection() {
    return _SettingsCard(
      title: 'Provincial Office',
      subtitle:
          'Public contact information for the Provincial Tourism Office. Province assignment is protected.',
      children: [
        _FieldRow(
          first: _AdminSettingsField(
            controller: _officeName,
            label: 'Office Name',
            icon: Icons.account_balance_outlined,
          ),
          second: _AdminSettingsField(
            controller: _province,
            label: 'Province',
            icon: Icons.map_outlined,
            readOnly: true,
            helperText: 'Managed by the account tenant assignment.',
          ),
        ),
        const SizedBox(height: 14),
        _AdminSettingsField(
          controller: _officeAddress,
          label: 'Office Address',
          icon: Icons.location_on_outlined,
          maxLines: 2,
        ),
        const SizedBox(height: 14),
        _FieldRow(
          first: _AdminSettingsField(
            controller: _contactPerson,
            label: 'Contact Person',
            icon: Icons.person_outline_rounded,
          ),
          second: _AdminSettingsField(
            controller: _contactNumber,
            label: 'Contact Number',
            icon: Icons.phone_outlined,
            keyboardType: TextInputType.phone,
          ),
        ),
        const SizedBox(height: 14),
        _AdminSettingsField(
          controller: _officialEmail,
          label: 'Official Email',
          icon: Icons.alternate_email_rounded,
          keyboardType: TextInputType.emailAddress,
          helperText:
              'Public office contact; this does not change the sign-in email.',
        ),
      ],
    );
  }

  Widget _brandingSection() {
    return _SettingsCard(
      title: 'Branding',
      subtitle:
          'Province-wide office identity. Images use the existing public-assets storage bucket.',
      children: [
        _AdminSettingsField(
          controller: _displayName,
          label: 'Display Name',
          icon: Icons.badge_outlined,
        ),
        const SizedBox(height: 16),
        _FieldRow(
          first: _BrandingAsset(
            title: 'Office Logo',
            description: 'Square JPG, PNG, or WebP, up to 5 MB.',
            imageUrl: _logoUrl.text.trim(),
            aspectRatio: 1,
            uploading: _uploadingLogo,
            onUpload: () => _pickBrandingImage(logo: true),
            onRemove: _logoUrl.text.trim().isEmpty
                ? null
                : () => _logoUrl.clear(),
          ),
          second: _BrandingAsset(
            title: 'Cover / Banner Image',
            description: 'Wide JPG, PNG, or WebP, up to 5 MB.',
            imageUrl: _coverUrl.text.trim(),
            aspectRatio: 3.2,
            uploading: _uploadingCover,
            onUpload: () => _pickBrandingImage(logo: false),
            onRemove: _coverUrl.text.trim().isEmpty
                ? null
                : () => _coverUrl.clear(),
          ),
        ),
      ],
    );
  }

  Widget _policiesSection() {
    return _SettingsCard(
      title: 'Booking Policies',
      subtitle:
          'Published province-wide booking rules. The cutoff below is the same value used by cancellation eligibility checks.',
      children: [
        ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 430),
          child: _AdminSettingsField(
            controller: _cancellationHours,
            label: 'Cancellation Cutoff',
            icon: Icons.schedule_rounded,
            keyboardType: TextInputType.number,
            suffixText: 'hours before scheduled tour',
          ),
        ),
        const SizedBox(height: 18),
        _PolicyEditor(
          controller: _terms,
          label: 'Terms & Conditions',
          description: 'General terms shown to TourisTrike users.',
        ),
        const SizedBox(height: 16),
        _PolicyEditor(
          controller: _cancellationPolicy,
          label: 'Cancellation Policy',
          description:
              'Explain refunds, late cancellation, and review conditions.',
        ),
        const SizedBox(height: 16),
        _PolicyEditor(
          controller: _privacy,
          label: 'Tourist Data Privacy Notice',
          description:
              'Explain how tourist and trip data is collected and used.',
        ),
      ],
    );
  }

  Widget _notificationsSection() {
    return _SettingsCard(
      title: 'Notifications',
      subtitle:
          'Choose which administrative events may create push and foreground alerts. Notification history remains available.',
      children: [
        _PreferenceTile(
          icon: Icons.location_city_outlined,
          title: 'New City / Municipal account applications',
          subtitle: 'Application submissions awaiting Provincial Admin review.',
          value: _cityApplications,
          onChanged: (value) => setState(() => _cityApplications = value),
        ),
        _PreferenceTile(
          icon: Icons.fact_check_outlined,
          title: 'Driver accreditation and status updates',
          subtitle: 'New applications and status changes from local offices.',
          value: _driverUpdates,
          onChanged: (value) => setState(() => _driverUpdates = value),
        ),
        _PreferenceTile(
          icon: Icons.event_busy_outlined,
          title: 'Booking issues requiring attention',
          subtitle: 'Cancellations and booking exceptions requiring review.',
          value: _bookingIssues,
          onChanged: (value) => setState(() => _bookingIssues = value),
        ),
        _PreferenceTile(
          icon: Icons.gpp_maybe_outlined,
          title: 'Payment disputes',
          subtitle: 'New payment disputes requiring administrative review.',
          value: _paymentDisputes,
          onChanged: (value) => setState(() => _paymentDisputes = value),
        ),
        const _PreferenceTile(
          icon: Icons.emergency_outlined,
          title: 'Emergency alerts',
          subtitle: 'Required for active trip safety incidents.',
          value: true,
          required: true,
        ),
        const _PreferenceTile(
          icon: Icons.security_outlined,
          title: 'System and security notifications',
          subtitle:
              'Required for account integrity and critical service notices.',
          value: true,
          required: true,
        ),
      ],
    );
  }

  Widget _securitySection(ProvincialAdminProfile profile) {
    return Column(
      children: [
        _SettingsCard(
          title: 'Account',
          subtitle: 'Authenticated Provincial Administrator account details.',
          children: [
            _ReadOnlyDetails(
              items: [
                ('Administrator Name', profile.displayName),
                (
                  'Email',
                  profile.email.isEmpty ? 'Not available' : profile.email,
                ),
                ('Role', 'Provincial Administrator'),
                ('Province', profile.province),
              ],
            ),
          ],
        ),
        const SizedBox(height: 14),
        _SettingsCard(
          title: 'Change Password',
          subtitle:
              'Updates this account through Supabase Auth. Passwords are never stored in application tables.',
          children: [
            _FieldRow(
              first: _AdminSettingsField(
                controller: _newPassword,
                label: 'New Password',
                icon: Icons.lock_outline_rounded,
                obscureText: _obscurePassword,
                onChanged: (_) => setState(() {}),
                suffixIcon: IconButton(
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
              second: _AdminSettingsField(
                controller: _confirmPassword,
                label: 'Confirm New Password',
                icon: Icons.lock_reset_rounded,
                obscureText: _obscureConfirmation,
                onChanged: (_) => setState(() {}),
                suffixIcon: IconButton(
                  onPressed: () => setState(
                    () => _obscureConfirmation = !_obscureConfirmation,
                  ),
                  icon: Icon(
                    _obscureConfirmation
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            _PasswordRules(errors: _passwordErrors(_newPassword.text)),
            const SizedBox(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: FilledButton.icon(
                onPressed: _savingPassword ? null : _changePassword,
                icon: _savingPassword
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.password_rounded),
                label: Text(
                  _savingPassword ? 'Updating...' : 'Update Password',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderPreview extends StatelessWidget {
  const _HeaderPreview({
    required this.data,
    required this.officeNameController,
    required this.displayNameController,
    required this.logoController,
    required this.coverController,
  });

  final ProvincialAdminSettingsData data;
  final TextEditingController officeNameController;
  final TextEditingController displayNameController;
  final TextEditingController logoController;
  final TextEditingController coverController;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([
        officeNameController,
        displayNameController,
        logoController,
        coverController,
      ]),
      builder: (context, _) {
        final cover = coverController.text.trim();
        final logo = logoController.text.trim();
        final officeName = officeNameController.text.trim();
        final displayName = displayNameController.text.trim();
        final province = data.profile.province.trim().isEmpty
            ? 'Province'
            : data.profile.province.trim();
        final subtitle = displayName.isNotEmpty
            ? displayName
            : officeName.isNotEmpty
            ? officeName
            : '$province Provincial Tourism Office';

        return Container(
          padding: const EdgeInsets.fromLTRB(18, 16, 18, 16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28),
            gradient: cover.isEmpty ? ProvincialAdminColors.gradient : null,
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
                color: ProvincialAdminColors.blue.withValues(alpha: .16),
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
                          Icons.account_balance_rounded,
                          color: ProvincialAdminColors.blue,
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
                        province,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: Responsive.isDesktop(context) ? 30 : 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      Text(
                        subtitle,
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

class _SettingsSection {
  const _SettingsSection(this.label, this.icon);

  final String label;
  final IconData icon;
}

class _SettingsNavigation extends StatelessWidget {
  const _SettingsNavigation({
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final List<_SettingsSection> sections;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Settings Menu',
            style: TextStyle(
              color: ProvincialAdminColors.text,
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
                  final isSelected = index == selected;
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
                          color: isSelected
                              ? ProvincialAdminColors.blue.withValues(
                                  alpha: .10,
                                )
                              : Colors.transparent,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: isSelected
                                ? ProvincialAdminColors.blue.withValues(
                                    alpha: .22,
                                  )
                                : Colors.transparent,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              section.icon,
                              size: 18,
                              color: isSelected
                                  ? ProvincialAdminColors.blue
                                  : ProvincialAdminColors.muted,
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Text(
                                section.label,
                                style: TextStyle(
                                  color: isSelected
                                      ? ProvincialAdminColors.blue
                                      : ProvincialAdminColors.text,
                                  fontSize: 13,
                                  fontWeight: isSelected
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

class _MobileSectionPicker extends StatelessWidget {
  const _MobileSectionPicker({
    required this.sections,
    required this.selected,
    required this.onSelected,
  });

  final List<_SettingsSection> sections;
  final int selected;
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
          final isSelected = index == selected;
          final section = sections[index];
          return InkWell(
            borderRadius: BorderRadius.circular(999),
            onTap: () => onSelected(index),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? ProvincialAdminColors.blue : Colors.white,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: isSelected
                      ? ProvincialAdminColors.blue
                      : ProvincialAdminColors.line,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    section.icon,
                    size: 16,
                    color: isSelected
                        ? Colors.white
                        : ProvincialAdminColors.muted,
                  ),
                  const SizedBox(width: 7),
                  Text(
                    section.label,
                    style: TextStyle(
                      color: isSelected
                          ? Colors.white
                          : ProvincialAdminColors.muted,
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

class _SettingsCard extends StatelessWidget {
  const _SettingsCard({
    required this.title,
    required this.subtitle,
    required this.children,
  });

  final String title;
  final String subtitle;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AdminSectionHeader(title: title, subtitle: subtitle),
          const SizedBox(height: 20),
          ...children,
        ],
      ),
    );
  }
}

class _FieldRow extends StatelessWidget {
  const _FieldRow({required this.first, required this.second});

  final Widget first;
  final Widget second;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 650) {
          return Column(children: [first, const SizedBox(height: 14), second]);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: first),
            const SizedBox(width: 14),
            Expanded(child: second),
          ],
        );
      },
    );
  }
}

class _AdminSettingsField extends StatelessWidget {
  const _AdminSettingsField({
    required this.controller,
    required this.label,
    required this.icon,
    this.readOnly = false,
    this.maxLines = 1,
    this.keyboardType,
    this.helperText,
    this.suffixText,
    this.suffixIcon,
    this.obscureText = false,
    this.onChanged,
  });

  final TextEditingController controller;
  final String label;
  final IconData icon;
  final bool readOnly;
  final int maxLines;
  final TextInputType? keyboardType;
  final String? helperText;
  final String? suffixText;
  final Widget? suffixIcon;
  final bool obscureText;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: controller,
      readOnly: readOnly,
      maxLines: maxLines,
      keyboardType: keyboardType,
      obscureText: obscureText,
      onChanged: onChanged,
      decoration: InputDecoration(
        labelText: label,
        helperText: helperText,
        suffixText: suffixText,
        suffixIcon: suffixIcon,
        prefixIcon: Icon(icon, size: 20),
        filled: true,
        fillColor: readOnly ? const Color(0xFFF1F5F9) : const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ProvincialAdminColors.line),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(16),
          borderSide: const BorderSide(color: ProvincialAdminColors.line),
        ),
      ),
    );
  }
}

class _PolicyEditor extends StatelessWidget {
  const _PolicyEditor({
    required this.controller,
    required this.label,
    required this.description,
  });

  final TextEditingController controller;
  final String label;
  final String description;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: ProvincialAdminColors.text,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 3),
        Text(
          description,
          style: const TextStyle(
            color: ProvincialAdminColors.muted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: 8),
        TextField(
          controller: controller,
          minLines: 5,
          maxLines: 10,
          decoration: InputDecoration(
            hintText: 'Enter $label',
            filled: true,
            fillColor: const Color(0xFFF8FAFC),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: ProvincialAdminColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(16),
              borderSide: const BorderSide(color: ProvincialAdminColors.line),
            ),
          ),
        ),
      ],
    );
  }
}

class _BrandingAsset extends StatelessWidget {
  const _BrandingAsset({
    required this.title,
    required this.description,
    required this.imageUrl,
    required this.aspectRatio,
    required this.uploading,
    required this.onUpload,
    this.onRemove,
  });

  final String title;
  final String description;
  final String imageUrl;
  final double aspectRatio;
  final bool uploading;
  final VoidCallback onUpload;
  final VoidCallback? onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 620;
          final preview = SizedBox(
            width: compact ? double.infinity : 230,
            child: AspectRatio(
              aspectRatio: compact
                  ? (aspectRatio < 2 ? 2.4 : aspectRatio)
                  : aspectRatio,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(14),
                child: imageUrl.isEmpty
                    ? const ColoredBox(
                        color: Color(0xFFEAF3FF),
                        child: Center(
                          child: Icon(
                            Icons.image_not_supported_outlined,
                            color: ProvincialAdminColors.lightMuted,
                            size: 34,
                          ),
                        ),
                      )
                    : Image.network(
                        imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) => const ColoredBox(
                          color: Color(0xFFFFF1F2),
                          child: Center(
                            child: Icon(
                              Icons.broken_image_outlined,
                              color: ProvincialAdminColors.red,
                            ),
                          ),
                        ),
                      ),
              ),
            ),
          );
          final details = Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: const TextStyle(
                  color: ProvincialAdminColors.text,
                  fontWeight: FontWeight.w900,
                  fontSize: 15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                description,
                style: const TextStyle(
                  color: ProvincialAdminColors.muted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  FilledButton.icon(
                    onPressed: uploading ? null : onUpload,
                    icon: uploading
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.upload_rounded),
                    label: Text(
                      uploading
                          ? 'Uploading...'
                          : imageUrl.isEmpty
                          ? 'Upload'
                          : 'Replace',
                    ),
                  ),
                  if (onRemove != null)
                    OutlinedButton.icon(
                      onPressed: uploading ? null : onRemove,
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: const Text('Remove'),
                    ),
                ],
              ),
            ],
          );
          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [preview, const SizedBox(height: 12), details],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              preview,
              const SizedBox(width: 16),
              Expanded(child: details),
            ],
          );
        },
      ),
    );
  }
}

class _PreferenceTile extends StatelessWidget {
  const _PreferenceTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.value,
    this.onChanged,
    this.required = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final bool value;
  final ValueChanged<bool>? onChanged;
  final bool required;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FAFC),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: ProvincialAdminColors.line),
      ),
      child: Row(
        children: [
          Icon(icon, color: ProvincialAdminColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        title,
                        style: const TextStyle(
                          color: ProvincialAdminColors.text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (required) ...[
                      const SizedBox(width: 8),
                      const _RequiredBadge(),
                    ],
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  subtitle,
                  style: const TextStyle(
                    color: ProvincialAdminColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Switch.adaptive(value: value, onChanged: required ? null : onChanged),
        ],
      ),
    );
  }
}

class _ReadOnlyDetails extends StatelessWidget {
  const _ReadOnlyDetails({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: items
          .map(
            (item) => Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: ProvincialAdminColors.backgroundAlt,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: ProvincialAdminColors.line),
              ),
              child: Row(
                children: [
                  Icon(switch (item.$1) {
                    'Administrator Name' => Icons.person_rounded,
                    'Email' => Icons.alternate_email_rounded,
                    'Role' => Icons.admin_panel_settings_rounded,
                    _ => Icons.map_rounded,
                  }, color: ProvincialAdminColors.blue),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      item.$1,
                      style: const TextStyle(
                        color: ProvincialAdminColors.text,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      item.$2.isEmpty ? 'Not available' : item.$2,
                      textAlign: TextAlign.right,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ProvincialAdminColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          )
          .toList(growable: false),
    );
  }
}

class _PasswordRules extends StatelessWidget {
  const _PasswordRules({required this.errors});

  final List<String> errors;

  @override
  Widget build(BuildContext context) {
    const rules = [
      'At least 8 characters',
      'An uppercase letter',
      'A lowercase letter',
      'A number',
      'A special character',
    ];
    return Wrap(
      spacing: 10,
      runSpacing: 8,
      children: rules
          .map((rule) {
            final met = !errors.contains(rule);
            return Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  met ? Icons.check_circle_rounded : Icons.circle_outlined,
                  size: 15,
                  color: met
                      ? ProvincialAdminColors.green
                      : ProvincialAdminColors.lightMuted,
                ),
                const SizedBox(width: 5),
                Text(
                  rule,
                  style: TextStyle(
                    color: met
                        ? ProvincialAdminColors.green
                        : ProvincialAdminColors.muted,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            );
          })
          .toList(growable: false),
    );
  }
}

class _SaveBar extends StatelessWidget {
  const _SaveBar({
    required this.dirty,
    required this.saving,
    required this.onReset,
    required this.onSave,
  });

  final bool dirty;
  final bool saving;
  final VoidCallback onReset;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    return AdminSectionCard(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: saving || !dirty ? null : onReset,
                style: TextButton.styleFrom(
                  foregroundColor: ProvincialAdminColors.muted,
                  disabledForegroundColor: ProvincialAdminColors.lightMuted,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 18,
                    vertical: 14,
                  ),
                ),
                child: const Text(
                  'Cancel',
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                width: 150,
                height: 44,
                child: FilledButton(
                  onPressed: saving || !dirty ? null : onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: ProvincialAdminColors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: ProvincialAdminColors.blue
                        .withValues(alpha: .42),
                    disabledForegroundColor: Colors.white.withValues(
                      alpha: .85,
                    ),
                    elevation: 0,
                    padding: const EdgeInsets.symmetric(horizontal: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: saving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text(
                          'Save Settings',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                ),
              ),
            ],
          );
          return Align(alignment: Alignment.centerRight, child: actions);
        },
      ),
    );
  }
}

class _UnsavedBadge extends StatelessWidget {
  const _UnsavedBadge();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
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
            fontSize: 11.5,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
    );
  }
}

class _RequiredBadge extends StatelessWidget {
  const _RequiredBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
      decoration: BoxDecoration(
        color: ProvincialAdminColors.blue.withValues(alpha: .10),
        borderRadius: BorderRadius.circular(999),
      ),
      child: const Text(
        'Required',
        style: TextStyle(
          color: ProvincialAdminColors.deepBlue,
          fontSize: 10,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}
