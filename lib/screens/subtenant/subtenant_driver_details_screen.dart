import 'package:flutter/material.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantDriverDetailsScreen extends StatefulWidget {
  const SubTenantDriverDetailsScreen({super.key, required this.driverId});

  final String driverId;

  @override
  State<SubTenantDriverDetailsScreen> createState() =>
      _SubTenantDriverDetailsScreenState();
}

class _SubTenantDriverDetailsScreenState
    extends State<SubTenantDriverDetailsScreen> {
  final SubTenantService _service = SubTenantService();

  late Future<_DriverDetailsLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_DriverDetailsLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final driver = await _service.fetchDriverById(profile, widget.driverId);

    if (driver == null) {
      throw StateError('Driver not found in your assigned city.');
    }

    var reviews = const <SubTenantDriverReview>[];
    try {
      reviews = await _service.fetchDriverReviews(profile, driver.id);
    } catch (e, stack) {
      debugPrint('Failed to fetch driver reviews: $e\n$stack');
    }

    return _DriverDetailsLoad(
      profile: profile,
      driver: driver,
      reviews: reviews,
    );
  }

  void _reload() {
  final nextFuture = _load();

  setState(() {
    _future = nextFuture;
  });
}

  Future<void> _setStatus(
    SubTenantProfile profile,
    SubTenantDriver driver,
    String status,
  ) async {
    try {
      await _service.updateDriverStatus(profile, driver, status);
      if (!mounted) return;
      showSubTenantSnack(context, 'Driver status updated.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to update driver status: $e');
    }
  }

  void _contact(SubTenantDriver driver) {
    final mobile =
        driver.mobile.isEmpty ? 'No mobile number saved' : driver.mobile;
    showSubTenantSnack(context, mobile, error: false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SubTenantColors.background,
      appBar: subTenantAppBar(context, title: 'Driver Details', showBack: true),
      body: FutureBuilder<_DriverDetailsLoad>(
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

          final load = snapshot.data;
          if (load == null) {
            return SubTenantErrorView(
              message: 'Unable to load driver details.',
              onRetry: _reload,
            );
          }

          final driver = load.driver;

          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const BouncingScrollPhysics(
                parent: AlwaysScrollableScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 28),
              children: [
                _DriverHeroCard(
                  driver: driver,
                  reviews: load.reviews,
                  onContact: () => _contact(driver),
                  onApprove: driver.status == 'approved'
                      ? null
                      : () => _setStatus(load.profile, driver, 'approved'),
                  onSuspend: driver.status == 'suspended'
                      ? null
                      : () => _setStatus(load.profile, driver, 'suspended'),
                ),
                const SizedBox(height: 14),
                LayoutBuilder(
                  builder: (context, constraints) {
                    final twoColumns = constraints.maxWidth >= 850;

                    if (!twoColumns) {
                      return Column(
                        children: [
                          _ProfileCard(driver: driver),
                          const SizedBox(height: 14),
                          _DriverInfoCard(driver: driver),
                        ],
                      );
                    }

                    return IntrinsicHeight(
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Expanded(child: _ProfileCard(driver: driver)),
                          const SizedBox(width: 14),
                          Expanded(child: _DriverInfoCard(driver: driver)),
                        ],
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                _DocumentsCard(driver: driver),
                const SizedBox(height: 14),
                _RatingsFeedbackCard(
                  driver: driver,
                  reviews: load.reviews,
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _DriverHeroCard extends StatelessWidget {
  const _DriverHeroCard({
    required this.driver,
    required this.reviews,
    required this.onContact,
    required this.onApprove,
    required this.onSuspend,
  });

  final SubTenantDriver driver;
  final List<SubTenantDriverReview> reviews;
  final VoidCallback onContact;
  final VoidCallback? onApprove;
  final VoidCallback? onSuspend;

  bool get _isApproved => driver.status == 'approved';
  bool get _isSuspended => driver.status == 'suspended';

  double get _averageRating {
    if (reviews.isNotEmpty) {
      final total =
          reviews.fold<int>(0, (sum, review) => sum + review.rating);
      return total / reviews.length;
    }
    return driver.averageRating;
  }

  bool get _hasRating =>
      reviews.isNotEmpty ||
      (driver.averageRating > 0 && driver.totalReviews > 0);

  @override
  Widget build(BuildContext context) {
    final actions = [
      if (!_isApproved)
        _HeroActionButton(
          label: 'Approve Driver',
          icon: Icons.verified_rounded,
          onPressed: onApprove,
          filled: true,
        ),
      if (!_isSuspended)
        _HeroActionButton(
          label: 'Suspend Driver',
          icon: Icons.block_rounded,
          onPressed: onSuspend,
          danger: true,
        ),
    ];

    return Container(
      decoration: BoxDecoration(
        gradient: SubTenantColors.gradient,
        borderRadius: BorderRadius.circular(26),
        boxShadow: [
          BoxShadow(
            color: SubTenantColors.blue.withValues(alpha: 0.18),
            blurRadius: 24,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(22),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 72,
                  height: 72,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.18),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.25),
                    ),
                  ),
                  child: const Icon(
                    Icons.person_rounded,
                    color: Colors.white,
                    size: 40,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        driver.fullName.isEmpty
                            ? 'Unnamed Driver'
                            : driver.fullName,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          _LightStatusPill(
                            label: driver.isOnline ? 'Online' : 'Offline',
                            icon: Icons.circle,
                          ),
                          _LightStatusPill(
                            label: _prettyStatus(driver.status),
                            icon: _isApproved
                                ? Icons.verified_rounded
                                : _isSuspended
                                    ? Icons.block_rounded
                                    : Icons.pending_rounded,
                          ),
                          _LightStatusPill(
                            label: !_hasRating
                                ? 'No Rating'
                                : '${_averageRating.toStringAsFixed(1)} Rating',
                            icon: Icons.star_rounded,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  onPressed: onContact,
                  icon: const Icon(Icons.call_rounded),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: SubTenantColors.blue,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            if (actions.isEmpty)
              const _ApprovedMessage()
            else
              Row(
                children: [
                  for (final action in actions) ...[
                    Expanded(child: action),
                    if (action != actions.last) const SizedBox(width: 10),
                  ],
                ],
              ),
          ],
        ),
      ),
    );
  }

  String _prettyStatus(String value) {
    if (value.isEmpty) return 'No Status';
    return value[0].toUpperCase() + value.substring(1);
  }
}

class _ApprovedMessage extends StatelessWidget {
  const _ApprovedMessage();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withValues(alpha: 0.20)),
      ),
      child: const Row(
        children: [
          Icon(Icons.check_circle_rounded, color: Colors.white, size: 18),
          SizedBox(width: 8),
          Expanded(
            child: Text(
              'This driver is already approved and active.',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 12.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeroActionButton extends StatelessWidget {
  const _HeroActionButton({
    required this.label,
    required this.icon,
    required this.onPressed,
    this.filled = false,
    this.danger = false,
  });

  final String label;
  final IconData icon;
  final VoidCallback? onPressed;
  final bool filled;
  final bool danger;

  @override
  Widget build(BuildContext context) {
    if (filled) {
      return FilledButton.icon(
        onPressed: onPressed,
        icon: Icon(icon, size: 17),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: SubTenantColors.blue,
          elevation: 0,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(15),
          ),
        ),
      );
    }

    return OutlinedButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 17),
      label: Text(label),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: BorderSide(
          color: danger
              ? const Color(0xFFFCA5A5)
              : Colors.white.withValues(alpha: 0.65),
        ),
        padding: const EdgeInsets.symmetric(vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(15),
        ),
      ),
    );
  }
}

class _LightStatusPill extends StatelessWidget {
  const _LightStatusPill({required this.label, required this.icon});

  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withValues(alpha: 0.22)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            label,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.driver});

  final SubTenantDriver driver;

  @override
  Widget build(BuildContext context) {
    return _DetailCard(
      title: 'Profile',
      subtitle: 'Basic contact and location information.',
      icon: Icons.account_circle_rounded,
      children: [
        _InfoRow(
          icon: Icons.phone_rounded,
          label: 'Mobile',
          value: driver.mobile.isEmpty ? 'Not provided' : driver.mobile,
        ),
        _InfoRow(
          icon: Icons.home_rounded,
          label: 'Address',
          value: driver.address.isEmpty ? 'Not provided' : driver.address,
        ),
        _InfoRow(
          icon: Icons.location_city_rounded,
          label: 'Assigned City',
          value: driver.city.isEmpty ? 'Not assigned' : driver.city,
        ),
        const _HiddenInfoRow(),
      ],
    );
  }
}

class _DriverInfoCard extends StatelessWidget {
  const _DriverInfoCard({required this.driver});

  final SubTenantDriver driver;

  @override
  Widget build(BuildContext context) {
    return _DetailCard(
      title: 'Driver Details',
      subtitle: 'Vehicle, TODA, and operator information.',
      icon: Icons.local_taxi_rounded,
      children: [
        _InfoRow(
          icon: Icons.badge_rounded,
          label: 'License Number',
          value:
              driver.licenseNumber.isEmpty ? 'Not provided' : driver.licenseNumber,
        ),
        _InfoRow(
          icon: Icons.confirmation_number_rounded,
          label: 'Plate Number',
          value: driver.plateNumber.isEmpty ? 'Not provided' : driver.plateNumber,
        ),
        _InfoRow(
          icon: Icons.groups_rounded,
          label: 'TODA Name',
          value: driver.todaName.isEmpty ? 'Not provided' : driver.todaName,
        ),
        _InfoRow(
          icon: Icons.qr_code_rounded,
          label: 'Operator Code',
          value:
              driver.operatorCode.isEmpty ? 'Not provided' : driver.operatorCode,
        ),
      ],
    );
  }
}

class _DocumentsCard extends StatelessWidget {
  const _DocumentsCard({required this.driver});

  final SubTenantDriver driver;

  @override
  Widget build(BuildContext context) {
    final docs = driver.documentLinks;

    return _DetailCard(
      title: 'Documents',
      subtitle: 'Uploaded driver verification documents.',
      icon: Icons.description_rounded,
      children: [
        if (docs.isEmpty)
          const _EmptyCardBody(
            icon: Icons.description_outlined,
            title: 'No documents uploaded',
            message: 'Driver documents from driver_documents will appear here.',
          )
        else ...[
          _DocumentSummaryBar(
            uploaded: driver.uploadedDocumentCount,
            required: driver.requiredDocumentCount,
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 720 ? 3 : 2;

              return GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: docs.length,
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: columns,
                  crossAxisSpacing: 12,
                  mainAxisSpacing: 12,
                  childAspectRatio: 0.84,
                ),
                itemBuilder: (context, index) {
                  final doc = docs[index];
                  return _DocumentPreviewCard(
                    doc: doc,
                    onTap: () => _showDocumentPreview(context, doc),
                  );
                },
              );
            },
          ),
        ],
      ],
    );
  }
}

