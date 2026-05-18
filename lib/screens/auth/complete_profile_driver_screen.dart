import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:touristrike/screens/driver/driver_home_screen.dart';

class CompleteProfileDriverScreen extends StatefulWidget {
  const CompleteProfileDriverScreen({super.key});

  @override
  State<CompleteProfileDriverScreen> createState() => _CompleteProfileDriverScreenState();
}

class _CompleteProfileDriverScreenState extends State<CompleteProfileDriverScreen> {
  final supabase = Supabase.instance.client;

  // Stepper
  int _step = 0;

  // Personal
  final _firstNameCtrl = TextEditingController();
  final _middleNameCtrl = TextEditingController();
  final _lastNameCtrl = TextEditingController();
  DateTime? _birthdate;

  final _addressCtrl = TextEditingController();
  final _barangayCtrl = TextEditingController();
  final _cityCtrl = TextEditingController();
  final _provinceCtrl = TextEditingController();
  final _postalCtrl = TextEditingController();

  // Driver details
  final _mobileCtrl = TextEditingController();
  final _licenseNoCtrl = TextEditingController();
  final _plateNoCtrl = TextEditingController();
  DateTime? _licenseExpiry;

  final _todaNameCtrl = TextEditingController();
  final _operatorCodeCtrl = TextEditingController();

  // Upload placeholders (UI-only)
  ImageProvider? selfie;
  ImageProvider? licenseFront;
  ImageProvider? licenseBack;
  ImageProvider? policeClearance;
  ImageProvider? mtop;

  ImageProvider? vehicleFront;
  ImageProvider? vehicleBack;
  ImageProvider? vehicleLeft;
  ImageProvider? vehicleRight;
  ImageProvider? orDoc;
  ImageProvider? crDoc;

  bool _agreed = false;
  bool _saving = false;

  @override
  void dispose() {
    _firstNameCtrl.dispose();
    _middleNameCtrl.dispose();
    _lastNameCtrl.dispose();

    _addressCtrl.dispose();
    _barangayCtrl.dispose();
    _cityCtrl.dispose();
    _provinceCtrl.dispose();
    _postalCtrl.dispose();

    _mobileCtrl.dispose();
    _licenseNoCtrl.dispose();
    _plateNoCtrl.dispose();
    _todaNameCtrl.dispose();
    _operatorCodeCtrl.dispose();
    super.dispose();
  }

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  bool _isValidMobile(String s) => s.trim().length >= 10;

  Future<void> _pickDate({
    required DateTime? initial,
    required ValueChanged<DateTime> onPicked,
  }) async {
    final now = DateTime.now();
    final first = DateTime(1900, 1, 1);
    final last = DateTime(now.year + 20, 12, 31);

    final picked = await showDatePicker(
      context: context,
      initialDate: initial ?? DateTime(now.year - 18, now.month, now.day),
      firstDate: first,
      lastDate: last,
    );
    if (picked != null) onPicked(picked);
  }

  bool _validateStep(int step) {
    if (step == 0) {
      if (_firstNameCtrl.text.trim().isEmpty ||
          _lastNameCtrl.text.trim().isEmpty ||
          _birthdate == null) {
        _showSnack('Please fill first name, last name, and birthdate.');
        return false;
      }
      if (_addressCtrl.text.trim().isEmpty ||
          _barangayCtrl.text.trim().isEmpty ||
          _cityCtrl.text.trim().isEmpty ||
          _provinceCtrl.text.trim().isEmpty ||
          _postalCtrl.text.trim().isEmpty) {
        _showSnack('Please complete your address fields.');
        return false;
      }
    }

    if (step == 1) {
      if (_mobileCtrl.text.trim().isEmpty || !_isValidMobile(_mobileCtrl.text)) {
        _showSnack('Please enter a valid mobile number.');
        return false;
      }
      if (_licenseNoCtrl.text.trim().isEmpty ||
          _plateNoCtrl.text.trim().isEmpty ||
          _licenseExpiry == null ||
          _todaNameCtrl.text.trim().isEmpty ||
          _operatorCodeCtrl.text.trim().isEmpty) {
        _showSnack('Please complete all driver details.');
        return false;
      }
    }

    if (step == 2) {
      // Uploads are UI-only; we just require agreement
      if (!_agreed) {
        _showSnack('Please agree to Terms and Conditions / Privacy Policy.');
        return false;
      }
    }

    return true;
  }

