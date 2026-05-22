import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class SavedPlacesScreen extends StatefulWidget {
  const SavedPlacesScreen({super.key});

  @override
  State<SavedPlacesScreen> createState() => _SavedPlacesScreenState();
}

class _SavedPlacesScreenState extends State<SavedPlacesScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;
  final TextEditingController _searchCtrl = TextEditingController();

  List<_SavedPlaceRecord> _places = const [];
  SavedPlacesFilter _filter = SavedPlacesFilter.all;
  bool _loading = true;
  bool _saving = false;
  RealtimeChannel? _realtimeChannel;

  User? get _user => _supabase.auth.currentUser;

  @override
  void initState() {
    super.initState();
    _loadData();
    _subscribeToRealtime();
  }

  @override
  void dispose() {
    _realtimeChannel?.unsubscribe();
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    final userId = _user?.id;
    if (userId == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _places = const [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() => _loading = true);
    }

    try {
      final rows = await _supabase
          .from('saved_places')
          .select()
          .eq('user_id', userId)
          .order('updated_at', ascending: false);

      if (!mounted) return;
      setState(() {
        _places = (rows as List<dynamic>)
            .map(
              (row) => _SavedPlaceRecord.fromMap(
                Map<String, dynamic>.from(row as Map),
              ),
            )
            .toList();
        _loading = false;
      });
    } catch (error, stackTrace) {
      debugPrint('SavedPlacesScreen _loadData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      if (!mounted) return;
      setState(() => _loading = false);
      _showError('Unable to load saved places.');
    }
  }

  void _subscribeToRealtime() {
    final userId = _user?.id;
    if (userId == null) return;

    _realtimeChannel?.unsubscribe();
    _realtimeChannel = _supabase
        .channel('saved_places_$userId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'saved_places',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'user_id',
            value: userId,
          ),
          callback: (_) => _loadData(),
        )
        .subscribe();
  }

  Future<void> _saveData({
    dynamic placeId,
    required _SavedPlaceDraft draft,
  }) async {
    final userId = _user?.id;
    if (userId == null || _saving) {
      if (userId == null) {
        _showError('No active session found. Please log in again.');
      }
      return;
    }

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      final payload = <String, dynamic>{
        'user_id': userId,
        'label': draft.label.trim(),
        'address': draft.address.trim(),
        'latitude': _tryParseDouble(draft.latitude),
        'longitude': _tryParseDouble(draft.longitude),
        'kind': draft.kind.trim().isEmpty ? null : draft.kind.trim(),
        'tag': draft.tag.trim().isEmpty ? null : draft.tag.trim(),
        'place_id': draft.placeId.trim().isEmpty ? null : draft.placeId.trim(),
        'place_name': draft.placeName.trim().isEmpty
            ? null
            : draft.placeName.trim(),
        'place_address': draft.placeAddress.trim().isEmpty
            ? null
            : draft.placeAddress.trim(),
        'place_category': draft.placeCategory.trim().isEmpty
            ? null
            : draft.placeCategory.trim(),
        'image_url': draft.imageUrl.trim().isEmpty
            ? null
            : draft.imageUrl.trim(),
        'updated_at': DateTime.now().toIso8601String(),
      };

      if (placeId == null) {
        await _supabase.from('saved_places').insert(payload);
        _showSuccess('Saved place added.');
      } else {
        await _supabase
            .from('saved_places')
            .update(payload)
            .eq('id', placeId)
            .eq('user_id', userId);
        _showSuccess('Saved place updated.');
      }

      await _loadData();
    } catch (error, stackTrace) {
      debugPrint('SavedPlacesScreen _saveData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showError('Unable to save this place.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  Future<void> _deleteData(_SavedPlaceRecord place) async {
    final userId = _user?.id;
    if (userId == null) {
      _showError('No active session found. Please log in again.');
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove saved place?'),
        content: Text('Delete ${place.label} from your saved places?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFFDC2626),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    if (mounted) {
      setState(() => _saving = true);
    }

    try {
      await _supabase
          .from('saved_places')
          .delete()
          .eq('id', place.id)
          .eq('user_id', userId);
      _showSuccess('Saved place removed.');
      await _loadData();
    } catch (error, stackTrace) {
      debugPrint('SavedPlacesScreen _deleteData error: $error');
      debugPrintStack(stackTrace: stackTrace);
      _showError('Unable to remove this place.');
    } finally {
      if (mounted) {
        setState(() => _saving = false);
      }
    }
  }

  void _showSuccess(String message) => _showSnack(message, isError: false);

  void _showError(String message) => _showSnack(message, isError: true);

  void _showSnack(String message, {required bool isError}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          behavior: SnackBarBehavior.floating,
          backgroundColor: isError
              ? const Color(0xFFDC2626)
              : const Color(0xFF16A34A),
        ),
      );
  }

  Future<void> _openEditor({_SavedPlaceRecord? place}) async {
    final draft = await showModalBottomSheet<_SavedPlaceDraft>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _PlaceEditorSheet(existing: place),
    );

    if (draft == null) return;
    await _saveData(placeId: place?.id, draft: draft);
  }

  double? _tryParseDouble(String value) {
    final trimmed = value.trim();
    if (trimmed.isEmpty) return null;
    return double.tryParse(trimmed);
  }

  void _selectPlace(_SavedPlaceRecord place) {
    _showSuccess('Selected: ${place.label}');
  }

  void _showActions(_SavedPlaceRecord place) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (_) => _ActionSheet(
        title: place.label,
        subtitle: place.displayAddress,
        actions: [
          _SheetAction(
            icon: Icons.edit_rounded,
            label: 'Edit',
            onTap: () {
              Navigator.pop(context);
              _openEditor(place: place);
            },
          ),
          _SheetAction(
            icon: Icons.delete_outline_rounded,
            label: 'Remove',
            isDanger: true,
            onTap: () {
              Navigator.pop(context);
              _deleteData(place);
            },
          ),
        ],
      ),
    );
  }

  List<_SavedPlaceRecord> get _filtered {
    final query = _searchCtrl.text.trim().toLowerCase();

    bool matchesSearch(_SavedPlaceRecord place) {
      if (query.isEmpty) return true;
      return place.label.toLowerCase().contains(query) ||
          place.displayAddress.toLowerCase().contains(query) ||
          place.tag.toLowerCase().contains(query) ||
          place.kind.toLowerCase().contains(query);
    }

    bool matchesFilter(_SavedPlaceRecord place) {
      switch (_filter) {
        case SavedPlacesFilter.all:
          return true;
        case SavedPlacesFilter.pinned:
          return place.isPinned;
        case SavedPlacesFilter.tour:
          return place.tag.toLowerCase() == 'tour' ||
              place.kind.toLowerCase() == 'tour';
        case SavedPlacesFilter.spot:
          return !place.isPinned &&
              place.tag.toLowerCase() != 'tour' &&
              place.kind.toLowerCase() != 'tour';
      }
    }

    final items = _places
        .where((place) => matchesSearch(place) && matchesFilter(place))
        .toList();

    items.sort((a, b) {
      final aPinned = a.isPinned ? 0 : 1;
      final bPinned = b.isPinned ? 0 : 1;
      if (aPinned != bPinned) return aPinned.compareTo(bPinned);
      return a.label.toLowerCase().compareTo(b.label.toLowerCase());
    });
    return items;
  }

  _SavedPlaceRecord? get _home {
    for (final place in _places) {
      if (place.isHome) return place;
    }
    return null;
  }

  _SavedPlaceRecord? get _work {
    for (final place in _places) {
      if (place.isWork) return place;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    const bg = Color(0xFFF5F7FB);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);
    const textLight = Color(0xFF94A3B8);
    const line = Color(0xFFE7EEF7);

    final items = _filtered;

    return Scaffold(
      backgroundColor: bg,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _saving ? null : () => _openEditor(),
        backgroundColor: const Color(0xFF2A86FF),
        foregroundColor: Colors.white,
        icon: _saving
            ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Icon(Icons.add_rounded),
        label: const Text(
          'Add Place',
          style: TextStyle(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  _TopCircleButton(
                    icon: Icons.arrow_back_rounded,
                    onTap: () => Navigator.pop(context),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Text(
                      'Saved Places',
                      style: TextStyle(
                        fontSize: 20.5,
                        fontWeight: FontWeight.w900,
                        color: textDark,
                        letterSpacing: -0.3,
                      ),
                    ),
                  ),
                  InkWell(
                    onTap: () {
                      showModalBottomSheet<void>(
                        context: context,
                        backgroundColor: Colors.transparent,
                        builder: (_) => const _InfoSheet(
                          title: 'Tips',
                          bullets: [
                            'Save places you visit often for quick access.',
                            'Mark home and work using the kind field.',
                            'All saved places sync with Supabase in realtime.',
                          ],
                        ),
                      );
                    },
                    borderRadius: BorderRadius.circular(999),
                    child: Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.info_outline_rounded,
                        color: textMid,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: RefreshIndicator(
                color: const Color(0xFF2A86FF),
                onRefresh: _loadData,
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(16, 10, 16, 18),
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: line),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.04),
                            blurRadius: 18,
                            offset: const Offset(0, 12),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.search_rounded, color: textLight),
                          const SizedBox(width: 8),
                          Expanded(
                            child: TextField(
                              controller: _searchCtrl,
                              onChanged: (_) => setState(() {}),
                              decoration: const InputDecoration(
                                hintText: 'Search saved places...',
                                border: InputBorder.none,
                                isDense: true,
                              ),
                              style: const TextStyle(
                                fontWeight: FontWeight.w900,
                                color: textDark,
                              ),
                            ),
                          ),
                          if (_searchCtrl.text.isNotEmpty)
                            InkWell(
                              onTap: () {
                                _searchCtrl.clear();
                                setState(() {});
                              },
                              borderRadius: BorderRadius.circular(999),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.close_rounded,
                                  color: textMid,
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(
                        children: [
                          _FilterChip(
                            label: 'All',
                            selected: _filter == SavedPlacesFilter.all,
                            onTap: () =>
                                setState(() => _filter = SavedPlacesFilter.all),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Pinned',
                            selected: _filter == SavedPlacesFilter.pinned,
                            onTap: () => setState(
                              () => _filter = SavedPlacesFilter.pinned,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Tour',
                            selected: _filter == SavedPlacesFilter.tour,
                            onTap: () => setState(
                              () => _filter = SavedPlacesFilter.tour,
                            ),
                          ),
                          const SizedBox(width: 8),
                          _FilterChip(
                            label: 'Spot',
                            selected: _filter == SavedPlacesFilter.spot,
                            onTap: () => setState(
                              () => _filter = SavedPlacesFilter.spot,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    if ((_home != null || _work != null) && !_loading) ...[
                      const _SectionHeader(title: 'Pinned'),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (_home != null)
                            Expanded(
                              child: _PinnedTile(
                                icon: Icons.home_rounded,
                                title: 'Home',
                                subtitle: _home!.displayAddress,
                                onTap: () => _selectPlace(_home!),
                                onMore: () => _showActions(_home!),
                              ),
                            ),
                          if (_home != null && _work != null)
                            const SizedBox(width: 10),
                          if (_work != null)
                            Expanded(
                              child: _PinnedTile(
                                icon: Icons.work_rounded,
                                title: 'Work',
                                subtitle: _work!.displayAddress,
                                onTap: () => _selectPlace(_work!),
                                onMore: () => _showActions(_work!),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ],
                    _SectionHeader(
                      title: 'Saved',
                      trailing: Text(
                        '${items.length}',
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: textMid,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (_loading)
                      const Center(
                        child: Padding(
                          padding: EdgeInsets.all(28),
                          child: CircularProgressIndicator(
                            color: Color(0xFF2A86FF),
                          ),
                        ),
                      )
                    else if (items.isEmpty)
                      const _EmptyState()
                    else
                      ...items.map(
                        (place) => Padding(
                          padding: const EdgeInsets.only(bottom: 12),
                          child: _Card(
                            child: _PlaceRow(
                              place: place,
                              onTap: () => _selectPlace(place),
                              onMore: () => _showActions(place),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 80),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum SavedPlacesFilter { all, pinned, tour, spot }

class _SavedPlaceRecord {
  const _SavedPlaceRecord({
    required this.id,
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.kind,
    required this.tag,
    required this.placeId,
    required this.placeName,
    required this.placeAddress,
    required this.placeCategory,
    required this.imageUrl,
  });

  factory _SavedPlaceRecord.fromMap(Map<String, dynamic> map) {
    return _SavedPlaceRecord(
      id: map['id'],
      label: (map['label'] ?? '').toString(),
      address: (map['address'] ?? '').toString(),
      latitude: _toDouble(map['latitude']),
      longitude: _toDouble(map['longitude']),
      kind: (map['kind'] ?? '').toString(),
      tag: (map['tag'] ?? '').toString(),
      placeId: (map['place_id'] ?? '').toString(),
      placeName: (map['place_name'] ?? '').toString(),
      placeAddress: (map['place_address'] ?? '').toString(),
      placeCategory: (map['place_category'] ?? '').toString(),
      imageUrl: (map['image_url'] ?? '').toString(),
    );
  }

  final dynamic id;
  final String label;
  final String address;
  final double? latitude;
  final double? longitude;
  final String kind;
  final String tag;
  final String placeId;
  final String placeName;
  final String placeAddress;
  final String placeCategory;
  final String imageUrl;

  bool get isHome {
    return kind.toLowerCase() == 'home' ||
        tag.toLowerCase() == 'home' ||
        label.toLowerCase() == 'home';
  }

  bool get isWork {
    return kind.toLowerCase() == 'work' ||
        tag.toLowerCase() == 'work' ||
        label.toLowerCase() == 'work';
  }

  bool get isPinned => isHome || isWork;

  String get displayAddress {
    final values = [
      address,
      placeAddress,
    ].where((value) => value.trim().isNotEmpty).toSet().toList();
    return values.isEmpty ? 'No address provided' : values.join(' • ');
  }

  IconData get icon {
    final normalizedTag = tag.toLowerCase();
    final normalizedKind = kind.toLowerCase();
    final normalizedCategory = placeCategory.toLowerCase();

    if (isHome) return Icons.home_rounded;
    if (isWork) return Icons.work_rounded;
    if (normalizedTag == 'tour' || normalizedKind == 'tour') {
      return Icons.tour_rounded;
    }
    if (normalizedTag == 'pickup' || normalizedKind == 'pickup') {
      return Icons.my_location_rounded;
    }
    if (normalizedCategory.contains('restaurant') ||
        normalizedCategory.contains('food')) {
      return Icons.restaurant_rounded;
    }
    if (normalizedCategory.contains('museum')) return Icons.museum_rounded;
    if (normalizedCategory.contains('park') ||
        normalizedCategory.contains('nature')) {
      return Icons.park_rounded;
    }
    return Icons.place_rounded;
  }

  static double? _toDouble(dynamic value) {
    if (value == null) return null;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString());
  }
}

class _SavedPlaceDraft {
  const _SavedPlaceDraft({
    required this.label,
    required this.address,
    required this.latitude,
    required this.longitude,
    required this.kind,
    required this.tag,
    required this.placeId,
    required this.placeName,
    required this.placeAddress,
    required this.placeCategory,
    required this.imageUrl,
  });

  final String label;
  final String address;
  final String latitude;
  final String longitude;
  final String kind;
  final String tag;
  final String placeId;
  final String placeName;
  final String placeAddress;
  final String placeCategory;
  final String imageUrl;
}

class _Card extends StatelessWidget {
  const _Card({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 22,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _TopCircleButton extends StatelessWidget {
  const _TopCircleButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 18,
              offset: const Offset(0, 10),
            ),
          ],
        ),
        child: Icon(icon, color: const Color(0xFF0F172A)),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text(
          title,
          style: const TextStyle(
            fontSize: 16.5,
            fontWeight: FontWeight.w900,
            color: Color(0xFF0F172A),
          ),
        ),
        const Spacer(),
        if (trailing case final trailingWidget?) trailingWidget,
      ],
    );
  }
}

class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFEAF2FF) : Colors.white,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(
            color: selected ? const Color(0xFFBBD7FF) : const Color(0xFFE7EEF7),
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontWeight: FontWeight.w900,
            color: selected ? blue : textDark,
            fontSize: 12.5,
          ),
        ),
      ),
    );
  }
}

class _PinnedTile extends StatelessWidget {
  const _PinnedTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.onMore,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(22),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(22),
          border: Border.all(color: const Color(0xFFE7EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 18,
              offset: const Offset(0, 12),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Icon(icon, color: blue),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.w900,
                      color: textDark,
                      fontSize: 15.5,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      color: textMid,
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
            ),
            InkWell(
              onTap: onMore,
              borderRadius: BorderRadius.circular(999),
              child: const Padding(
                padding: EdgeInsets.all(6),
                child: Icon(Icons.more_horiz_rounded, color: textMid),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PlaceRow extends StatelessWidget {
  const _PlaceRow({
    required this.place,
    required this.onTap,
    required this.onMore,
  });

  final _SavedPlaceRecord place;
  final VoidCallback onTap;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    const blue = Color(0xFF2A86FF);
    const textDark = Color(0xFF0F172A);
    const textMid = Color(0xFF64748B);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(18),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFEAF2FF),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Icon(place.icon, color: blue),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        place.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontWeight: FontWeight.w900,
                          color: textDark,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    if (place.tag.trim().isNotEmpty) ...[
                      const SizedBox(width: 8),
                      _TagChip(text: place.tag),
                    ],
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  place.displayAddress,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontWeight: FontWeight.w800,
                    color: textMid,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          InkWell(
            onTap: onMore,
            borderRadius: BorderRadius.circular(999),
            child: const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.more_horiz_rounded, color: textMid),
            ),
          ),
        ],
      ),
    );
  }
}

class _TagChip extends StatelessWidget {
  const _TagChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(
        text.toUpperCase(),
        style: const TextStyle(
          fontWeight: FontWeight.w900,
          color: Color(0xFF2A86FF),
          fontSize: 12,
          letterSpacing: 0.35,
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFE7EEF7)),
      ),
      child: const Text(
        'No saved places yet. Add a place to keep your favorite destinations in sync.',
        style: TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF64748B)),
      ),
    );
  }
}