class _DocumentSummaryBar extends StatelessWidget {
  const _DocumentSummaryBar({
    required this.uploaded,
    required this.required,
  });

  final int uploaded;
  final int required;

  bool get isComplete => uploaded >= required;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isComplete ? const Color(0xFFECFDF5) : const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isComplete ? const Color(0xFF86EFAC) : SubTenantColors.line,
        ),
      ),
      child: Row(
        children: [
          Icon(
            isComplete ? Icons.verified_rounded : Icons.folder_open_rounded,
            color: isComplete ? const Color(0xFF16A34A) : SubTenantColors.blue,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              '$uploaded of $required documents uploaded',
              style: TextStyle(
                color: SubTenantColors.text,
                fontWeight: FontWeight.w800,
                fontSize: 14,
              ),
            ),
          ),
          Text(
            '${((uploaded / required) * 100).round()}%',
            style: TextStyle(
              color: isComplete ? const Color(0xFF16A34A) : SubTenantColors.muted,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}

class _DocumentPreviewCard extends StatelessWidget {
  const _DocumentPreviewCard({
    required this.doc,
    required this.onTap,
  });

  final SubTenantDocumentLink doc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: Ink(
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SubTenantColors.line),
            boxShadow: [
              BoxShadow(
                color: SubTenantColors.shadow,
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: ClipRRect(
                  borderRadius: const BorderRadius.vertical(
                    top: Radius.circular(17),
                  ),
                  child: _DocumentImage(url: doc.url, label: doc.label),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 10, 10),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        doc.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 13,
                        ),
                      ),
                    ),
                    const Icon(
                      Icons.zoom_in_rounded,
                      size: 18,
                      color: SubTenantColors.blue,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DocumentImage extends StatelessWidget {
  const _DocumentImage({required this.url, required this.label});

  final String url;
  final String label;

  @override
  Widget build(BuildContext context) {
    if (url.trim().isEmpty) {
      return _DocumentImagePlaceholder(label: label);
    }

    return Image.network(
      url,
      fit: BoxFit.cover,
      width: double.infinity,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: const Color(0xFFE4ECF7),
          alignment: Alignment.center,
          child: const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 2.5),
          ),
        );
      },
      errorBuilder: (_, _, _) => _DocumentImagePlaceholder(
        label: label,
        message: 'Preview unavailable',
      ),
    );
  }
}

