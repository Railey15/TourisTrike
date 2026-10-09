import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:touristrike/core/branding/municipality_cover_service.dart';
import 'package:touristrike/core/responsive/responsive.dart';
import 'package:touristrike/screens/subtenant/layouts/subtenant_admin_shell.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_admin_widgets.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';
import 'package:url_launcher/url_launcher.dart';

class SubTenantCityProfileScreen extends StatefulWidget {
  const SubTenantCityProfileScreen({super.key, this.service});

  final SubTenantService? service;

  @override
  State<SubTenantCityProfileScreen> createState() =>
      _SubTenantCityProfileScreenState();
}

class _SubTenantCityProfileScreenState
    extends State<SubTenantCityProfileScreen> {
  late final SubTenantService _service;
  final MunicipalityCoverService _coverService = MunicipalityCoverService();
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
  final _customWaitingIntervalCtrl = TextEditingController();

  int _waitingIntervalSelection =
      SubTenantFareSettings.defaultAdditionalWaitingIntervalMinutes;

  SubTenantProfile? _profile;

  bool _saving = false;
  bool _uploadingCover = false;
  String _selectingCoverUrl = '';
  bool _dirty = false;
  bool _hydrating = false;
  int _selectedIndex = 0;

  bool _officeNameCustomized = false;
  String _generatedOfficeName = '';
  String _localGovernmentType = 'municipality';
  MunicipalityCoverSelection? _currentCover;
  Future<MunicipalityCoverSuggestionsResult>? _coverSuggestionsFuture;
  bool _coverSuggestionsLoading = false;
  final Set<String> _unavailableCoverUrls = {};

  final List<_SettingsSection> _sections = const [
    _SettingsSection('Office Settings', Icons.business_rounded),
    _SettingsSection('Branding', Icons.palette_rounded),
    _SettingsSection('Fare Matrix', Icons.payments_rounded),
    _SettingsSection('Security', Icons.security_rounded),
  ];

  @override
  void initState() {
    super.initState();
    _service = widget.service ?? SubTenantService();
    _future = _load();

    for (final controller in [
      _descriptionCtrl,
      _officeNameCtrl,
      _contactPersonCtrl,
      _contactCtrl,
      _emailCtrl,
      _addressCtrl,
      _logoCtrl,
      _baseFareCtrl,
      _farePerKmCtrl,
      _minimumFareCtrl,
      _waitingFeeCtrl,
      _customWaitingIntervalCtrl,
    ]) {
      controller.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (_hydrating) return;

    _officeNameCustomized =
        _officeNameCtrl.text.trim().toLowerCase() !=
        _generatedOfficeName.toLowerCase();

    if (!_dirty && mounted) {
      setState(() => _dirty = true);
    }
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
    _currentCover = details.coverImageUrl.isEmpty
        ? null
        : MunicipalityCoverSelection(
            imageUrl: details.coverImageUrl,
            source: details.coverImageSource,
            attribution: details.coverImageAttribution,
            sourceUrl: details.coverImageSourceUrl,
            updatedAt: details.coverImageUpdatedAt,
          );

    // A missing row is not an approved fare matrix. Require entered values
    // before first-time upsert rather than persisting model defaults.
    _baseFareCtrl.text = fare.id == null ? '' : _moneyText(fare.baseFare);
    _farePerKmCtrl.text = fare.id == null ? '' : _moneyText(fare.farePerKm);
    _minimumFareCtrl.text = fare.id == null ? '' : _moneyText(fare.minimumFare);
    _waitingFeeCtrl.text = fare.id == null ? '' : _moneyText(fare.waitingFee);
    final interval = fare.additionalWaitingIntervalMinutes;
    if (const {15, 20, 30}.contains(interval)) {
      _waitingIntervalSelection = interval;
      _customWaitingIntervalCtrl.clear();
    } else {
      _waitingIntervalSelection = -1;
      _customWaitingIntervalCtrl.text = '$interval';
    }
    _hydrating = false;
    _dirty = false;

    return _SettingsLoad(profile: profile, details: details, fare: fare);
  }

  void _reload() {
    final next = _load();
    if (!mounted) return;
    setState(() {
      _dirty = false;
      _coverSuggestionsFuture = null;
      _future = next;
    });
  }

  void _refreshCoverSuggestions() {
    final profile = _profile;
    if (profile == null || _coverSuggestionsLoading) return;
    final request = _coverService.loadSuggestions(
      municipality: profile.assignedCity,
    );
    setState(() {
      _unavailableCoverUrls.clear();
      _coverSuggestionsLoading = true;
      _coverSuggestionsFuture = request;
    });
    _trackCoverSuggestionRequest(request);
  }

  Future<void> _trackCoverSuggestionRequest(
    Future<MunicipalityCoverSuggestionsResult> request,
  ) async {
    try {
      await request;
    } catch (_) {
      // FutureBuilder presents the retry state.
    } finally {
      if (mounted && identical(_coverSuggestionsFuture, request)) {
        setState(() => _coverSuggestionsLoading = false);
      }
    }
  }

  Future<MunicipalityCoverSuggestionsResult> _initialCoverSuggestions(
    String municipality,
  ) {
    final request = _coverService.loadSuggestions(municipality: municipality);
    _coverSuggestionsLoading = true;
    _trackCoverSuggestionRequest(request);
    return request;
  }

  void _markCoverSuggestionUnavailable(String imageUrl) {
    final key = MunicipalityCoverService.normalizedImageUrl(imageUrl);
    if (_unavailableCoverUrls.add(key) && mounted) setState(() {});
  }

  Future<void> _selectCover(MunicipalityCoverSuggestion suggestion) async {
    final key = MunicipalityCoverService.normalizedImageUrl(
      suggestion.imageUrl,
    );
    if (_unavailableCoverUrls.contains(key) ||
        !MunicipalityCoverService.canSelectSuggestion(suggestion)) {
      showSubTenantSnack(
        context,
        'This image is unavailable and cannot be selected.',
      );
      return;
    }
    setState(() => _selectingCoverUrl = suggestion.imageUrl);
    try {
      await _coverService.selectCover(suggestion);
      if (!mounted) return;
      setState(() {
        _coverCtrl.text = suggestion.imageUrl;
        _currentCover = MunicipalityCoverSelection(
          imageUrl: suggestion.imageUrl,
          source: suggestion.source,
          attribution: suggestion.attribution,
          sourceUrl: suggestion.sourceUrl,
          updatedAt: DateTime.now(),
        );
      });
      showSubTenantSnack(context, 'Municipality cover updated.', error: false);
    } catch (error) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Could not update the cover: $error');
    } finally {
      if (mounted) setState(() => _selectingCoverUrl = '');
    }
  }

  Future<void> _removeCover() async {
    setState(() => _selectingCoverUrl = '__remove__');
    try {
      await _coverService.removeCover();
      if (!mounted) return;
      setState(() {
        _coverCtrl.clear();
        _currentCover = null;
      });
      showSubTenantSnack(
        context,
        'Municipality cover removed. TourisTrike will use a safe fallback.',
        error: false,
      );
    } catch (error) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Could not remove the cover: $error');
    } finally {
      if (mounted) setState(() => _selectingCoverUrl = '');
    }
  }

  bool _isSupportedCover(XFile file) {
    final mimeType = file.mimeType?.trim().toLowerCase() ?? '';
    if (mimeType.isNotEmpty &&
        !const {'image/jpeg', 'image/png', 'image/webp'}.contains(mimeType)) {
      return false;
    }
    final name = file.name.toLowerCase();
    return name.endsWith('.jpg') ||
        name.endsWith('.jpeg') ||
        name.endsWith('.png') ||
        name.endsWith('.webp');
  }

  String _coverContentType(XFile file) {
    final name = file.name.toLowerCase();
    if (name.endsWith('.png')) return 'image/png';
    if (name.endsWith('.webp')) return 'image/webp';
    return 'image/jpeg';
  }

  Future<void> _uploadCover(SubTenantProfile profile) async {
    final file = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      maxWidth: 2400,
      imageQuality: 90,
    );
    if (file == null) return;
    if (!_isSupportedCover(file)) {
      if (mounted) {
        showSubTenantSnack(context, 'Use JPG, PNG, or WebP images only.');
      }
      return;
    }

    final bytes = await file.readAsBytes();
    if (bytes.length > 8 * 1024 * 1024) {
      if (mounted) {
        showSubTenantSnack(context, 'Cover image must be 8 MB or smaller.');
      }
      return;
    }
    late final int imageWidth;
    late final int imageHeight;
    ui.Codec? codec;
    try {
      codec = await ui.instantiateImageCodec(bytes);
      final frame = await codec.getNextFrame();
      imageWidth = frame.image.width;
      imageHeight = frame.image.height;
      frame.image.dispose();
    } catch (_) {
      if (mounted) {
        showSubTenantSnack(context, 'The selected file is not a valid image.');
      }
      return;
    } finally {
      codec?.dispose();
    }
    final isLandscape = imageWidth > imageHeight;
    if (!isLandscape) {
      if (mounted) {
        showSubTenantSnack(
          context,
          'Choose a landscape image so the municipality hero crops correctly.',
        );
      }
      return;
    }
    if (imageWidth < 900 || imageHeight < 500) {
      if (mounted) {
        showSubTenantSnack(
          context,
          'Choose a landscape image at least 900 × 500 pixels.',
        );
      }
      return;
    }

    setState(() => _uploadingCover = true);
    try {
      final url = await _service.uploadPublicAsset(
        profile: profile,
        bucket: 'public-assets',
        folder: 'municipality-covers/${profile.id}',
        fileName: file.name,
        bytes: bytes,
        contentType: _coverContentType(file),
      );
      final suggestion = MunicipalityCoverSuggestion(
        imageUrl: url,
        source: MunicipalityCoverSource.uploaded,
        title: '${profile.assignedCity} uploaded cover',
        municipality: profile.assignedCity,
        width: imageWidth,
        height: imageHeight,
      );
      await _coverService.selectCover(suggestion);
      if (!mounted) return;
      setState(() {
        _coverCtrl.text = url;
        _currentCover = MunicipalityCoverSelection(
          imageUrl: url,
          source: MunicipalityCoverSource.uploaded,
          updatedAt: DateTime.now(),
        );
      });
      showSubTenantSnack(
        context,
        'Custom municipality cover uploaded.',
        error: false,
      );
    } catch (error) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Cover upload failed: $error');
    } finally {
      if (mounted) setState(() => _uploadingCover = false);
    }
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
    _customWaitingIntervalCtrl.dispose();
    super.dispose();
  }

  double _moneyValue(TextEditingController controller) {
    return SubTenantFareSettings.parseMoneyAmount(controller.text) ?? 0;
  }

  String _moneyText(double value) {
    if (value == 0) return '0';

    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toStringAsFixed(2);
  }

  String? _nonNegativeMoneyValidator(String? value) {
    final parsed = SubTenantFareSettings.parseMoneyAmount(value ?? '');
    if (parsed == null) {
      return 'Enter a valid non-negative amount (up to 2 decimals)';
    }
    return null;
  }

  int? get _additionalWaitingIntervalMinutes {
    if (_waitingIntervalSelection != -1) return _waitingIntervalSelection;
    final raw = _customWaitingIntervalCtrl.text.trim();
    if (!RegExp(r'^\d+$').hasMatch(raw)) return null;
    final minutes = int.tryParse(raw);
    return minutes != null && minutes >= 1 && minutes <= 60 ? minutes : null;
  }

  String? _waitingIntervalValidator(String? value) {
    if (_waitingIntervalSelection != -1) return null;
    return _additionalWaitingIntervalMinutes == null
        ? 'Enter a whole number from 1 to 60'
        : null;
  }

  SubTenantFareSettings _fareFromState(SubTenantProfile profile) {
    return SubTenantFareSettings(
      subtenantId: profile.id,
      city: profile.assignedCity,
      baseFare: _moneyValue(_baseFareCtrl),
      farePerKm: _moneyValue(_farePerKmCtrl),
      minimumFare: _moneyValue(_minimumFareCtrl),
      waitingFee: _moneyValue(_waitingFeeCtrl),
      additionalWaitingIntervalMinutes:
          _additionalWaitingIntervalMinutes ??
          SubTenantFareSettings.defaultAdditionalWaitingIntervalMinutes,
    );
  }

  Future<void> _save() async {
    FocusScope.of(context).unfocus();

    if (!_formKey.currentState!.validate()) {
      return;
    }

    final profile = _profile;

    if (profile == null) {
      return;
    }

    setState(() => _saving = true);

    try {
      if (_selectedIndex != 2) {
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
      }
      if (_selectedIndex == 2) {
        await _service.saveFareSettings(profile, _fareFromState(profile));
      }

      if (!mounted) return;

      setState(() => _dirty = false);

      showSubTenantSnack(context, 'Settings saved.', error: false);
    } catch (e) {
      if (!mounted) return;

      showSubTenantSnack(context, 'Failed to save settings: $e');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SubTenantAdminShell(
      currentIndex: 6,
      title: 'Settings',
      subtitle: 'Manage your tourism office profile and active fare settings.',
      actions: [
        if (_dirty && !Responsive.isMobile(context))
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
                              final navWidth = (constraints.maxWidth * .26)
                                  .clamp(220.0, 270.0)
                                  .toDouble();

                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: navWidth,
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
        return _brandingSettings(data);
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

  Widget _brandingSettings(_SettingsLoad data) {
    _coverSuggestionsFuture ??= _initialCoverSuggestions(
      data.profile.assignedCity,
    );
    return _SettingsContent(
      title: 'Branding',
      subtitle: 'Customize how this municipality appears to tourists.',
      children: [
        _ReadOnlyMunicipality(
          city: data.profile.assignedCity,
          province: data.profile.province.isEmpty
              ? 'Bulacan'
              : data.profile.province,
        ),
        const SizedBox(height: 16),
        SubTenantTextField(
          controller: _logoCtrl,
          label: 'Municipality Logo / Image URL',
          keyboardType: TextInputType.url,
        ),
        const SizedBox(height: 10),
        ListenableBuilder(
          listenable: _logoCtrl,
          builder: (context, _) => SizedBox(
            width: 220,
            child: _ImageBox(label: 'Logo Preview', url: _logoCtrl.text.trim()),
          ),
        ),
        const SizedBox(height: 22),
        _CurrentCoverCard(
          cover: _currentCover,
          removing: _selectingCoverUrl == '__remove__',
          uploading: _uploadingCover,
          onRemove: _currentCover == null ? null : _removeCover,
          onUpload: () => _uploadCover(data.profile),
        ),
        const SizedBox(height: 22),
        Row(
          children: [
            Expanded(
              child: SubTenantSectionHeader(
                title: 'Smart Cover Suggestions',
                subtitle:
                    'Suggested for ${data.profile.assignedCity}, '
                    '${data.profile.province.isEmpty ? 'Bulacan' : data.profile.province}. '
                    'Verified local destinations are ranked before Pexels photos.',
              ),
            ),
            OutlinedButton.icon(
              onPressed: _coverSuggestionsLoading
                  ? null
                  : _refreshCoverSuggestions,
              icon: _coverSuggestionsLoading
                  ? const SizedBox.square(
                      dimension: 15,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.refresh_rounded, size: 18),
              label: const Text('Refresh Suggestions'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        FutureBuilder<MunicipalityCoverSuggestionsResult>(
          future: _coverSuggestionsFuture,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const _CoverSuggestionsLoading();
            }
            if (snapshot.hasError) {
              return _CoverSuggestionsMessage(
                icon: Icons.cloud_off_outlined,
                message:
                    'Suggestions could not be loaded. You can still upload a cover.',
                actionLabel: 'Retry',
                onAction: _refreshCoverSuggestions,
              );
            }
            final result = snapshot.data!;
            final suggestions = result.suggestions
                .where(
                  (suggestion) => !_unavailableCoverUrls.contains(
                    MunicipalityCoverService.normalizedImageUrl(
                      suggestion.imageUrl,
                    ),
                  ),
                )
                .toList(growable: false);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (result.warning.isNotEmpty) ...[
                  _CoverWarning(message: result.warning),
                  const SizedBox(height: 12),
                ],
                if (suggestions.isEmpty)
                  _CoverSuggestionsMessage(
                    icon: Icons.photo_library_outlined,
                    message:
                        'No verified cover suggestions are available for '
                        '${data.profile.assignedCity} yet. You can upload an '
                        'official municipality cover photo.',
                    actionLabel: 'Upload Cover',
                    onAction: () => _uploadCover(data.profile),
                  )
                else
                  LayoutBuilder(
                    builder: (context, constraints) => Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (final suggestion in suggestions)
                          _CoverSuggestionCard(
                            width: constraints.maxWidth >= 900
                                ? (constraints.maxWidth - 24) / 3
                                : constraints.maxWidth >= 600
                                ? (constraints.maxWidth - 12) / 2
                                : constraints.maxWidth,
                            suggestion: suggestion,
                            currentUrl: _currentCover?.imageUrl ?? '',
                            selecting:
                                _selectingCoverUrl == suggestion.imageUrl,
                            onUse: () => _selectCover(suggestion),
                            onImageFailed: () =>
                                _markCoverSuggestionUnavailable(
                                  suggestion.imageUrl,
                                ),
                          ),
                      ],
                    ),
                  ),
              ],
            );
          },
        ),
        const SizedBox(height: 22),
        const _OrDivider(),
        const SizedBox(height: 18),
        Align(
          alignment: Alignment.centerLeft,
          child: FilledButton.icon(
            onPressed: _uploadingCover
                ? null
                : () => _uploadCover(data.profile),
            icon: _uploadingCover
                ? const SizedBox.square(
                    dimension: 17,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Icon(Icons.upload_rounded),
            label: Text(
              _uploadingCover ? 'Uploading cover...' : 'Upload Your Own Cover',
            ),
          ),
        ),
      ],
    );
  }

  Widget _fareMatrixSettings(SubTenantProfile profile) {
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
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: SubTenantColors.backgroundAlt,
            border: Border.all(color: SubTenantColors.line),
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ListenableBuilder(
                listenable: Listenable.merge([
                  _waitingFeeCtrl,
                  _customWaitingIntervalCtrl,
                ]),
                builder: (context, child) {
                  final interval = _additionalWaitingIntervalMinutes;
                  final hourly = SubTenantFareSettings.parseMoneyAmount(
                    _waitingFeeCtrl.text,
                  );
                  final calculated = interval == null || hourly == null
                      ? null
                      : SubTenantFareSettings(
                          subtenantId: profile.id,
                          city: profile.assignedCity,
                          waitingFee: hourly,
                          additionalWaitingIntervalMinutes: interval,
                        ).calculatedAdditionalWaitingFee;
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _TwoColumn(
                        left: _WaitingIntervalField(
                          selection: _waitingIntervalSelection,
                          customController: _customWaitingIntervalCtrl,
                          customValidator: _waitingIntervalValidator,
                          onChanged: (value) {
                            if (value == null) return;
                            setState(() => _waitingIntervalSelection = value);
                            _markDirty();
                          },
                        ),
                        right: _CalculatedWaitingFeeField(amount: calculated),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        interval == null
                            ? 'Choose a valid interval to calculate the waiting fee.'
                            : 'Charged per started $interval minutes after the tourist exceeds the included Time of Stay.',
                      ),
                      if (interval != null) ...[
                        const SizedBox(height: 4),
                        const Text(
                          'One configured interval is free; the first charge applies when that grace interval ends.',
                        ),
                      ],
                    ],
                  );
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        ListenableBuilder(
          listenable: Listenable.merge([
            _baseFareCtrl,
            _farePerKmCtrl,
            _minimumFareCtrl,
            _waitingFeeCtrl,
          ]),
          builder: (context, child) {
            final entered =
                [
                  _baseFareCtrl,
                  _farePerKmCtrl,
                  _minimumFareCtrl,
                  _waitingFeeCtrl,
                ].every(
                  (controller) =>
                      SubTenantFareSettings.parseMoneyAmount(controller.text) !=
                      null,
                );
            if (!entered) {
              return const Text(
                'Enter fare amounts to view the sample calculation.',
              );
            }
            return _FarePreview(
              calculation: _fareFromState(
                profile,
              ).calculate(routeDistanceKm: 8),
            );
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

class _WaitingIntervalField extends StatelessWidget {
  const _WaitingIntervalField({
    required this.selection,
    required this.customController,
    required this.customValidator,
    required this.onChanged,
  });

  final int selection;
  final TextEditingController customController;
  final FormFieldValidator<String> customValidator;
  final ValueChanged<int?> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Additional Waiting Interval',
          style: TextStyle(
            color: SubTenantColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        DropdownButtonFormField<int>(
          key: const ValueKey('additional-waiting-interval-dropdown'),
          initialValue: selection,
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
          items: const [
            DropdownMenuItem(value: 15, child: Text('15 minutes')),
            DropdownMenuItem(value: 20, child: Text('20 minutes')),
            DropdownMenuItem(value: 30, child: Text('30 minutes')),
            DropdownMenuItem(value: -1, child: Text('Custom')),
          ],
          onChanged: onChanged,
        ),
        if (selection == -1) ...[
          const SizedBox(height: 10),
          SubTenantTextField(
            controller: customController,
            label: 'Custom interval (minutes)',
            keyboardType: TextInputType.number,
            validator: customValidator,
          ),
        ],
      ],
    );
  }
}

class _CalculatedWaitingFeeField extends StatelessWidget {
  const _CalculatedWaitingFeeField({required this.amount});

  final double? amount;

  @override
  Widget build(BuildContext context) {
    final display = amount == null
        ? 'PHP —'
        : 'PHP ${amount!.toStringAsFixed(2)}';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Calculated Waiting Fee',
          style: TextStyle(
            color: SubTenantColors.text,
            fontSize: 13,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        TextFormField(
          key: ValueKey('calculated-waiting-fee-$display'),
          initialValue: display,
          readOnly: true,
          enableInteractiveSelection: false,
          decoration: InputDecoration(
            filled: true,
            fillColor: const Color(0xFFEFF5FC),
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
        ),
        const SizedBox(height: 6),
        const Text(
          'Automatically calculated from the hourly waiting fee.',
          style: TextStyle(color: SubTenantColors.muted, fontSize: 12),
        ),
      ],
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
          final actions = Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton(
                onPressed: saving || !dirty ? null : onCancel,
                style: TextButton.styleFrom(
                  foregroundColor: SubTenantColors.muted,
                  disabledForegroundColor: SubTenantColors.lightMuted,
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

              // Plain Save Settings button.
              // No check icon and no save icon.
              SizedBox(
                width: 150,
                height: 44,
                child: FilledButton(
                  onPressed: saving || !dirty ? null : onSave,
                  style: FilledButton.styleFrom(
                    backgroundColor: SubTenantColors.blue,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: SubTenantColors.blue.withValues(
                      alpha: .42,
                    ),
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

          if (constraints.maxWidth < 560) {
            return Align(alignment: Alignment.centerRight, child: actions);
          }

          return Row(
            mainAxisAlignment: MainAxisAlignment.end,
            children: [actions],
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

class _ReadOnlyMunicipality extends StatelessWidget {
  const _ReadOnlyMunicipality({required this.city, required this.province});

  final String city;
  final String province;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: SubTenantColors.backgroundAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_city_rounded, color: SubTenantColors.blue),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Municipality',
                  style: TextStyle(
                    color: SubTenantColors.muted,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '$city, $province',
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ),
          const Icon(
            Icons.lock_outline_rounded,
            color: SubTenantColors.lightMuted,
          ),
        ],
      ),
    );
  }
}

class _CurrentCoverCard extends StatelessWidget {
  const _CurrentCoverCard({
    required this.cover,
    required this.removing,
    required this.uploading,
    required this.onRemove,
    required this.onUpload,
  });

  final MunicipalityCoverSelection? cover;
  final bool removing;
  final bool uploading;
  final VoidCallback? onRemove;
  final VoidCallback onUpload;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Municipality Cover',
          style: TextStyle(
            color: SubTenantColors.text,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'CURRENT COVER',
          style: TextStyle(
            color: SubTenantColors.lightMuted,
            fontSize: 11,
            fontWeight: FontWeight.w900,
            letterSpacing: .8,
          ),
        ),
        const SizedBox(height: 9),
        if (cover == null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 34, horizontal: 18),
            decoration: BoxDecoration(
              color: SubTenantColors.backgroundAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SubTenantColors.line),
            ),
            child: const Column(
              children: [
                Icon(
                  Icons.photo_size_select_actual_outlined,
                  color: SubTenantColors.lightMuted,
                  size: 34,
                ),
                SizedBox(height: 9),
                Text(
                  'No municipality cover selected yet.',
                  style: TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                SizedBox(height: 3),
                Text(
                  'Tourist Home will use its verified fallback chain.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: SubTenantColors.muted, fontSize: 12),
                ),
              ],
            ),
          )
        else ...[
          Container(
            width: double.infinity,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: SubTenantColors.backgroundAlt,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: SubTenantColors.line),
            ),
            child: AspectRatio(
              aspectRatio: 16 / 6,
              child: Image.network(
                cover!.imageUrl,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const _CurrentCoverUnavailable(),
              ),
            ),
          ),
          const SizedBox(height: 9),
          Row(
            children: [
              _SourceBadge(source: cover!.source),
              if (cover!.attribution.isNotEmpty) ...[
                const SizedBox(width: 9),
                Expanded(
                  child: _AttributionLink(
                    label: cover!.attribution,
                    url: cover!.sourceUrl,
                  ),
                ),
              ],
            ],
          ),
        ],
        const SizedBox(height: 12),
        Wrap(
          spacing: 10,
          runSpacing: 8,
          children: [
            FilledButton.icon(
              onPressed: uploading ? null : onUpload,
              icon: uploading
                  ? const SizedBox.square(
                      dimension: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.upload_rounded, size: 18),
              label: Text(
                cover == null ? 'Upload Cover' : 'Change / Upload Cover',
              ),
            ),
            if (onRemove != null)
              OutlinedButton.icon(
                onPressed: removing ? null : onRemove,
                icon: removing
                    ? const SizedBox.square(
                        dimension: 15,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.delete_outline_rounded, size: 18),
                label: const Text('Remove Cover'),
              ),
          ],
        ),
      ],
    );
  }
}

class _CurrentCoverUnavailable extends StatelessWidget {
  const _CurrentCoverUnavailable();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: SubTenantColors.backgroundAlt,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              color: SubTenantColors.lightMuted,
            ),
            SizedBox(height: 6),
            Text(
              'Current cover is unavailable',
              style: TextStyle(
                color: SubTenantColors.muted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SourceBadge extends StatelessWidget {
  const _SourceBadge({required this.source});

  final MunicipalityCoverSource source;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: SubTenantColors.blue.withValues(alpha: .08),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        source.label,
        style: const TextStyle(
          color: SubTenantColors.blue,
          fontSize: 10,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _CoverSuggestionCard extends StatefulWidget {
  const _CoverSuggestionCard({
    required this.width,
    required this.suggestion,
    required this.currentUrl,
    required this.selecting,
    required this.onUse,
    required this.onImageFailed,
  });

  final double width;
  final MunicipalityCoverSuggestion suggestion;
  final String currentUrl;
  final bool selecting;
  final VoidCallback onUse;
  final VoidCallback onImageFailed;

  @override
  State<_CoverSuggestionCard> createState() => _CoverSuggestionCardState();
}

class _CoverSuggestionCardState extends State<_CoverSuggestionCard> {
  bool _imageAvailable = true;
  bool _failureReported = false;

  void _handleImageFailure() {
    if (_failureReported) return;
    _failureReported = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _imageAvailable = false);
      widget.onImageFailed();
    });
  }

  @override
  Widget build(BuildContext context) {
    final current =
        MunicipalityCoverService.normalizedImageUrl(widget.currentUrl) ==
        MunicipalityCoverService.normalizedImageUrl(widget.suggestion.imageUrl);
    return SizedBox(
      width: widget.width,
      height: 350,
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(17),
          border: Border.all(
            color: current ? SubTenantColors.blue : SubTenantColors.line,
            width: current ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: AspectRatio(
                aspectRatio: 16 / 9,
                child: _imageAvailable
                    ? Image.network(
                        widget.suggestion.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, _, _) {
                          _handleImageFailure();
                          return const _SuggestionImageUnavailable();
                        },
                      )
                    : const _SuggestionImageUnavailable(),
              ),
            ),
            const SizedBox(height: 9),
            Row(
              children: [
                Expanded(
                  child: Text(
                    widget.suggestion.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: SubTenantColors.text,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                _SourceBadge(source: widget.suggestion.source),
              ],
            ),
            if (widget.suggestion.isGenericFallback) ...[
              const SizedBox(height: 5),
              const Text(
                'General Bulacan image — confirm it fits your municipality.',
                style: TextStyle(color: SubTenantColors.muted, fontSize: 11),
              ),
            ],
            if (widget.suggestion.attribution.isNotEmpty) ...[
              const SizedBox(height: 5),
              _AttributionLink(
                label: widget.suggestion.attribution,
                url: widget.suggestion.sourceUrl,
              ),
            ],
            const Spacer(),
            FilledButton(
              onPressed: current || widget.selecting || !_imageAvailable
                  ? null
                  : widget.onUse,
              child: widget.selecting
                  ? const SizedBox.square(
                      dimension: 17,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(
                      !_imageAvailable
                          ? 'Image unavailable'
                          : current
                          ? 'Current cover'
                          : 'Use this cover',
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SuggestionImageUnavailable extends StatelessWidget {
  const _SuggestionImageUnavailable();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: SubTenantColors.backgroundAlt,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.broken_image_outlined,
              color: SubTenantColors.lightMuted,
            ),
            SizedBox(height: 5),
            Text(
              'Image unavailable',
              style: TextStyle(color: SubTenantColors.muted, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}

class _AttributionLink extends StatelessWidget {
  const _AttributionLink({required this.label, required this.url});

  final String label;
  final String url;

  Future<void> _open() async {
    final uri = Uri.tryParse(url);
    if (uri != null) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: url.isEmpty ? null : _open,
      child: Text(
        label,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: SubTenantColors.muted,
          fontSize: 11,
          decoration: url.isEmpty ? null : TextDecoration.underline,
          decorationColor: SubTenantColors.muted,
        ),
      ),
    );
  }
}

class _CoverWarning extends StatelessWidget {
  const _CoverWarning({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: const Color(0xFFFFFBEB),
        border: Border.all(color: const Color(0xFFFDE68A)),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.info_outline_rounded,
            color: Color(0xFFB45309),
            size: 19,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: const TextStyle(color: Color(0xFF92400E), fontSize: 12),
            ),
          ),
        ],
      ),
    );
  }
}

class _CoverSuggestionsLoading extends StatelessWidget {
  const _CoverSuggestionsLoading();

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 900
            ? 3
            : constraints.maxWidth >= 600
            ? 2
            : 1;
        final width = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
        return Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            for (var index = 0; index < columns; index++)
              Container(
                width: width,
                height: 235,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(17),
                  border: Border.all(color: SubTenantColors.line),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(
                      child: Container(
                        decoration: BoxDecoration(
                          color: SubTenantColors.backgroundAlt,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),
                    Container(height: 13, color: SubTenantColors.backgroundAlt),
                    const SizedBox(height: 7),
                    Container(
                      height: 36,
                      decoration: BoxDecoration(
                        color: SubTenantColors.backgroundAlt,
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ],
                ),
              ),
          ],
        );
      },
    );
  }
}

class _CoverSuggestionsMessage extends StatelessWidget {
  const _CoverSuggestionsMessage({
    required this.icon,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: SubTenantColors.backgroundAlt,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        children: [
          Icon(icon, color: SubTenantColors.lightMuted, size: 34),
          const SizedBox(height: 8),
          Text(message, textAlign: TextAlign.center),
          const SizedBox(height: 9),
          TextButton(onPressed: onAction, child: Text(actionLabel)),
        ],
      ),
    );
  }
}

class _OrDivider extends StatelessWidget {
  const _OrDivider();

  @override
  Widget build(BuildContext context) {
    return const Row(
      children: [
        Expanded(child: Divider(color: SubTenantColors.line)),
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            'OR',
            style: TextStyle(
              color: SubTenantColors.lightMuted,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        Expanded(child: Divider(color: SubTenantColors.line)),
      ],
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
