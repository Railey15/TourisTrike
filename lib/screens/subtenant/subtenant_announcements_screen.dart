import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantAnnouncementsScreen extends StatefulWidget {
  const SubTenantAnnouncementsScreen({super.key});

  @override
  State<SubTenantAnnouncementsScreen> createState() =>
      _SubTenantAnnouncementsScreenState();
}

class _SubTenantAnnouncementsScreenState
    extends State<SubTenantAnnouncementsScreen> {
  final SubTenantService _service = SubTenantService();
  late Future<_AnnouncementsLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_AnnouncementsLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final result = await _service.fetchAnnouncements(profile);
    return _AnnouncementsLoad(profile: profile, result: result);
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _openForm(
    _AnnouncementsLoad load, [
    SubTenantAnnouncement? announcement,
  ]) async {
    if (!load.result.tableAvailable) {
      showSubTenantSnack(
        context,
        'Create city_announcements before enabling announcement CRUD.',
      );
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AnnouncementSheet(
        service: _service,
        profile: load.profile,
        announcement: announcement,
      ),
    );

    if (saved == true) _reload();
  }

  Future<void> _delete(
    _AnnouncementsLoad load,
    SubTenantAnnouncement announcement,
  ) async {
    try {
      await _service.deleteAnnouncement(load.profile, announcement);
      if (!mounted) return;
      showSubTenantSnack(context, 'Announcement deleted.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to delete announcement: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SubTenantColors.background,
      appBar: subTenantAppBar(context, title: 'Announcements', showBack: true),
      body: FutureBuilder<_AnnouncementsLoad>(
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

          final load = snapshot.data!;
          final result = load.result;
          return RefreshIndicator(
            onRefresh: () async => _reload(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
              children: [
                if (!result.tableAvailable)
                  const SubTenantEmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'Announcements table needed',
                    message:
                        'TODO: create city_announcements(id, created_by, city, title, body, status, created_at) to enable CRUD.',
                  )
                else if (result.items.isEmpty)
                  SubTenantEmptyState(
                    icon: Icons.campaign_outlined,
                    title: 'No announcements yet',
                    message:
                        'Create local announcements for ${load.profile.assignedCity}.',
                    actionLabel: 'Create Announcement',
                    onAction: () => _openForm(load),
                  )
                else
                  ...result.items.map(
                    (announcement) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _AnnouncementCard(
                        announcement: announcement,
                        onEdit: () => _openForm(load, announcement),
                        onDelete: () => _delete(load, announcement),
                      ),
                    ),
                  ),
              ],
            ),
          );
        },
      ),
      floatingActionButton: FutureBuilder<_AnnouncementsLoad>(
        future: _future,
        builder: (context, snapshot) {
          final load = snapshot.data;
          if (load == null || !load.result.tableAvailable) {
            return const SizedBox.shrink();
          }
          return FloatingActionButton(
            heroTag: 'subtenant_announcement_add_fab',
            backgroundColor: SubTenantColors.blue,
            foregroundColor: Colors.white,
            onPressed: () => _openForm(load),
            child: const Icon(Icons.add_rounded),
          );
        },
      ),
    );
  }
}

class _AnnouncementCard extends StatelessWidget {
  const _AnnouncementCard({
    required this.announcement,
    required this.onEdit,
    required this.onDelete,
  });

  final SubTenantAnnouncement announcement;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final date = announcement.createdAt == null
        ? 'No date'
        : DateFormat('MMM d, yyyy').format(announcement.createdAt!);

    return SubTenantDashboardCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  announcement.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 16,
                  ),
                ),
              ),
              PopupMenuButton<String>(
                onSelected: (value) {
                  if (value == 'edit') onEdit();
                  if (value == 'delete') onDelete();
                },
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            announcement.body,
            style: const TextStyle(
              color: SubTenantColors.muted,
              fontWeight: FontWeight.w600,
              height: 1.35,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              SubTenantStatusPill(status: announcement.status),
              const Spacer(),
              Text(
                date,
                style: const TextStyle(
                  color: SubTenantColors.lightMuted,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _AnnouncementSheet extends StatefulWidget {
  const _AnnouncementSheet({
    required this.service,
    required this.profile,
    required this.announcement,
  });

  final SubTenantService service;
  final SubTenantProfile profile;
  final SubTenantAnnouncement? announcement;

  @override
  State<_AnnouncementSheet> createState() => _AnnouncementSheetState();
}

class _AnnouncementSheetState extends State<_AnnouncementSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleCtrl;
  late final TextEditingController _bodyCtrl;
  String _status = 'draft';
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _titleCtrl = TextEditingController(text: widget.announcement?.title ?? '');
    _bodyCtrl = TextEditingController(text: widget.announcement?.body ?? '');
    _status = widget.announcement?.status ?? 'draft';
  }

  @override
  void dispose() {
    _titleCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    try {
      await widget.service.saveAnnouncement(
        profile: widget.profile,
        announcementId: widget.announcement?.id,
        title: _titleCtrl.text,
        body: _bodyCtrl.text,
        status: _status,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to save announcement: $e');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      padding: EdgeInsets.fromLTRB(16, 12, 16, 16 + bottomInset),
      decoration: const BoxDecoration(
        color: SubTenantColors.background,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Form(
        key: _formKey,
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 48,
                  height: 5,
                  decoration: BoxDecoration(
                    color: const Color(0xFFD1D5DB),
                    borderRadius: BorderRadius.circular(999),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                widget.announcement == null
                    ? 'Create Announcement'
                    : 'Edit Announcement',
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              SubTenantTextField(
                controller: _titleCtrl,
                label: 'Title',
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              SubTenantTextField(
                controller: _bodyCtrl,
                label: 'Body',
                maxLines: 4,
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Required' : null,
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<String>(
                initialValue: _status,
                decoration: InputDecoration(
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: SubTenantColors.line),
                  ),
                ),
                items: const [
                  DropdownMenuItem(value: 'draft', child: Text('Draft')),
                  DropdownMenuItem(
                    value: 'published',
                    child: Text('Published'),
                  ),
                  DropdownMenuItem(value: 'archived', child: Text('Archived')),
                ],
                onChanged: (value) {
                  if (value != null) setState(() => _status = value);
                },
              ),
              const SizedBox(height: 18),
              SubTenantGradientButton(
                label: 'Save Announcement',
                icon: Icons.save_rounded,
                loading: _saving,
                onPressed: _save,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AnnouncementsLoad {
  const _AnnouncementsLoad({required this.profile, required this.result});

  final SubTenantProfile profile;
  final SubTenantAnnouncementsResult result;
}
