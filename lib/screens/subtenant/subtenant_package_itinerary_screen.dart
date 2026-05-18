import 'package:flutter/material.dart';
import 'package:touristrike/screens/subtenant/subtenant_models.dart';
import 'package:touristrike/screens/subtenant/subtenant_service.dart';
import 'package:touristrike/screens/subtenant/widgets/subtenant_components.dart';

class SubTenantPackageItineraryScreen extends StatefulWidget {
  const SubTenantPackageItineraryScreen({super.key, required this.package});

  final SubTenantPackage package;

  @override
  State<SubTenantPackageItineraryScreen> createState() =>
      _SubTenantPackageItineraryScreenState();
}

class _SubTenantPackageItineraryScreenState
    extends State<SubTenantPackageItineraryScreen> {
  final SubTenantService _service = SubTenantService();
  late Future<_ItineraryLoad> _future;

  @override
  void initState() {
    super.initState();
    _future = _load();
  }

  Future<_ItineraryLoad> _load() async {
    final profile = await _service.loadCurrentProfile();
    final package = await _service.fetchPackageById(profile, widget.package.id);
    if (package == null) {
      throw StateError('Package not found in your assigned city.');
    }

    final days = await _service.fetchItinerary(profile, package.id);
    final spots = (await _service.fetchSpots(
      profile,
    )).where((spot) => spot.status != 'archived').toList(growable: false);

    return _ItineraryLoad(
      profile: profile,
      package: package,
      days: days,
      spots: spots,
    );
  }

  void _reload() {
    setState(() => _future = _load());
  }

  Future<void> _addDay(_ItineraryLoad load) async {
    try {
      await _service.addPackageDay(
        load.profile,
        load.package.id,
        load.days.length + 1,
      );
      if (!mounted) return;
      showSubTenantSnack(context, 'Package day added.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to add day: $e');
    }
  }

  Future<void> _renameDay(_ItineraryLoad load, PackageItineraryDay day) async {
    final controller = TextEditingController(text: day.title);
    final title = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Rename day'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(labelText: 'Day title'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    controller.dispose();
    if (title == null) return;

    try {
      await _service.updatePackageDayTitle(
        load.profile,
        load.package.id,
        day.id,
        title,
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to rename day: $e');
    }
  }

  Future<void> _openItemForm(
    _ItineraryLoad load,
    PackageItineraryDay day, {
    PackageItineraryItem? item,
  }) async {
    if (load.spots.isEmpty) {
      showSubTenantSnack(
        context,
        'Add tourist spots for ${load.profile.assignedCity} first.',
      );
      return;
    }

    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ItineraryItemSheet(
        service: _service,
        profile: load.profile,
        packageId: load.package.id,
        day: day,
        spots: load.spots,
        item: item,
      ),
    );

    if (saved == true) _reload();
  }

  Future<void> _deleteItem(
    _ItineraryLoad load,
    PackageItineraryItem item,
  ) async {
    try {
      await _service.deleteItineraryItem(load.profile, load.package.id, item);
      if (!mounted) return;
      showSubTenantSnack(context, 'Itinerary item removed.', error: false);
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to remove item: $e');
    }
  }

  Future<void> _moveItem(
    _ItineraryLoad load,
    PackageItineraryDay day,
    int oldIndex,
    int newIndex,
  ) async {
    final items = [...day.items];
    if (newIndex < 0 || newIndex >= items.length) return;

    final moved = items.removeAt(oldIndex);
    items.insert(newIndex, moved);

    try {
      await _service.updateItineraryItemOrder(
        load.profile,
        load.package.id,
        items,
      );
      _reload();
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to reorder item: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: SubTenantColors.background,
      appBar: subTenantAppBar(
        context,
        title: 'Package Itinerary',
        showBack: true,
      ),
      body: FutureBuilder<_ItineraryLoad>(
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
          return ListView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
            children: [
              SubTenantDashboardCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      load.package.title,
                      style: const TextStyle(
                        color: SubTenantColors.text,
                        fontSize: 19,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 5),
                    Text(
                      '${load.package.city} - ${load.package.durationText}',
                      style: const TextStyle(
                        color: SubTenantColors.muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 12),
                    SubTenantGradientButton(
                      label: 'Add Package Day',
                      icon: Icons.add_rounded,
                      onPressed: () => _addDay(load),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              if (load.days.isEmpty)
                SubTenantEmptyState(
                  icon: Icons.map_outlined,
                  title: 'No itinerary yet',
                  message:
                      'Add days and stops using tourist spots from ${load.profile.assignedCity}.',
                  actionLabel: 'Add Day',
                  onAction: () => _addDay(load),
                )
              else
                ...load.days.map(
                  (day) => Padding(
                    padding: const EdgeInsets.only(bottom: 14),
                    child: _DayCard(
                      day: day,
                      onRename: () => _renameDay(load, day),
                      onAddItem: () => _openItemForm(load, day),
                      onEditItem: (item) =>
                          _openItemForm(load, day, item: item),
                      onDeleteItem: (item) => _deleteItem(load, item),
                      onMoveItem: (oldIndex, newIndex) =>
                          _moveItem(load, day, oldIndex, newIndex),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _DayCard extends StatelessWidget {
  const _DayCard({
    required this.day,
    required this.onRename,
    required this.onAddItem,
    required this.onEditItem,
    required this.onDeleteItem,
    required this.onMoveItem,
  });

  final PackageItineraryDay day;
  final VoidCallback onRename;
  final VoidCallback onAddItem;
  final ValueChanged<PackageItineraryItem> onEditItem;
  final ValueChanged<PackageItineraryItem> onDeleteItem;
  final void Function(int oldIndex, int newIndex) onMoveItem;

  @override
  Widget build(BuildContext context) {
    return SubTenantDashboardCard(
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SubTenantSectionHeader(
                  title: 'Day ${day.dayNumber}',
                  subtitle: day.title,
                ),
              ),
              IconButton(
                tooltip: 'Rename day',
                onPressed: onRename,
                icon: const Icon(Icons.edit_rounded),
                color: SubTenantColors.blue,
              ),
              IconButton(
                tooltip: 'Add stop',
                onPressed: onAddItem,
                icon: const Icon(Icons.add_location_alt_rounded),
                color: SubTenantColors.blue,
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (day.items.isEmpty)
            const SubTenantEmptyState(
              icon: Icons.route_outlined,
              title: 'No stops for this day',
              message: 'Add itinerary items from your local tourist spots.',
            )
          else
            ...day.items.asMap().entries.map(
              (entry) => _ItineraryTile(
                item: entry.value,
                index: entry.key,
                total: day.items.length,
                onEdit: () => onEditItem(entry.value),
                onDelete: () => onDeleteItem(entry.value),
                onMoveUp: () => onMoveItem(entry.key, entry.key - 1),
                onMoveDown: () => onMoveItem(entry.key, entry.key + 1),
              ),
            ),
        ],
      ),
    );
  }
}

class _ItineraryTile extends StatelessWidget {
  const _ItineraryTile({
    required this.item,
    required this.index,
    required this.total,
    required this.onEdit,
    required this.onDelete,
    required this.onMoveUp,
    required this.onMoveDown,
  });

  final PackageItineraryItem item;
  final int index;
  final int total;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onMoveUp;
  final VoidCallback onMoveDown;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF8FBFF),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: SubTenantColors.line),
      ),
      child: Row(
        children: [
          Container(
            width: 50,
            height: 50,
            decoration: BoxDecoration(
              color: const Color(0xFFE8EEF7),
              borderRadius: BorderRadius.circular(15),
              image: item.spotImageUrl.isEmpty
                  ? null
                  : DecorationImage(
                      image: NetworkImage(item.spotImageUrl),
                      fit: BoxFit.cover,
                    ),
            ),
            child: item.spotImageUrl.isEmpty
                ? const Icon(
                    Icons.place_rounded,
                    color: SubTenantColors.lightMuted,
                  )
                : null,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.spotTitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.text,
                    fontWeight: FontWeight.w900,
                    fontSize: 13.5,
                  ),
                ),
                const SizedBox(height: 3),
                Text(
                  [
                    if (item.timeLabel.isNotEmpty) item.timeLabel,
                    if (item.note.isNotEmpty) item.note,
                  ].join(' - '),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    color: SubTenantColors.muted,
                    fontWeight: FontWeight.w600,
                    fontSize: 12,
                  ),
                ),
              ],
            ),
          ),
          Column(
            children: [
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Move up',
                    visualDensity: VisualDensity.compact,
                    onPressed: index == 0 ? null : onMoveUp,
                    icon: const Icon(Icons.keyboard_arrow_up_rounded),
                  ),
                  IconButton(
                    tooltip: 'Move down',
                    visualDensity: VisualDensity.compact,
                    onPressed: index == total - 1 ? null : onMoveDown,
                    icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  ),
                ],
              ),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    tooltip: 'Edit',
                    visualDensity: VisualDensity.compact,
                    onPressed: onEdit,
                    icon: const Icon(Icons.edit_rounded),
                    color: SubTenantColors.blue,
                  ),
                  IconButton(
                    tooltip: 'Delete',
                    visualDensity: VisualDensity.compact,
                    onPressed: onDelete,
                    icon: const Icon(Icons.delete_outline_rounded),
                    color: const Color(0xFFDC2626),
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ItineraryItemSheet extends StatefulWidget {
  const _ItineraryItemSheet({
    required this.service,
    required this.profile,
    required this.packageId,
    required this.day,
    required this.spots,
    required this.item,
  });

  final SubTenantService service;
  final SubTenantProfile profile;
  final dynamic packageId;
  final PackageItineraryDay day;
  final List<SubTenantSpot> spots;
  final PackageItineraryItem? item;

  @override
  State<_ItineraryItemSheet> createState() => _ItineraryItemSheetState();
}

class _ItineraryItemSheetState extends State<_ItineraryItemSheet> {
  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  late final TextEditingController _timeCtrl;
  late final TextEditingController _noteCtrl;
  dynamic _spotId;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _timeCtrl = TextEditingController(text: widget.item?.timeLabel ?? '');
    _noteCtrl = TextEditingController(text: widget.item?.note ?? '');
    _spotId = widget.item?.spotId ?? widget.spots.first.id;
  }

  @override
  void dispose() {
    _timeCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);

    try {
      await widget.service.saveItineraryItem(
        profile: widget.profile,
        packageId: widget.packageId,
        dayId: widget.day.id,
        itemId: widget.item?.id,
        spotId: _spotId,
        timeLabel: _timeCtrl.text.trim(),
        note: _noteCtrl.text.trim(),
        sortOrder: widget.item?.sortOrder ?? widget.day.items.length,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      showSubTenantSnack(context, 'Failed to save itinerary item: $e');
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
                widget.item == null ? 'Add Itinerary Item' : 'Edit Stop',
                style: const TextStyle(
                  color: SubTenantColors.text,
                  fontSize: 19,
                  fontWeight: FontWeight.w900,
                ),
              ),
              const SizedBox(height: 14),
              DropdownButtonFormField<dynamic>(
                initialValue: _spotId,
                decoration: InputDecoration(
                  labelText: 'Tourist Spot',
                  filled: true,
                  fillColor: Colors.white,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(16),
                    borderSide: const BorderSide(color: SubTenantColors.line),
                  ),
                ),
                items: widget.spots
                    .map(
                      (spot) => DropdownMenuItem<dynamic>(
                        value: spot.id,
                        child: Text(
                          spot.title,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: (value) => setState(() => _spotId = value),
              ),
              const SizedBox(height: 14),
              SubTenantTextField(
                controller: _timeCtrl,
                label: 'Time Label',
                hint: '09:00 AM',
              ),
              const SizedBox(height: 14),
              SubTenantTextField(
                controller: _noteCtrl,
                label: 'Note',
                maxLines: 3,
              ),
              const SizedBox(height: 18),
              SubTenantGradientButton(
                label: 'Save Stop',
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

class _ItineraryLoad {
  const _ItineraryLoad({
    required this.profile,
    required this.package,
    required this.days,
    required this.spots,
  });

  final SubTenantProfile profile;
  final SubTenantPackage package;
  final List<PackageItineraryDay> days;
  final List<SubTenantSpot> spots;
}
