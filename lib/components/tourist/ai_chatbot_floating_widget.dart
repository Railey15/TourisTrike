import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:touristrike/core/places/city_spot_suggestions.dart';
import 'package:touristrike/core/services/chatbot_models.dart';
import 'package:touristrike/core/services/gemini_service.dart';
import 'package:touristrike/screens/tourist/package_details_screen.dart';
import 'package:touristrike/screens/tourist/spot_details_screen.dart';

const _kChatHistoryKey = 'ai_chatbot_history_v1';

Future<void> clearAiChatbotHistory() async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kChatHistoryKey);
  } catch (_) {}
}

// ── System prompt ──────────────────────────────────────────────────────────────
const _kSystemPrompt =
    'You are TourisTrike AI Assistant. You help tourists explore municipalities, '
    'tourist destinations, packages, tricycle transportation, routes, and travel '
    'planning within Bulacan, Philippines. '
    'Answer questions about tourism, tourist spots, travel packages, '
    'cafes, food places, attractions, historical sites, nature spots, '
    'routes, and transportation within TourisTrike. '
    'Give short, helpful, and friendly answers. '
    'Only decline if the topic is completely unrelated to tourism or travel.';

const _kOffTopicReply =
    'I can only assist with tourism, travel packages, tourist spots, routes, '
    'and transportation services within TourisTrike.';

const _kTourismKeywords = [
  'tour', 'tourist', 'spot', 'package', 'travel', 'trip', 'route',
  'tricycle', 'trike', 'bulacan', 'municipality', 'destination', 'visit',
  'place', 'hotel', 'transport', 'itinerary', 'recommend', 'activity',
  'booking', 'schedule', 'price', 'cost', 'driver', 'service', 'map',
  'location', 'direction', 'nature', 'historical', 'resort', 'food',
  'park', 'church', 'museum', 'festival', 'heritage', 'beach', 'falls',
  'mountain', 'river', 'lake', 'hi', 'hello', 'hey', 'help', 'what',
  'how', 'where', 'who', 'which', 'when', 'can', 'tell', 'show', 'give',
  'suggest', 'best', 'popular', 'famous', 'nearby', 'top',
  // Spot-intent keywords
  'cafe', 'café', 'coffee', 'restaurant', 'dining', 'eat', 'food',
  'attraction', 'landmark', 'historical', 'history', 'heritage',
  'nature', 'eco', 'mountain', 'river', 'falls', 'lake', 'forest',
  'religious', 'church', 'cathedral', 'shrine', 'temple',
  'museum', 'park', 'garden', 'plaza', 'resort', 'pool',
  // Package-intent keywords
  'hop', 'hopping', 'adventure', 'family', 'cultural', 'culture',
  'want', 'looking', 'find', 'interested', 'explore', 'enjoy',
  'experience', 'trekking', 'biking', 'swimming',
];

bool _isOnTopic(String msg) {
  final lower = msg.toLowerCase();
  return _kTourismKeywords.any((kw) => lower.contains(kw));
}

// ── Data model ─────────────────────────────────────────────────────────────────
class _ChatMessage {
  const _ChatMessage({
    required this.text,
    required this.isUser,
    this.isError = false,
    // UI-only messages (greetings, off-topic replies) are NEVER sent to Gemini.
    this.isUiOnly = false,
    this.spots = const [],
    this.packages = const [],
  });

  final String text;
  final bool isUser;
  final bool isError;
  final bool isUiOnly;
  final List<ChatSpotSuggestion> spots;
  final List<ChatPackageSuggestion> packages;
}

// ── Wrapper ────────────────────────────────────────────────────────────────────
class TouristAiChatbotWrapper extends StatefulWidget {
  const TouristAiChatbotWrapper({super.key, required this.child});

  final Widget child;

  @override
  State<TouristAiChatbotWrapper> createState() =>
      _TouristAiChatbotWrapperState();
}