  Future<void> _saveProfile() async {
    final user = supabase.auth.currentUser;
    if (user == null) {
      _showSnack('No active session. Please log in again.');
      return;
    }

    // Validate all steps
    for (int s = 0; s <= 2; s++) {
      if (!_validateStep(s)) {
        setState(() => _step = s);
        return;
      }
    }

    setState(() => _saving = true);

    try {
      // 1) Update base profile + role driver
      await supabase.from('profiles').update({
        'role': 'driver',
        'first_name': _firstNameCtrl.text.trim(),
        'middle_name': _middleNameCtrl.text.trim(),
        'last_name': _lastNameCtrl.text.trim(),
        'full_name':
            '${_firstNameCtrl.text.trim()} ${_middleNameCtrl.text.trim()} ${_lastNameCtrl.text.trim()}'
                .replaceAll(RegExp(r'\s+'), ' ')
                .trim(),
        'birthdate': _birthdate!.toIso8601String().substring(0, 10),
        'address': _addressCtrl.text.trim(),
        'barangay': _barangayCtrl.text.trim(),
        'city': _cityCtrl.text.trim(),
        'province': _provinceCtrl.text.trim(),
        'postal_code': _postalCtrl.text.trim(),
      }).eq('id', user.id);

      // 2) Upsert driver_details
      await supabase.from('driver_details').upsert({
        'driver_id': user.id,
        'mobile': _mobileCtrl.text.trim(),
        'license_number': _licenseNoCtrl.text.trim(),
        'plate_number': _plateNoCtrl.text.trim(),
        'license_expiry': _licenseExpiry!.toIso8601String().substring(0, 10),
        'toda_name': _todaNameCtrl.text.trim(),
        'operator_code': _operatorCodeCtrl.text.trim(),
      });

      // 3) Upsert driver_documents (store URLs later, now empty)
      await supabase.from('driver_documents').upsert({
        'driver_id': user.id,
        'selfie_url': null,
        'license_front_url': null,
        'license_back_url': null,
        'police_clearance_url': null,
        'mtop_url': null,
        'vehicle_front_url': null,
        'vehicle_back_url': null,
        'vehicle_left_url': null,
        'vehicle_right_url': null,
        'or_url': null,
        'cr_url': null,
      });

      if (!mounted) return;

      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const DriverHomeScreen()),
      );
    } on PostgrestException catch (e) {
      _showSnack('Save failed: ${e.message}');
    } catch (e) {
      _showSnack('Save failed: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final headerH = (size.height * 0.12).clamp(92.0, 112.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      resizeToAvoidBottomInset: true,
      body: SafeArea(
        child: Column(
          children: [
            SizedBox(
              height: headerH,
              width: double.infinity,
              child: Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.all(10),
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: const Color(0xFF0F172A),
                  ),
                ),
              ),
            ),

            // Header / title changes per step
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                children: [
                  const Text(
                    'Complete your Driver Profile',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      height: 1.05,
                      letterSpacing: -0.4,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _step == 0
                        ? 'Fill up your Personal Details'
                        : _step == 1
                            ? 'Fill up your Driver Details'
                            : 'Upload requirements & agree to policies',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 14.5,
                      fontWeight: FontWeight.w700,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  const SizedBox(height: 12),
                  _StepDots(current: _step, total: 3),
                ],
              ),
            ),

            const SizedBox(height: 10),

            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: _GlassCard(
                  child: Column(
                    children: [
                      Expanded(
                        child: SingleChildScrollView(
                          physics: const BouncingScrollPhysics(),
                          child: AnimatedSwitcher(
                            duration: const Duration(milliseconds: 180),
                            child: _step == 0
                                ? _personalStep()
                                : _step == 1
                                    ? _driverStep()
                                    : _uploadStep(),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          if (_step > 0)
                            Expanded(
                              child: _OutlinedButton(
                                text: 'Back',
                                onPressed: _saving
                                    ? null
                                    : () => setState(() => _step = (_step - 1).clamp(0, 2)),
                              ),
                            ),
                          if (_step > 0) const SizedBox(width: 12),
                          Expanded(
                            child: _GradientButton(
                              text: _saving
                                  ? 'Saving...'
                                  : _step < 2
                                      ? 'Next'
                                      : 'Submit & Continue',
                              onPressed: _saving
                                  ? null
                                  : () async {
                                      if (_step < 2) {
                                        if (_validateStep(_step)) {
                                          setState(() => _step += 1);
                                        }
                                      } else {
                                        await _saveProfile();
                                      }
                                    },
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),

            const SizedBox(height: 12),

            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Text(
                'You can edit these details later in Settings after approval.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  height: 1.3,
                  color: const Color(0xFF64748B).withOpacity(0.95),
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }

  // ---------------- STEP UI ----------------

  Widget _personalStep() {
    return Column(
      key: const ValueKey('personal'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Personal Details'),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  const _Label(text: 'First Name'),
                  const SizedBox(height: 8),
                  _FancyInputField(
                    controller: _firstNameCtrl,
                    hintText: 'Juan',
                    prefixIcon: Icons.badge_outlined,
                    keyboardType: TextInputType.name,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  const _Label(text: 'Middle Name'),
                  const SizedBox(height: 8),
                  _FancyInputField(
                    controller: _middleNameCtrl,
                    hintText: 'Santos',
                    prefixIcon: Icons.badge_outlined,
                    keyboardType: TextInputType.name,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        const _Label(text: 'Last Name'),
        const SizedBox(height: 8),
        _FancyInputField(
          controller: _lastNameCtrl,
          hintText: 'Dela Cruz',
          prefixIcon: Icons.badge_outlined,
          keyboardType: TextInputType.name,
        ),
        const SizedBox(height: 12),

        const _Label(text: 'Birthdate'),
        const SizedBox(height: 8),
        _DateField(
          valueText: _birthdate == null ? 'Select birthdate' : _fmtDate(_birthdate!),
          icon: Icons.cake_outlined,
          onTap: () => _pickDate(
            initial: _birthdate,
            onPicked: (d) => setState(() => _birthdate = d),
          ),
        ),

        const SizedBox(height: 16),
        const _SectionTitle('Address Information'),
        const SizedBox(height: 12),

        const _Label(text: 'Address'),
        const SizedBox(height: 8),
        _FancyInputField(
          controller: _addressCtrl,
          hintText: 'Street / House No.',
          prefixIcon: Icons.location_on_outlined,
          keyboardType: TextInputType.streetAddress,
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  const _Label(text: 'Barangay'),
                  const SizedBox(height: 8),
                  _FancyInputField(
                    controller: _barangayCtrl,
                    hintText: 'Barangay',
                    prefixIcon: Icons.map_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  const _Label(text: 'City/Municipality'),
                  const SizedBox(height: 8),
                  _FancyInputField(
                    controller: _cityCtrl,
                    hintText: 'Bustos',
                    prefixIcon: Icons.location_city_outlined,
                  ),
                ],
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: Column(
                children: [
                  const _Label(text: 'Province/Region'),
                  const SizedBox(height: 8),
                  _FancyInputField(
                    controller: _provinceCtrl,
                    hintText: 'Bulacan',
                    prefixIcon: Icons.public_outlined,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                children: [
                  const _Label(text: 'Postal Code'),
                  const SizedBox(height: 8),
                  _FancyInputField(
                    controller: _postalCtrl,
                    hintText: '3004',
                    prefixIcon: Icons.markunread_mailbox_outlined,
                    keyboardType: TextInputType.number,
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _driverStep() {
    return Column(
      key: const ValueKey('driver'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle('Driver Details'),
        const SizedBox(height: 12),

        const _Label(text: 'Mobile Number'),
        const SizedBox(height: 8),
        _FancyInputField(
          controller: _mobileCtrl,
          hintText: '09XXXXXXXXX',
          prefixIcon: Icons.phone_outlined,
          keyboardType: TextInputType.phone,
        ),
        const SizedBox(height: 12),

        const _Label(text: "Driver's License Number"),
        const SizedBox(height: 8),
        _FancyInputField(
          controller: _licenseNoCtrl,
          hintText: 'License No.',
          prefixIcon: Icons.credit_card_outlined,
        ),
        const SizedBox(height: 12),

        const _Label(text: "Plate Number"),
        const SizedBox(height: 8),
        _FancyInputField(
          controller: _plateNoCtrl,
          hintText: 'ABC-1234',
          prefixIcon: Icons.confirmation_number_outlined,
        ),
        const SizedBox(height: 12),

        const _Label(text: "Driver's License Expiry Date"),
        const SizedBox(height: 8),
        _DateField(
          valueText: _licenseExpiry == null ? 'Select expiry date' : _fmtDate(_licenseExpiry!),
          icon: Icons.event_available_outlined,
          onTap: () => _pickDate(
            initial: _licenseExpiry,
            onPicked: (d) => setState(() => _licenseExpiry = d),
          ),
        ),
        const SizedBox(height: 12),

        const _Label(text: "TODA Name"),
        const SizedBox(height: 8),
        _FancyInputField(
          controller: _todaNameCtrl,
          hintText: 'TODA Name',
          prefixIcon: Icons.groups_2_outlined,
        ),
        const SizedBox(height: 12),

        const _Label(text: "Operator Code"),
        const SizedBox(height: 8),
        _FancyInputField(
          controller: _operatorCodeCtrl,
          hintText: 'Operator Code',
          prefixIcon: Icons.lock_outline,
        ),
      ],
    );
  }

  Widget _uploadStep() {
    return Column(
      key: const ValueKey('upload'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _SectionTitle("Upload Driver's Requirements"),
        const SizedBox(height: 12),

        _UploadTile(
          title: 'Selfie',
          subtitle: 'Clear selfie photo',
          icon: Icons.camera_alt_rounded,
          image: selfie,
          onTap: () {}, // UI only (add picker later)
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _UploadTile(
                title: "Driver's License (Front)",
                subtitle: 'Front photo',
                icon: Icons.credit_card_rounded,
                image: licenseFront,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _UploadTile(
                title: "Driver's License (Back)",
                subtitle: 'Back photo',
                icon: Icons.credit_card_rounded,
                image: licenseBack,
                onTap: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        _UploadTile(
          title: 'National Police Clearance',
          subtitle: 'Upload document/photo',
          icon: Icons.verified_user_outlined,
          image: policeClearance,
          onTap: () {},
        ),
        const SizedBox(height: 10),

        _UploadTile(
          title: 'MTOP (Motorized Tricycle Operator’s Permit)',
          subtitle: 'Upload document/photo',
          icon: Icons.description_outlined,
          image: mtop,
          onTap: () {},
        ),

        const SizedBox(height: 16),
        const _SectionTitle('Upload Vehicle Requirements'),
        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: _UploadTile(
                title: 'Vehicle (Front)',
                subtitle: 'Photo',
                icon: Icons.directions_car_filled_outlined,
                image: vehicleFront,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _UploadTile(
                title: 'Vehicle (Back)',
                subtitle: 'Photo',
                icon: Icons.directions_car_filled_outlined,
                image: vehicleBack,
                onTap: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _UploadTile(
                title: 'Vehicle (Left)',
                subtitle: 'Photo',
                icon: Icons.directions_car_filled_outlined,
                image: vehicleLeft,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _UploadTile(
                title: 'Vehicle (Right)',
                subtitle: 'Photo',
                icon: Icons.directions_car_filled_outlined,
                image: vehicleRight,
                onTap: () {},
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),

        Row(
          children: [
            Expanded(
              child: _UploadTile(
                title: 'Official Receipt (OR)',
                subtitle: 'Upload document/photo',
                icon: Icons.receipt_long_outlined,
                image: orDoc,
                onTap: () {},
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _UploadTile(
                title: 'Certificate of Registration (CR)',
                subtitle: 'Upload document/photo',
                icon: Icons.article_outlined,
                image: crDoc,
                onTap: () {},
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFF1F5F9),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: const Color(0xFFE2E8F0)),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Checkbox(
                value: _agreed,
                onChanged: (v) => setState(() => _agreed = v ?? false),
              ),
              const SizedBox(width: 6),
              const Expanded(
                child: Text(
                  'By proceeding you agree to Terms and Conditions and acknowledge you have read the Privacy Policy.',
                  style: TextStyle(
                    fontSize: 12.8,
                    height: 1.25,
                    fontWeight: FontWeight.w700,
                    color: Color(0xFF334155),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _fmtDate(DateTime d) {
    final mm = d.month.toString().padLeft(2, '0');
    final dd = d.day.toString().padLeft(2, '0');
    return '${d.year}-$mm-$dd';
  }
}

// ---------------- UI helpers (same style as your tourist screen) ----------------

class _StepDots extends StatelessWidget {
  const _StepDots({required this.current, required this.total});

  final int current;
  final int total;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(total, (i) {
        final active = i == current;
        return AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          margin: const EdgeInsets.symmetric(horizontal: 5),
          width: active ? 22 : 8,
          height: 8,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(99),
            color: active ? const Color(0xFF2A86FF) : const Color(0xFFC7D2FE),
          ),
        );
      }),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text);
  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 16,
        fontWeight: FontWeight.w900,
        color: Color(0xFF0F172A),
      ),
    );
  }
}

class _GlassCard extends StatelessWidget {
  const _GlassCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.92),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.07),
            blurRadius: 24,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _GradientButton extends StatelessWidget {
  const _GradientButton({required this.text, required this.onPressed});
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
        ),
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A86FF).withOpacity(0.30),
            blurRadius: 22,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.transparent,
          shadowColor: Colors.transparent,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Center(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w900,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ),
      ),
    );
  }
}

class _OutlinedButton extends StatelessWidget {
  const _OutlinedButton({required this.text, required this.onPressed});
  final String text;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: OutlinedButton(
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: Color(0xFFE2E8F0)),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
        child: Text(
          text,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
      ),
    );
  }
}

class _Label extends StatelessWidget {
  const _Label({required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 15,
          fontWeight: FontWeight.w900,
          color: Color(0xFF0F172A),
        ),
      ),
    );
  }
}

class _FancyInputField extends StatefulWidget {
  const _FancyInputField({
    required this.controller,
    required this.hintText,
    required this.prefixIcon,
    this.keyboardType,
  });

  final TextEditingController controller;
  final String hintText;
  final IconData prefixIcon;
  final TextInputType? keyboardType;

  @override
  State<_FancyInputField> createState() => _FancyInputFieldState();
}

class _FancyInputFieldState extends State<_FancyInputField> {
  final _focus = FocusNode();

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final focused = _focus.hasFocus;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        color: Colors.white,
        border: Border.all(
          color: focused ? const Color(0xFF2A86FF) : const Color(0xFFE2E8F0),
          width: focused ? 1.5 : 1,
        ),
        boxShadow: [
          if (focused)
            BoxShadow(
              color: const Color(0xFF2A86FF).withOpacity(0.18),
              blurRadius: 18,
              offset: const Offset(0, 10),
            )
          else
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
        ],
      ),
      child: TextField(
        focusNode: _focus,
        controller: widget.controller,
        keyboardType: widget.keyboardType,
        style: const TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w800,
          color: Color(0xFF0F172A),
        ),
        decoration: InputDecoration(
          hintText: widget.hintText,
          hintStyle: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: Color(0xFF94A3B8),
          ),
          prefixIcon: Icon(widget.prefixIcon, color: const Color(0xFF94A3B8)),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide.none,
          ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  const _DateField({
    required this.valueText,
    required this.icon,
    required this.onTap,
  });

  final String valueText;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        height: 56,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          color: Colors.white,
          border: Border.all(color: const Color(0xFFE2E8F0), width: 1),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 16,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Icon(icon, color: const Color(0xFF94A3B8)),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                valueText,
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: valueText.contains('Select') ? const Color(0xFF94A3B8) : const Color(0xFF0F172A),
                ),
              ),
            ),
            const Icon(Icons.expand_more_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}

class _UploadTile extends StatelessWidget {
  const _UploadTile({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.onTap,
    this.image,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final VoidCallback onTap;
  final ImageProvider? image;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        height: 74,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFE2E8F0)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 50,
              height: 50,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(14),
                color: const Color(0xFFEAF1FF),
              ),
              child: image != null
                  ? ClipRRect(borderRadius: BorderRadius.circular(14), child: Image(image: image!, fit: BoxFit.cover))
                  : Icon(icon, color: const Color(0xFF2A86FF)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF0F172A))),
                  const SizedBox(height: 3),
                  Text(subtitle, style: const TextStyle(fontWeight: FontWeight.w700, color: Color(0xFF64748B), fontSize: 12.5)),
                ],
              ),
            ),
            const Icon(Icons.upload_rounded, color: Color(0xFF94A3B8)),
          ],
        ),
      ),
    );
  }
}