class _ActionSheet extends StatelessWidget {
  const _ActionSheet({
    required this.title,
    required this.subtitle,
    required this.actions,
  });

  final String title;
  final String subtitle;
  final List<_SheetAction> actions;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        color: Color(0xFF0F172A),
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                onPressed: () => Navigator.pop(context),
                icon: const Icon(Icons.close_rounded),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...actions.map(
            (action) => ListTile(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              leading: Icon(
                action.icon,
                color: action.isDanger
                    ? const Color(0xFFDC2626)
                    : const Color(0xFF2A86FF),
              ),
              title: Text(
                action.label,
                style: TextStyle(
                  fontWeight: FontWeight.w900,
                  color: action.isDanger
                      ? const Color(0xFFDC2626)
                      : const Color(0xFF0F172A),
                ),
              ),
              onTap: action.onTap,
            ),
          ),
        ],
      ),
    );
  }
}

class _SheetAction {
  const _SheetAction({
    required this.icon,
    required this.label,
    required this.onTap,
    this.isDanger = false,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isDanger;
}

class _InfoSheet extends StatelessWidget {
  const _InfoSheet({required this.title, required this.bullets});

  final String title;
  final List<String> bullets;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 44,
            height: 5,
            decoration: BoxDecoration(
              color: const Color(0xFFE2E8F0),
              borderRadius: BorderRadius.circular(999),
            ),
          ),
          const SizedBox(height: 12),
          Text(
            title,
            style: const TextStyle(
              fontWeight: FontWeight.w900,
              color: Color(0xFF0F172A),
              fontSize: 18,
            ),
          ),
          const SizedBox(height: 12),
          ...bullets.map(
            (bullet) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    '• ',
                    style: TextStyle(
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF64748B),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      bullet,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _PlaceEditorSheet extends StatefulWidget {
  const _PlaceEditorSheet({this.existing});

  final _SavedPlaceRecord? existing;

  @override
  State<_PlaceEditorSheet> createState() => _PlaceEditorSheetState();
}

class _PlaceEditorSheetState extends State<_PlaceEditorSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _labelCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _latitudeCtrl;
  late final TextEditingController _longitudeCtrl;
  late final TextEditingController _kindCtrl;
  late final TextEditingController _tagCtrl;
  late final TextEditingController _placeIdCtrl;
  late final TextEditingController _placeNameCtrl;
  late final TextEditingController _placeAddressCtrl;
  late final TextEditingController _placeCategoryCtrl;
  late final TextEditingController _imageUrlCtrl;

  @override
  void initState() {
    super.initState();
    final place = widget.existing;
    _labelCtrl = TextEditingController(text: place?.label ?? '');
    _addressCtrl = TextEditingController(text: place?.address ?? '');
    _latitudeCtrl = TextEditingController(
      text: place?.latitude?.toString() ?? '',
    );
    _longitudeCtrl = TextEditingController(
      text: place?.longitude?.toString() ?? '',
    );
    _kindCtrl = TextEditingController(text: place?.kind ?? '');
    _tagCtrl = TextEditingController(text: place?.tag ?? '');
    _placeIdCtrl = TextEditingController(text: place?.placeId ?? '');
    _placeNameCtrl = TextEditingController(text: place?.placeName ?? '');
    _placeAddressCtrl = TextEditingController(text: place?.placeAddress ?? '');
    _placeCategoryCtrl = TextEditingController(
      text: place?.placeCategory ?? '',
    );
    _imageUrlCtrl = TextEditingController(text: place?.imageUrl ?? '');
  }

  @override
  void dispose() {
    _labelCtrl.dispose();
    _addressCtrl.dispose();
    _latitudeCtrl.dispose();
    _longitudeCtrl.dispose();
    _kindCtrl.dispose();
    _tagCtrl.dispose();
    _placeIdCtrl.dispose();
    _placeNameCtrl.dispose();
    _placeAddressCtrl.dispose();
    _placeCategoryCtrl.dispose();
    _imageUrlCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 5,
                decoration: BoxDecoration(
                  color: const Color(0xFFE2E8F0),
                  borderRadius: BorderRadius.circular(999),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.existing == null
                          ? 'Add Saved Place'
                          : 'Edit Saved Place',
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ),
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close_rounded),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: MediaQuery.of(context).size.height * 0.65,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    children: [
                      _SheetTextField(
                        controller: _labelCtrl,
                        label: 'Label',
                        validator: _requiredValidator,
                      ),
                      const SizedBox(height: 10),
                      _SheetTextField(
                        controller: _addressCtrl,
                        label: 'Address',
                        validator: _requiredValidator,
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _SheetTextField(
                              controller: _latitudeCtrl,
                              label: 'Latitude',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SheetTextField(
                              controller: _longitudeCtrl,
                              label: 'Longitude',
                              keyboardType:
                                  const TextInputType.numberWithOptions(
                                    decimal: true,
                                    signed: true,
                                  ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(
                            child: _SheetTextField(
                              controller: _kindCtrl,
                              label: 'Kind',
                              hintText: 'home, work, tour, pickup',
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: _SheetTextField(
                              controller: _tagCtrl,
                              label: 'Tag',
                              hintText: 'tour, food, museum',
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _SheetTextField(
                        controller: _placeIdCtrl,
                        label: 'Place ID',
                      ),
                      const SizedBox(height: 10),
                      _SheetTextField(
                        controller: _placeNameCtrl,
                        label: 'Place Name',
                      ),
                      const SizedBox(height: 10),
                      _SheetTextField(
                        controller: _placeAddressCtrl,
                        label: 'Place Address',
                        maxLines: 2,
                      ),
                      const SizedBox(height: 10),
                      _SheetTextField(
                        controller: _placeCategoryCtrl,
                        label: 'Place Category',
                      ),
                      const SizedBox(height: 10),
                      _SheetTextField(
                        controller: _imageUrlCtrl,
                        label: 'Image URL',
                        keyboardType: TextInputType.url,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                height: 52,
                child: ElevatedButton(
                  onPressed: () {
                    if (!_formKey.currentState!.validate()) return;
                    Navigator.pop(
                      context,
                      _SavedPlaceDraft(
                        label: _labelCtrl.text,
                        address: _addressCtrl.text,
                        latitude: _latitudeCtrl.text,
                        longitude: _longitudeCtrl.text,
                        kind: _kindCtrl.text,
                        tag: _tagCtrl.text,
                        placeId: _placeIdCtrl.text,
                        placeName: _placeNameCtrl.text,
                        placeAddress: _placeAddressCtrl.text,
                        placeCategory: _placeCategoryCtrl.text,
                        imageUrl: _imageUrlCtrl.text,
                      ),
                    );
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF2A86FF),
                    foregroundColor: Colors.white,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(18),
                    ),
                  ),
                  child: Text(
                    widget.existing == null ? 'Save Place' : 'Save Changes',
                    style: const TextStyle(fontWeight: FontWeight.w900),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _requiredValidator(String? value) {
    if (value == null || value.trim().isEmpty) {
      return 'This field is required.';
    }
    return null;
  }
}

class _SheetTextField extends StatelessWidget {
  const _SheetTextField({
    required this.controller,
    required this.label,
    this.keyboardType,
    this.validator,
    this.maxLines = 1,
    this.hintText,
  });

  final TextEditingController controller;
  final String label;
  final TextInputType? keyboardType;
  final String? Function(String?)? validator;
  final int maxLines;
  final String? hintText;

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      validator: validator,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hintText,
        filled: true,
        fillColor: const Color(0xFFF8FAFC),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(18),
          borderSide: const BorderSide(color: Color(0xFFE7EEF7)),
        ),
      ),
    );
  }
}