class _TouristAiChatbotWrapperState extends State<TouristAiChatbotWrapper> {
  static const double _kFabSize = 56.0;
  static const double _kNavBarH = 90.0;

  double _right = 18.0;
  double _bottom = _kNavBarH;
  bool _positionInitialized = false;

  void _openChat() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      enableDrag: true,
      builder: (_) => _AiChatSheet(
        onOpenPackage: _navigateToPackage,
        onOpenSpot: _navigateToSpot,
      ),
    );
  }

  void _navigateToPackage(dynamic packageId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PackageDetailsScreen(packageId: packageId),
      ),
    );
  }

  void _navigateToSpot(ChatSpotSuggestion spot) {
    final spotData = TouristSpotDetailsData(
      id: spot.googlePlaceId.isNotEmpty ? spot.googlePlaceId : spot.id,
      title: spot.name,
      address: spot.address,
      distance: 'Nearby',
      distanceKm: 0,
      tag: spot.category,
      rating: spot.rating,
      userRatingsTotal: 0,
      imageUrl: spot.imageUrl,
      imageUrls: spot.imageUrl.isNotEmpty ? [spot.imageUrl] : const [],
      latitude: spot.latitude,
      longitude: spot.longitude,
      openNow: null,
      municipality: spot.municipality,
      googlePlaceId: spot.googlePlaceId,
    );

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TouristSpotDetailsScreen(
          spot: spotData,
          googleMapsApiKey: CitySpotSuggestionService.defaultGoogleMapsApiKey,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);

    if (!_positionInitialized) {
      _positionInitialized = true;
      _bottom = _kNavBarH + mq.padding.bottom;
    }

    return Stack(
      children: [
        widget.child,
        Positioned(
          right: _right.clamp(0.0, mq.size.width - _kFabSize),
          bottom: _bottom.clamp(
            mq.padding.bottom + 80.0,
            mq.size.height - _kFabSize - mq.padding.top - 20.0,
          ),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _openChat,
            onPanUpdate: (details) {
              setState(() {
                _right -= details.delta.dx;
                _bottom -= details.delta.dy;
              });
            },
            child: const _ChatFab(),
          ),
        ),
      ],
    );
  }
}

// ── Floating button ────────────────────────────────────────────────────────────
class _ChatFab extends StatelessWidget {
  const _ChatFab();

  static const _iconUrl =
      'https://mvtqhsrdgtwdeootgjci.supabase.co/storage/v1/object/public/public-assets/chatbot.png';

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 56,
      height: 56,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
        ),
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: const Color(0xFF2A86FF).withValues(alpha: 0.42),
            blurRadius: 20,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(9),
        child: Image.network(
          _iconUrl,
          fit: BoxFit.contain,
          errorBuilder: (_, __, ___) => const Icon(
            Icons.assistant_rounded,
            color: Colors.white,
            size: 26,
          ),
        ),
      ),
    );
  }
}

// ── Chat bottom sheet ──────────────────────────────────────────────────────────
class _AiChatSheet extends StatefulWidget {
  const _AiChatSheet({
    required this.onOpenPackage,
    required this.onOpenSpot,
  });

  final void Function(dynamic packageId) onOpenPackage;
  final void Function(ChatSpotSuggestion spot) onOpenSpot;

  @override
  State<_AiChatSheet> createState() => _AiChatSheetState();
}