class _DocumentImagePlaceholder extends StatelessWidget {
  const _DocumentImagePlaceholder({
    required this.label,
    this.message,
  });

  final String label;
  final String? message;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFFE4ECF7),
      alignment: Alignment.center,
      padding: const EdgeInsets.all(12),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(
            Icons.image_not_supported_outlined,
            color: SubTenantColors.lightMuted,
            size: 30,
          ),
          const SizedBox(height: 8),
          Text(
            message ?? label,
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: SubTenantColors.lightMuted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> _showDocumentPreview(
  BuildContext context,
  SubTenantDocumentLink doc,
) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      return Dialog(
        insetPadding: const EdgeInsets.all(20),
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: 560,
            maxHeight: MediaQuery.sizeOf(dialogContext).height * 0.82,
          ),
          child: Padding(
            padding: const EdgeInsets.all(18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        doc.label,
                        style: const TextStyle(
                          color: SubTenantColors.text,
                          fontWeight: FontWeight.w900,
                          fontSize: 18,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.of(dialogContext).pop(),
                      icon: const Icon(Icons.close_rounded),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Flexible(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(18),
                    child: Container(
                      color: const Color(0xFFF7FAFF),
                      child: doc.url.trim().isEmpty
                          ? const _DocumentImagePlaceholder(
                              label: 'Document',
                              message: 'No image available for this document.',
                            )
                          : InteractiveViewer(
                              minScale: 0.75,
                              maxScale: 4,
                              child: Image.network(
                                doc.url,
                                fit: BoxFit.contain,
                                errorBuilder: (_, _, _) =>
                                    const _DocumentImagePlaceholder(
                                  label: 'Document',
                                  message: 'Preview unavailable.',
                                ),
                              ),
                            ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton(
                    onPressed: () => Navigator.of(dialogContext).pop(),
                    style: FilledButton.styleFrom(
                      backgroundColor: SubTenantColors.blue,
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: const Text('Close'),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
}

class _RatingsFeedbackCard extends StatelessWidget {
  const _RatingsFeedbackCard({
    required this.driver,
    required this.reviews,
  });

  final SubTenantDriver driver;
  final List<SubTenantDriverReview> reviews;

  double get averageRating {
    if (reviews.isNotEmpty) {
      final total = reviews.fold<int>(0, (sum, review) => sum + review.rating);
      return total / reviews.length;
    }
    return driver.averageRating;
  }

  bool get hasRating =>
      reviews.isNotEmpty ||
      (driver.averageRating > 0 && driver.totalReviews > 0);

  int get reviewCount =>
      reviews.isNotEmpty ? reviews.length : driver.totalReviews;

  @override
  Widget build(BuildContext context) {
    return _DetailCard(
      title: 'Ratings & Feedback',
      subtitle: 'Reviews submitted by tourists after completed bookings.',
      icon: Icons.star_rounded,
      children: [
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFFF7FAFF),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: SubTenantColors.line),
          ),
          child: Row(
            children: [
              Container(
                width: 58,
                height: 58,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF7E6),
                  borderRadius: BorderRadius.circular(18),
                ),
                child: const Icon(
                  Icons.star_rounded,
                  color: Color(0xFFF59E0B),
                  size: 34,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Text(
                  !hasRating
                      ? 'No rating yet'
                      : '${averageRating.toStringAsFixed(1)} average rating from $reviewCount review${reviewCount == 1 ? '' : 's'}',
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontSize: 20,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 12),
        if (reviews.isEmpty)
          const _EmptyCardBody(
            icon: Icons.rate_review_outlined,
            title: 'No feedback yet',
            message:
                'No matching records were found in driver_reviews for this driver.',
          )
        else
          ...reviews.map((review) => _FeedbackTile(review: review)),
      ],
    );
  }
}

class _FeedbackTile extends StatelessWidget {
  const _FeedbackTile({required this.review});

  final SubTenantDriverReview review;

  String get formattedDate {
    final date = review.createdAt;
    if (date == null) return '';
    return '${date.month.toString().padLeft(2, '0')}/${date.day.toString().padLeft(2, '0')}/${date.year}';
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFF7FAFF),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_rounded, color: SubTenantColors.blue),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  review.touristName,
                  style: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
              const Icon(Icons.star_rounded, color: Color(0xFFF59E0B), size: 17),
              Text(
                review.rating.toString(),
                style: const TextStyle(fontWeight: FontWeight.w900),
              ),
            ],
          ),
          if (formattedDate.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              formattedDate,
              style: const TextStyle(
                color: SubTenantColors.muted,
                fontSize: 12,
              ),
            ),
          ],
          const SizedBox(height: 8),
          Text(
            review.reviewText.trim().isEmpty
                ? 'No written feedback provided.'
                : review.reviewText.trim(),
            style: const TextStyle(fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }
}

class _DetailCard extends StatelessWidget {
  const _DetailCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.children,
  });

  final String title;
  final String subtitle;
  final IconData icon;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: SubTenantColors.blue),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 15,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: Icon(icon, color: SubTenantColors.blue),
      title: Text(label),
      subtitle: Text(value),
    );
  }
}

class _HiddenInfoRow extends StatelessWidget {
  const _HiddenInfoRow();

  @override
  Widget build(BuildContext context) {
    return const SizedBox(height: 72);
  }
}

class _EmptyCardBody extends StatelessWidget {
  const _EmptyCardBody({
    required this.icon,
    required this.title,
    required this.message,
  });

  final IconData icon;
  final String title;
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          children: [
            Icon(icon, color: SubTenantColors.blue, size: 34),
            const SizedBox(height: 10),
            Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(message, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}

class _DriverDetailsLoad {
  const _DriverDetailsLoad({
    required this.profile,
    required this.driver,
    required this.reviews,
  });

  final SubTenantProfile profile;
  final SubTenantDriver driver;
  final List<SubTenantDriverReview> reviews;
}