class _AiChatSheetState extends State<_AiChatSheet> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _thinking = false;

  static const _kGreeting = _ChatMessage(
    text: 'Hi! I\'m your TourisTrike AI Assistant \u{1F44B}\n\n'
        'Ask me about tourist spots, travel packages, tricycle routes, '
        'cafes, food places, or anything about exploring Bulacan!',
    isUser: false,
    isUiOnly: true,
  );

  final List<_ChatMessage> _messages = [_kGreeting];

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getStringList(_kChatHistoryKey);
      if (raw == null || raw.isEmpty) return;
      final loaded = raw
          .map((s) {
            try {
              final m = jsonDecode(s) as Map<String, dynamic>;
              return _ChatMessage(
                text: m['text'] as String? ?? '',
                isUser: m['isUser'] as bool? ?? false,
                isError: false,
                isUiOnly: m['isUiOnly'] as bool? ?? false,
              );
            } catch (_) {
              return null;
            }
          })
          .whereType<_ChatMessage>()
          .toList();
      if (loaded.isEmpty) return;
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..add(_kGreeting)
          ..addAll(loaded);
      });
      _scrollToBottom();
    } catch (_) {}
  }

  Future<void> _saveHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Skip the greeting (first message, isUiOnly), save the rest
      final toSave = _messages
          .skip(1)
          .where((m) => !m.isError)
          .map((m) => jsonEncode({
                'text': m.text,
                'isUser': m.isUser,
                'isUiOnly': m.isUiOnly,
              }))
          .toList();
      await prefs.setStringList(_kChatHistoryKey, toSave);
    } catch (_) {}
  }


  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 280),
          curve: Curves.easeOut,
        );
      }
    });
  }

  // History includes only the reply text — not the spot/package data.
  List<GeminiTurn> _buildHistory() {
    final turns = <GeminiTurn>[];

    for (final msg in _messages) {
      if (msg.isUiOnly || msg.isError) continue;
      turns.add(GeminiTurn(
        role: msg.isUser ? 'user' : 'model',
        text: msg.text,
      ));
    }

    while (turns.isNotEmpty && turns.first.role == 'model') {
      turns.removeAt(0);
    }

    if (turns.length > 10) return turns.sublist(turns.length - 10);
    return turns;
  }

  Future<void> _send() async {
    final text = _textCtrl.text.trim();
    if (text.isEmpty || _thinking) return;
    _textCtrl.clear();

    setState(() {
      _messages.add(_ChatMessage(text: text, isUser: true));
      _thinking = true;
    });
    _scrollToBottom();

    if (!_isOnTopic(text)) {
      await Future.delayed(const Duration(milliseconds: 380));
      if (!mounted) return;
      setState(() {
        _messages.add(const _ChatMessage(
          text: _kOffTopicReply,
          isUser: false,
          isUiOnly: true,
        ));
        _thinking = false;
      });
      unawaited(_saveHistory());
      _scrollToBottom();
      return;
    }

    try {
      final history = _buildHistory();
      debugPrint('[Chat] history=${history.length} user="$text"');

      final response = await GeminiService.instance.chat(
        userMessage: text,
        history: history,
        systemPrompt: _kSystemPrompt,
      );

      debugPrint('[Chat] reply="${response.reply}" '
          'spots=${response.spots.length} '
          'packages=${response.packages.length}');

      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          text: response.reply,
          isUser: false,
          spots: response.spots,
          packages: response.packages,
        ));
        _thinking = false;
      });
      unawaited(_saveHistory());
    } catch (e) {
      debugPrint('[Chat] Error: $e');
      if (!mounted) return;
      final raw = e.toString().replaceFirst(RegExp(r'^Exception:\s*'), '');
      final String userFacing;
      if (raw.toLowerCase().contains('quota') ||
          raw.toLowerCase().contains('rate') ||
          raw.toLowerCase().contains('limit') ||
          raw.toLowerCase().contains('busy') ||
          raw.toLowerCase().contains('demand') ||
          raw.toLowerCase().contains('overload') ||
          raw.toLowerCase().contains('503') ||
          raw.toLowerCase().contains('unavailable')) {
        userFacing =
            'AI assistant is currently busy. Please try again in a moment.';
      } else if (raw.toLowerCase().contains('network') ||
          raw.toLowerCase().contains('timeout') ||
          raw.toLowerCase().contains('socket')) {
        userFacing =
            'No internet connection. Please check your network and try again.';
      } else if (raw.toLowerCase().contains('key') ||
          raw.toLowerCase().contains('permission') ||
          raw.toLowerCase().contains('unauthorized') ||
          raw.toLowerCase().contains('denied')) {
        userFacing =
            'AI service is not configured correctly. Please contact support.';
      } else {
        userFacing =
            raw.isNotEmpty ? raw : 'Something went wrong. Please try again.';
      }
      setState(() {
        _messages.add(_ChatMessage(
          text: userFacing,
          isUser: false,
          isError: true,
        ));
        _thinking = false;
      });
    }

    _scrollToBottom();
  }

  // ── Build ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final viewInsetsBottom = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;
    final sheetH = math.min(screenH * 0.82, screenH - 60.0);

    return Padding(
      padding: EdgeInsets.only(bottom: viewInsetsBottom),
      child: Material(
        color: const Color(0xFFF5F7FB),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: SizedBox(
          height: sheetH,
          child: Column(
            children: [
              _buildDragHandle(),
              _buildHeader(),
              const Divider(height: 1, color: Color(0xFFE7EEF7)),
              Expanded(child: _buildMessagesList()),
              _buildInputBar(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 4),
      child: Center(
        child: Container(
          width: 44,
          height: 5,
          decoration: BoxDecoration(
            color: const Color(0xFFD1D9E6),
            borderRadius: BorderRadius.circular(999),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 8, 10, 8),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: Image.network(
                _ChatFab._iconUrl,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const Icon(
                  Icons.assistant_rounded,
                  color: Colors.white,
                  size: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'TourisTrike AI Assistant',
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 15.5,
                    color: Color(0xFF0F172A),
                  ),
                ),
                Text(
                  'Tourism & Travel Guide · Bulacan',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF64748B),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 9,
            height: 9,
            margin: const EdgeInsets.only(right: 4),
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
          IconButton(
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.close_rounded, color: Color(0xFF64748B)),
            splashRadius: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildMessagesList() {
    return ListView.builder(
      controller: _scrollCtrl,
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 8),
      itemCount: _messages.length + (_thinking ? 1 : 0),
      itemBuilder: (_, i) {
        if (_thinking && i == _messages.length) {
          return const _TypingIndicator();
        }

        final msg = _messages[i];
        final hasCards = !msg.isUser &&
            (msg.spots.isNotEmpty || msg.packages.isNotEmpty);

        if (hasCards) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _MessageBubble(message: msg),
              // Spot cards first (spot intent)
              if (msg.spots.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...msg.spots.map(
                  (spot) => _SpotSuggestionCard(
                    suggestion: spot,
                    onTap: () => widget.onOpenSpot(spot),
                  ),
                ),
              ],
              // Package cards after (package intent)
              if (msg.packages.isNotEmpty) ...[
                const SizedBox(height: 8),
                ...msg.packages.map(
                  (pkg) => _PackageSuggestionCard(
                    suggestion: pkg,
                    onTap: () => widget.onOpenPackage(pkg.id),
                  ),
                ),
              ],
              const SizedBox(height: 4),
            ],
          );
        }

        return _MessageBubble(message: msg);
      },
    );
  }

  Widget _buildInputBar() {
    return Material(
      color: Colors.white,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Container(
                  constraints: const BoxConstraints(maxHeight: 120),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0xFFE2E8F0)),
                  ),
                  child: TextField(
                    controller: _textCtrl,
                    maxLines: 5,
                    minLines: 1,
                    textInputAction: TextInputAction.send,
                    onSubmitted: (_) => _send(),
                    enabled: !_thinking,
                    style: const TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 14,
                      color: Color(0xFF0F172A),
                    ),
                    decoration: const InputDecoration(
                      hintText: 'Ask about spots, packages, routes...',
                      hintStyle: TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w600,
                        fontSize: 13.5,
                      ),
                      border: InputBorder.none,
                      contentPadding: EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 12,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              GestureDetector(
                onTap: _thinking ? null : _send,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    gradient: _thinking
                        ? null
                        : const LinearGradient(
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                            colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
                          ),
                    color: _thinking ? const Color(0xFFE2E8F0) : null,
                    borderRadius: BorderRadius.circular(15),
                    boxShadow: _thinking
                        ? null
                        : [
                            BoxShadow(
                              color: const Color(0xFF2A86FF)
                                  .withValues(alpha: 0.30),
                              blurRadius: 12,
                              offset: const Offset(0, 6),
                            ),
                          ],
                  ),
                  child: _thinking
                      ? const Padding(
                          padding: EdgeInsets.all(13),
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Color(0xFF94A3B8),
                          ),
                        )
                      : const Icon(
                          Icons.send_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ── Tourist spot suggestion card ───────────────────────────────────────────────
class _SpotSuggestionCard extends StatelessWidget {
  const _SpotSuggestionCard({
    required this.suggestion,
    required this.onTap,
  });

  final ChatSpotSuggestion suggestion;
  final VoidCallback onTap;

  // Category → icon mapping.
  static IconData _categoryIcon(String category) {
    switch (category) {
      case 'Historical':
        return Icons.account_balance_outlined;
      case 'Nature':
        return Icons.terrain_outlined;
      case 'Food':
        return Icons.restaurant_outlined;
      case 'Religious':
        return Icons.church_outlined;
      case 'Museum':
        return Icons.museum_outlined;
      case 'Park':
        return Icons.park_outlined;
      case 'Resort':
        return Icons.pool_rounded;
      default:
        return Icons.place_outlined;
    }
  }

  // Category → colour mapping.
  static Color _categoryColor(String category) {
    switch (category) {
      case 'Historical':
        return const Color(0xFF92400E);
      case 'Nature':
        return const Color(0xFF166534);
      case 'Food':
        return const Color(0xFFB45309);
      case 'Religious':
        return const Color(0xFF6D28D9);
      case 'Museum':
        return const Color(0xFF1D4ED8);
      case 'Park':
        return const Color(0xFF15803D);
      case 'Resort':
        return const Color(0xFF0369A1);
      default:
        return const Color(0xFF2A86FF);
    }
  }

  @override
  Widget build(BuildContext context) {
    final catColor = _categoryColor(suggestion.category);
    final hasImage = suggestion.imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Thumbnail ──────────────────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
              child: SizedBox(
                width: 76,
                height: 80,
                child: hasImage
                    ? Image.network(
                        suggestion.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) =>
                            _spotPlaceholder(catColor),
                      )
                    : _spotPlaceholder(catColor),
              ),
            ),
            // ── Details ────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // Category badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: catColor.withValues(alpha: 0.10),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            _categoryIcon(suggestion.category),
                            size: 10,
                            color: catColor,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            suggestion.category,
                            style: TextStyle(
                              fontSize: 10,
                              color: catColor,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      suggestion.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: Color(0xFF2A86FF),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            suggestion.municipality,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (suggestion.rating > 0) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.star_rounded,
                            size: 12,
                            color: Color(0xFFF59E0B),
                          ),
                          const SizedBox(width: 3),
                          Text(
                            suggestion.rating.toStringAsFixed(1),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ── Chevron ────────────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFCBD5E1),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _spotPlaceholder(Color catColor) {
    return Container(
      color: catColor.withValues(alpha: 0.08),
      child: Center(
        child: Icon(
          _categoryIcon(suggestion.category),
          color: catColor.withValues(alpha: 0.5),
          size: 28,
        ),
      ),
    );
  }
}

// ── Package suggestion card ────────────────────────────────────────────────────
class _PackageSuggestionCard extends StatelessWidget {
  const _PackageSuggestionCard({
    required this.suggestion,
    required this.onTap,
  });

  final ChatPackageSuggestion suggestion;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasImage = suggestion.imageUrl.isNotEmpty;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0xFFE7EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Thumbnail ──────────────────────────────────────────────────
            ClipRRect(
              borderRadius: const BorderRadius.horizontal(
                left: Radius.circular(14),
              ),
              child: SizedBox(
                width: 76,
                height: 80,
                child: hasImage
                    ? Image.network(
                        suggestion.imageUrl,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => _packagePlaceholder(),
                      )
                    : _packagePlaceholder(),
              ),
            ),
            // ── Details ────────────────────────────────────────────────────
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 6, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // "Tour Package" badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEAF2FF),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            Icons.verified_rounded,
                            size: 10,
                            color: Color(0xFF2A86FF),
                          ),
                          SizedBox(width: 3),
                          Text(
                            'Tour Package',
                            style: TextStyle(
                              fontSize: 10,
                              color: Color(0xFF2A86FF),
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      suggestion.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontWeight: FontWeight.w900,
                        fontSize: 13.5,
                        color: Color(0xFF0F172A),
                      ),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        const Icon(
                          Icons.location_on_outlined,
                          size: 12,
                          color: Color(0xFF2A86FF),
                        ),
                        const SizedBox(width: 2),
                        Expanded(
                          child: Text(
                            suggestion.municipality,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFF64748B),
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (suggestion.description.isNotEmpty) ...[
                      const SizedBox(height: 3),
                      Text(
                        suggestion.description,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w600,
                          height: 1.35,
                        ),
                      ),
                    ],
                    if (suggestion.price.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Text(
                        suggestion.price,
                        style: const TextStyle(
                          fontSize: 12,
                          color: Color(0xFF2A86FF),
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            // ── Chevron ────────────────────────────────────────────────────
            const Padding(
              padding: EdgeInsets.only(right: 10),
              child: Icon(
                Icons.chevron_right_rounded,
                color: Color(0xFFCBD5E1),
                size: 22,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _packagePlaceholder() {
    return Container(
      color: const Color(0xFFEAF2FF),
      child: const Center(
        child: Icon(
          Icons.explore_rounded,
          color: Color(0xFF2A86FF),
          size: 28,
        ),
      ),
    );
  }
}

// ── Message bubble ─────────────────────────────────────────────────────────────
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final _ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.80,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          gradient: isUser
              ? const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
                )
              : null,
          color: isUser
              ? null
              : message.isError
                  ? const Color(0xFFFEF2F2)
                  : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isUser ? 18 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 18),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: message.isError
                      ? const Color(0xFFFECACA)
                      : const Color(0xFFE7EEF7),
                ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (!isUser) ...[
              Container(
                width: 26,
                height: 26,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: Image.network(
                    _ChatFab._iconUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const Icon(
                      Icons.assistant_rounded,
                      color: Colors.white,
                      size: 15,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                message.text,
                style: TextStyle(
                  color: isUser
                      ? Colors.white
                      : message.isError
                          ? const Color(0xFFDC2626)
                          : const Color(0xFF0F172A),
                  fontWeight: FontWeight.w600,
                  fontSize: 14,
                  height: 1.45,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Typing indicator ───────────────────────────────────────────────────────────
class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(18),
            topRight: Radius.circular(18),
            bottomRight: Radius.circular(18),
            bottomLeft: Radius.circular(4),
          ),
          border: Border.all(color: const Color(0xFFE7EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: List.generate(3, (i) {
            return AnimatedBuilder(
              animation: _ctrl,
              builder: (context, _) {
                final phase = (_ctrl.value + i / 3.0) % 1.0;
                final t = (0.5 + 0.5 * math.sin(phase * 2 * math.pi))
                    .clamp(0.2, 1.0);
                return Container(
                  margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: Color.fromRGBO(42, 134, 255, t),
                    shape: BoxShape.circle,
                  ),
                );
              },
            );
          }),
        ),
      ),
    );
  }
}
