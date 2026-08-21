import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/app_bottom_nav_tourist.dart';
import 'package:touristrike/components/tourist/ai_chatbot_floating_widget.dart';

class TouristMessagesScreen extends StatefulWidget {
  const TouristMessagesScreen({super.key});

  @override
  State<TouristMessagesScreen> createState() => _TouristMessagesScreenState();
}

class _TouristMessagesScreenState extends State<TouristMessagesScreen> {
  final SupabaseClient _supabase = Supabase.instance.client;

  late Future<List<_ConversationItem>> _convFuture;

  RealtimeChannel? _channel;

  static const String _forcedRole = String.fromEnvironment(
    'FORCE_ROLE',
    defaultValue: '',
  );

  bool get _isTouristPreview =>
      _forcedRole.trim().toLowerCase() == 'tourist';

  String get _myId => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();

    _convFuture = _loadConversations();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    super.dispose();
  }

  Future<List<_ConversationItem>> _loadConversations() async {
    final user = _supabase.auth.currentUser;

    if (user == null && _isTouristPreview) {
      debugPrint(
        'MESSAGES preview: no authenticated Supabase user. '
        'Showing preview conversation state.',
      );

      return const [];
    }

    if (user == null) {
      return const [];
    }

    try {
      final rows = await _supabase
          .from('conversations')
          .select(
            'id, tourist_id, driver_id, booking_id, '
            'last_message, last_message_at',
          )
          .eq('tourist_id', user.id)
          .order(
            'last_message_at',
            ascending: false,
          )
          .limit(50);

      final convList = List<Map<String, dynamic>>.from(
        rows as List,
      );

      if (convList.isEmpty) {
        return const [];
      }

      final driverIds = convList
          .map(
            (row) => row['driver_id']?.toString(),
          )
          .whereType<String>()
          .where((id) => id.isNotEmpty)
          .toSet()
          .toList();

      Map<String, Map<String, dynamic>> profileMap = {};

      if (driverIds.isNotEmpty) {
        final profileRows = await _supabase
            .from('profiles')
            .select(
              'id, full_name, first_name, last_name, '
              'mobile, avatar_url, profile_image_url',
            )
            .inFilter(
              'id',
              driverIds,
            );

        profileMap = {
          for (final profile in profileRows as List<dynamic>)
            profile['id'].toString():
                Map<String, dynamic>.from(profile as Map),
        };
      }

      return convList.map((row) {
        final driverId =
            row['driver_id']?.toString() ?? '';

        final driver =
            profileMap[driverId];

        final rawName =
            driver?['full_name'] as String? ?? '';

        final fullName = rawName.trim().isNotEmpty
            ? rawName.trim()
            : [
                driver?['first_name'],
                driver?['last_name'],
              ]
                .whereType<String>()
                .where(
                  (value) => value.trim().isNotEmpty,
                )
                .join(' ')
                .trim();

        final avatarUrl =
            (driver?['avatar_url'] as String? ?? '')
                    .trim()
                    .isNotEmpty
                ? driver!['avatar_url'] as String
                : (driver?['profile_image_url']
                            as String? ??
                        '');

        return _ConversationItem(
          id: row['id'].toString(),
          driverId: driverId,
          bookingId:
              row['booking_id']?.toString() ?? '',
          lastMessage:
              row['last_message'] as String? ?? '',
          lastMessageAt:
              row['last_message_at'] != null
                  ? DateTime.tryParse(
                      row['last_message_at']
                          .toString(),
                    )
                  : null,
          driverName: fullName.isEmpty
              ? 'Driver'
              : fullName,
          driverPhone:
              driver?['mobile'] as String? ?? '',
          driverAvatar: avatarUrl,
        );
      }).toList();
    } catch (error, stackTrace) {
      debugPrint(
        'MESSAGES _loadConversations error: $error',
      );

      debugPrintStack(
        stackTrace: stackTrace,
      );

      return const [];
    }
  }

  void _subscribeRealtime() {
    final user = _supabase.auth.currentUser;

    if (user == null) {
      debugPrint(
        'MESSAGES realtime skipped: '
        'no authenticated Supabase session.',
      );

      return;
    }

    _channel?.unsubscribe();

    _channel = _supabase
        .channel(
          'tourist-conversations:${user.id}',
        )
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) {
            if (!mounted) return;

            setState(() {
              _convFuture =
                  _loadConversations();
            });
          },
        )
        .subscribe();
  }

  Future<void> _refresh() async {
    if (!mounted) return;

    setState(() {
      _convFuture = _loadConversations();
    });

    await _convFuture;
  }

  void _openChat(
    _ConversationItem conversation,
  ) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TouristChatScreen(
          conversationId:
              conversation.id,
          driverId:
              conversation.driverId,
          driverName:
              conversation.driverName,
          driverPhone:
              conversation.driverPhone,
          driverAvatar:
              conversation.driverAvatar,
        ),
      ),
    ).then((_) {
      if (!mounted) return;

      _refresh();
    });
  }

  @override
  Widget build(BuildContext context) {
    return TouristAiChatbotWrapper(
      child: Scaffold(
        backgroundColor:
            const Color(0xFFF6F8FC),
        bottomNavigationBar:
            const AppBottomNav(
          selectedIndex: 4,
        ),
        body: SafeArea(
          bottom: false,
          child: Align(
            alignment: Alignment.topCenter,
            child: ConstrainedBox(
              constraints:
                  const BoxConstraints(
                maxWidth: 680,
              ),
              child: Column(
                children: [
                  const _MessagesHeader(),

                  Expanded(
                    child: FutureBuilder<
                        List<_ConversationItem>>(
                      future: _convFuture,
                      builder:
                          (context, snapshot) {
                        if (snapshot
                                .connectionState !=
                            ConnectionState.done) {
                          return const _MessagesLoadingState();
                        }

                        if (snapshot.hasError) {
                          return _ErrorState(
                            message:
                                snapshot.error
                                    .toString(),
                            onRetry: () {
                              setState(() {
                                _convFuture =
                                    _loadConversations();
                              });
                            },
                          );
                        }

                        final conversations =
                            snapshot.data ??
                                const [];

                        if (conversations
                            .isEmpty) {
                          return RefreshIndicator(
                            color:
                                const Color(
                              0xFF2A86FF,
                            ),
                            onRefresh: _refresh,
                            child:
                                const _EmptyConversationList(),
                          );
                        }

                        return RefreshIndicator(
                          color:
                              const Color(
                            0xFF2A86FF,
                          ),
                          backgroundColor:
                              Colors.white,
                          onRefresh: _refresh,
                          child: ListView(
                            physics:
                                const AlwaysScrollableScrollPhysics(
                              parent:
                                  BouncingScrollPhysics(),
                            ),
                            padding:
                                const EdgeInsets.fromLTRB(
                              18,
                              5,
                              18,
                              26,
                            ),
                            children: [
                              _ConversationSectionHeader(
                                count:
                                    conversations
                                        .length,
                              ),

                              const SizedBox(
                                height: 12,
                              ),

                              ...conversations.map(
                                (
                                  conversation,
                                ) =>
                                    Padding(
                                  padding:
                                      const EdgeInsets.only(
                                    bottom: 11,
                                  ),
                                  child:
                                      _ConversationCard(
                                    conversation:
                                        conversation,
                                    onTap: () =>
                                        _openChat(
                                      conversation,
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// MESSAGES HEADER
// ============================================================================

class _MessagesHeader
    extends StatelessWidget {
  const _MessagesHeader();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        20,
        18,
        20,
        17,
      ),
      child: Row(
        children: [
          const Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  'Messages',
                  style: TextStyle(
                    fontSize: 26,
                    fontWeight:
                        FontWeight.w900,
                    color:
                        Color(0xFF111827),
                    letterSpacing: -0.7,
                    height: 1.05,
                  ),
                ),
                SizedBox(height: 6),
                Text(
                  'Stay connected with your assigned drivers.',
                  style: TextStyle(
                    color:
                        Color(0xFF7C8BA1),
                    fontWeight:
                        FontWeight.w600,
                    fontSize: 12.5,
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(width: 12),

          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              gradient:
                  const LinearGradient(
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
                colors: [
                  Color(0xFFEFF6FF),
                  Color(0xFFE1EEFF),
                ],
              ),
              borderRadius:
                  BorderRadius.circular(15),
              border: Border.all(
                color:
                    const Color(
                  0xFFDCEAFE,
                ),
              ),
            ),
            child: const Icon(
              Icons.chat_bubble_outline_rounded,
              color:
                  Color(0xFF2A86FF),
              size: 22,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// CONVERSATIONS SECTION HEADER
// ============================================================================

class _ConversationSectionHeader
    extends StatelessWidget {
  const _ConversationSectionHeader({
    required this.count,
  });

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        const Expanded(
          child: Column(
            crossAxisAlignment:
                CrossAxisAlignment.start,
            children: [
              Text(
                'Conversations',
                style: TextStyle(
                  color:
                      Color(0xFF111827),
                  fontSize: 16.5,
                  fontWeight:
                      FontWeight.w900,
                  letterSpacing: -0.2,
                ),
              ),
              SizedBox(height: 3),
              Text(
                'Your recent driver chats',
                style: TextStyle(
                  color:
                      Color(0xFF8C99AB),
                  fontWeight:
                      FontWeight.w600,
                  fontSize: 11.5,
                ),
              ),
            ],
          ),
        ),

        Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 10,
            vertical: 6,
          ),
          decoration: BoxDecoration(
            color:
                const Color(0xFFEAF3FF),
            borderRadius:
                BorderRadius.circular(999),
          ),
          child: Text(
            '$count',
            style: const TextStyle(
              color:
                  Color(0xFF2A86FF),
              fontWeight:
                  FontWeight.w900,
              fontSize: 11,
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// CONVERSATION CARD
// ============================================================================

class _ConversationCard
    extends StatelessWidget {
  const _ConversationCard({
    required this.conversation,
    required this.onTap,
  });

  final _ConversationItem conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final timeText =
        conversation.lastMessageAt == null
            ? ''
            : _formatTime(
                conversation.lastMessageAt!,
              );

    final preview =
        conversation.lastMessage.trim().isEmpty
            ? 'Start a conversation'
            : conversation.lastMessage.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius:
            BorderRadius.circular(22),
        child: Ink(
          padding:
              const EdgeInsets.fromLTRB(
            14,
            14,
            12,
            14,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(22),
            border: Border.all(
              color:
                  const Color(0xFFE5ECF5),
            ),
            boxShadow: [
              BoxShadow(
                color:
                    const Color(0xFF0F172A)
                        .withValues(
                  alpha: 0.045,
                ),
                blurRadius: 18,
                offset:
                    const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              _DriverAvatar(
                name:
                    conversation.driverName,
                imageUrl:
                    conversation.driverAvatar,
                size: 56,
                showOnlineDot: true,
              ),

              const SizedBox(width: 13),

              Expanded(
                child: Column(
                  crossAxisAlignment:
                      CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            conversation
                                .driverName,
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style:
                                const TextStyle(
                              fontWeight:
                                  FontWeight
                                      .w900,
                              color:
                                  Color(
                                0xFF111827,
                              ),
                              fontSize:
                                  15.5,
                              letterSpacing:
                                  -0.15,
                            ),
                          ),
                        ),

                        if (timeText
                            .isNotEmpty) ...[
                          const SizedBox(
                            width: 8,
                          ),
                          Text(
                            timeText,
                            style:
                                const TextStyle(
                              fontSize: 10.5,
                              color:
                                  Color(
                                0xFF98A2B3,
                              ),
                              fontWeight:
                                  FontWeight
                                      .w600,
                            ),
                          ),
                        ],
                      ],
                    ),

                    const SizedBox(height: 5),

                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration:
                              const BoxDecoration(
                            color: Color(
                              0xFF2A86FF,
                            ),
                            shape:
                                BoxShape.circle,
                          ),
                        ),

                        const SizedBox(width: 6),

                        Expanded(
                          child: Text(
                            preview,
                            maxLines: 1,
                            overflow:
                                TextOverflow
                                    .ellipsis,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: conversation
                                      .lastMessage
                                      .trim()
                                      .isEmpty
                                  ? const Color(
                                      0xFFA7B2C1,
                                    )
                                  : const Color(
                                      0xFF667085,
                                    ),
                              fontWeight:
                                  FontWeight
                                      .w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              const SizedBox(width: 8),

              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color:
                      const Color(
                    0xFFF4F7FB,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    10,
                  ),
                ),
                child: const Icon(
                  Icons.chevron_right_rounded,
                  color:
                      Color(0xFFA0AEC0),
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _formatTime(
    DateTime rawDate,
  ) {
    final date = rawDate.toLocal();
    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final messageDay = DateTime(
      date.year,
      date.month,
      date.day,
    );

    final difference =
        today.difference(messageDay).inDays;

    if (difference == 0) {
      return DateFormat.jm().format(date);
    }

    if (difference == 1) {
      return 'Yesterday';
    }

    if (difference > 1 &&
        difference < 7) {
      return DateFormat.E().format(date);
    }

    if (date.year == now.year) {
      return DateFormat.MMMd().format(date);
    }

    return DateFormat(
      'MMM d, yyyy',
    ).format(date);
  }
}

// ============================================================================
// DRIVER AVATAR
// ============================================================================

class _DriverAvatar
    extends StatelessWidget {
  const _DriverAvatar({
    required this.name,
    required this.imageUrl,
    this.size = 52,
    this.showOnlineDot = false,
  });

  final String name;
  final String imageUrl;
  final double size;
  final bool showOnlineDot;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty
        ? 'D'
        : name.trim()[0].toUpperCase();

    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color:
                    const Color(
                  0xFFEAF3FF,
                ),
                shape: BoxShape.circle,
                border: Border.all(
                  color:
                      const Color(
                    0xFFE1EAF5,
                  ),
                  width: 2,
                ),
              ),
              clipBehavior:
                  Clip.antiAlias,
              child: imageUrl.trim().isEmpty
                  ? _AvatarInitial(
                      initial:
                          initial,
                    )
                  : Image.network(
                      imageUrl,
                      fit: BoxFit.cover,
                      errorBuilder:
                          (_, _, _) =>
                              _AvatarInitial(
                        initial:
                            initial,
                      ),
                    ),
            ),
          ),

          if (showOnlineDot)
            Positioned(
              right: 1,
              bottom: 2,
              child: Container(
                width: 13,
                height: 13,
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFF22C55E,
                  ),
                  shape:
                      BoxShape.circle,
                  border: Border.all(
                    color:
                        Colors.white,
                    width: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _AvatarInitial
    extends StatelessWidget {
  const _AvatarInitial({
    required this.initial,
  });

  final String initial;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Text(
        initial,
        style: const TextStyle(
          color:
              Color(0xFF2A86FF),
          fontWeight:
              FontWeight.w900,
          fontSize: 21,
        ),
      ),
    );
  }
}

// ============================================================================
// EMPTY CONVERSATION STATE
// ============================================================================

class _EmptyConversationList
    extends StatelessWidget {
  const _EmptyConversationList();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(
        22,
        34,
        22,
        30,
      ),
      children: [
        const SizedBox(height: 20),

        Center(
          child: Container(
            width: 92,
            height: 92,
            decoration: BoxDecoration(
              gradient:
                  const LinearGradient(
                begin:
                    Alignment.topLeft,
                end:
                    Alignment.bottomRight,
                colors: [
                  Color(0xFFF1F7FF),
                  Color(0xFFE4F0FF),
                ],
              ),
              borderRadius:
                  BorderRadius.circular(31),
              border: Border.all(
                color:
                    const Color(
                  0xFFDCEAFF,
                ),
              ),
            ),
            child: const Center(
              child: Icon(
                Icons
                    .chat_bubble_outline_rounded,
                color:
                    Color(0xFF2A86FF),
                size: 40,
              ),
            ),
          ),
        ),

        const SizedBox(height: 22),

        const Text(
          'Your conversations will appear here',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 18,
            fontWeight:
                FontWeight.w900,
            color:
                Color(0xFF111827),
            letterSpacing: -0.25,
          ),
        ),

        const SizedBox(height: 8),

        Center(
          child: ConstrainedBox(
            constraints:
                BoxConstraints(
              maxWidth: 310,
            ),
            child: Text(
              'Once a driver is assigned to your booking, you can message them directly from TourisTrike.',
              textAlign:
                  TextAlign.center,
              style: TextStyle(
                fontSize: 12.5,
                color:
                    Color(
                  0xFF718096,
                ),
                fontWeight:
                    FontWeight.w600,
                height: 1.45,
              ),
            ),
          ),
        ),

        const SizedBox(height: 22),

        Center(
          child: Container(
            padding:
                const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            decoration: BoxDecoration(
              color:
                  const Color(
                0xFFF0F7FF,
              ),
              borderRadius:
                  BorderRadius.circular(
                999,
              ),
            ),
            child: const Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Icon(
                  Icons
                      .verified_user_outlined,
                  color:
                      Color(
                    0xFF2A86FF,
                  ),
                  size: 15,
                ),
                SizedBox(width: 6),
                Text(
                  'Chat with your assigned driver',
                  style: TextStyle(
                    color:
                        Color(
                      0xFF4D6D91,
                    ),
                    fontWeight:
                        FontWeight
                            .w700,
                    fontSize: 10.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ============================================================================
// MESSAGES LOADING STATE
// ============================================================================

class _MessagesLoadingState
    extends StatelessWidget {
  const _MessagesLoadingState();

  @override
  Widget build(BuildContext context) {
    return ListView(
      physics:
          const AlwaysScrollableScrollPhysics(),
      padding:
          const EdgeInsets.fromLTRB(
        18,
        10,
        18,
        20,
      ),
      children: [
        const Row(
          children: [
            Expanded(
              child: Text(
                'Conversations',
                style: TextStyle(
                  color:
                      Color(0xFF111827),
                  fontWeight:
                      FontWeight.w900,
                  fontSize: 16.5,
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 14),

        ...List.generate(
          3,
          (index) => const Padding(
            padding:
                EdgeInsets.only(
              bottom: 11,
            ),
            child:
                _ConversationSkeleton(),
          ),
        ),
      ],
    );
  }
}

class _ConversationSkeleton
    extends StatelessWidget {
  const _ConversationSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 84,
      padding:
          const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius:
            BorderRadius.circular(22),
        border: Border.all(
          color:
              const Color(0xFFE8EDF5),
        ),
      ),
      child: Row(
        children: [
          Container(
            width: 54,
            height: 54,
            decoration:
                const BoxDecoration(
              color:
                  Color(0xFFEEF2F7),
              shape:
                  BoxShape.circle,
            ),
          ),

          const SizedBox(width: 13),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              mainAxisAlignment:
                  MainAxisAlignment.center,
              children: [
                Container(
                  width: 135,
                  height: 12,
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFFEDF1F5,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      6,
                    ),
                  ),
                ),
                const SizedBox(height: 9),
                Container(
                  width: 195,
                  height: 10,
                  decoration:
                      BoxDecoration(
                    color:
                        const Color(
                      0xFFF1F4F7,
                    ),
                    borderRadius:
                        BorderRadius.circular(
                      6,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ERROR STATE
// ============================================================================

class _ErrorState
    extends StatelessWidget {
  const _ErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(26),
        child: Container(
          width: double.infinity,
          constraints:
              const BoxConstraints(
            maxWidth: 400,
          ),
          padding:
              const EdgeInsets.fromLTRB(
            24,
            28,
            24,
            24,
          ),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius:
                BorderRadius.circular(26),
            border: Border.all(
              color:
                  const Color(
                0xFFE5ECF5,
              ),
            ),
            boxShadow: [
              BoxShadow(
                color:
                    const Color(
                  0xFF0F172A,
                ).withValues(
                  alpha: 0.06,
                ),
                blurRadius: 25,
                offset:
                    const Offset(
                  0,
                  10,
                ),
              ),
            ],
          ),
          child: Column(
            mainAxisSize:
                MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration:
                    BoxDecoration(
                  color:
                      const Color(
                    0xFFF1F5F9,
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    20,
                  ),
                ),
                child: const Icon(
                  Icons
                      .wifi_off_rounded,
                  color:
                      Color(
                    0xFF64748B,
                  ),
                  size: 29,
                ),
              ),

              const SizedBox(
                height: 17,
              ),

              const Text(
                'Could not load messages',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  fontWeight:
                      FontWeight.w900,
                  fontSize: 17,
                  color:
                      Color(
                    0xFF111827,
                  ),
                ),
              ),

              const SizedBox(
                height: 7,
              ),

              const Text(
                'Check your connection and try loading your conversations again.',
                textAlign:
                    TextAlign.center,
                style: TextStyle(
                  color:
                      Color(
                    0xFF718096,
                  ),
                  fontWeight:
                      FontWeight.w600,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),

              const SizedBox(
                height: 20,
              ),

              SizedBox(
                width:
                    double.infinity,
                height: 47,
                child:
                    ElevatedButton.icon(
                  onPressed: onRetry,
                  icon: const Icon(
                    Icons
                        .refresh_rounded,
                    size: 18,
                  ),
                  label:
                      const Text(
                    'Try Again',
                  ),
                  style:
                      ElevatedButton
                          .styleFrom(
                    backgroundColor:
                        const Color(
                      0xFF2A86FF,
                    ),
                    foregroundColor:
                        Colors.white,
                    elevation: 0,
                    shape:
                        RoundedRectangleBorder(
                      borderRadius:
                          BorderRadius.circular(
                        14,
                      ),
                    ),
                    textStyle:
                        const TextStyle(
                      fontWeight:
                          FontWeight
                              .w800,
                      fontSize: 13,
                    ),
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

// ============================================================================
// CHAT SCREEN
// ============================================================================

class TouristChatScreen
    extends StatefulWidget {
  const TouristChatScreen({
    super.key,
    required this.conversationId,
    required this.driverId,
    required this.driverName,
    required this.driverPhone,
    required this.driverAvatar,
  });

  final String conversationId;
  final String driverId;
  final String driverName;
  final String driverPhone;
  final String driverAvatar;

  @override
  State<TouristChatScreen>
      createState() =>
          _TouristChatScreenState();
}

class _TouristChatScreenState
    extends State<TouristChatScreen> {
  final SupabaseClient _supabase =
      Supabase.instance.client;

  final TextEditingController
      _messageController =
      TextEditingController();

  final ScrollController
      _scrollController =
      ScrollController();

  late Future<List<_Message>>
      _messagesFuture;

  RealtimeChannel? _channel;

  bool _sending = false;

  String get _myId =>
      _supabase.auth.currentUser?.id ??
      '';

  @override
  void initState() {
    super.initState();

    _messagesFuture =
        _loadMessages();

    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _messageController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<List<_Message>>
      _loadMessages() async {
    final user =
        _supabase.auth.currentUser;

    if (user == null) {
      return const [];
    }

    try {
      final rows = await _supabase
          .from('messages')
          .select(
            'id, sender_id, '
            'message_text, is_read, created_at',
          )
          .eq(
            'conversation_id',
            widget.conversationId,
          )
          .order(
            'created_at',
            ascending: true,
          )
          .limit(200);

      final messages =
          (rows as List<dynamic>)
              .map((row) {
        return _Message(
          id: row['id'].toString(),
          senderId:
              row['sender_id']
                      ?.toString() ??
                  '',
          text:
              row['message_text']
                      as String? ??
                  '',
          isRead:
              row['is_read']
                      as bool? ??
                  false,
          createdAt:
              row['created_at'] != null
                  ? DateTime.tryParse(
                        row['created_at']
                            .toString(),
                      ) ??
                      DateTime.now()
                  : DateTime.now(),
        );
      }).toList();

      await _markRead();

      WidgetsBinding.instance
          .addPostFrameCallback(
        (_) {
          _scrollToBottom(
            animated: false,
          );
        },
      );

      return messages;
    } catch (error) {
      debugPrint(
        'CHAT load error: $error',
      );

      return const [];
    }
  }

  Future<void> _markRead() async {
    if (_myId.isEmpty) return;

    try {
      await _supabase
          .from('messages')
          .update({
            'is_read': true,
          })
          .eq(
            'conversation_id',
            widget.conversationId,
          )
          .neq(
            'sender_id',
            _myId,
          );
    } catch (error) {
      debugPrint(
        'CHAT mark read error: $error',
      );
    }
  }

  void _subscribeRealtime() {
    if (_supabase.auth.currentUser ==
        null) {
      return;
    }

    _channel = _supabase
        .channel(
          'chat:${widget.conversationId}',
        )
        .onPostgresChanges(
          event:
              PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter:
              PostgresChangeFilter(
            type:
                PostgresChangeFilterType
                    .eq,
            column:
                'conversation_id',
            value:
                widget.conversationId,
          ),
          callback: (_) {
            _refreshMessages();
          },
        )
        .subscribe();
  }

  void _refreshMessages() {
    if (!mounted) return;

    setState(() {
      _messagesFuture =
          _loadMessages();
    });

    WidgetsBinding.instance
        .addPostFrameCallback(
      (_) {
        _scrollToBottom();
      },
    );
  }

  void _scrollToBottom({
    bool animated = true,
  }) {
    if (!_scrollController
        .hasClients) {
      return;
    }

    final target =
        _scrollController
            .position
            .maxScrollExtent;

    if (!animated) {
      _scrollController.jumpTo(
        target,
      );
      return;
    }

    _scrollController.animateTo(
      target,
      duration:
          const Duration(
        milliseconds: 280,
      ),
      curve: Curves.easeOut,
    );
  }

  Future<void>
      _sendMessage() async {
    final text =
        _messageController.text.trim();

    if (text.isEmpty ||
        _sending ||
        _myId.isEmpty) {
      return;
    }

    setState(() {
      _sending = true;
    });

    try {
      await _supabase
          .from('messages')
          .insert({
        'conversation_id':
            widget.conversationId,
        'sender_id': _myId,
        'receiver_id':
            widget.driverId,
        'message_text': text,
        'is_read': false,
      });

      await _supabase
          .from('conversations')
          .update({
            'last_message': text,
            'last_message_at':
                DateTime.now()
                    .toIso8601String(),
          })
          .eq(
            'id',
            widget.conversationId,
          );

      if (!mounted) return;

      _messageController.clear();
      _refreshMessages();
    } catch (error) {
      if (!mounted) return;

      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(
          SnackBar(
            behavior:
                SnackBarBehavior.floating,
            margin:
                const EdgeInsets.all(
              16,
            ),
            shape:
                RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(
                14,
              ),
            ),
            content: const Row(
              children: [
                Icon(
                  Icons
                      .error_outline_rounded,
                  color:
                      Colors.white,
                  size: 20,
                ),
                SizedBox(width: 9),
                Expanded(
                  child: Text(
                    'Could not send your message right now.',
                    style:
                        TextStyle(
                      fontWeight:
                          FontWeight
                              .w600,
                    ),
                  ),
                ),
              ],
            ),
            backgroundColor:
                const Color(
              0xFFDC2626,
            ),
          ),
        );
    } finally {
      if (mounted) {
        setState(() {
          _sending = false;
        });
      }
    }
  }

  Future<void>
      _callDriver() async {
    final phone =
        widget.driverPhone.trim();

    if (phone.isEmpty) {
      return;
    }

    final uri =
        Uri.parse('tel:$phone');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomSafe =
        MediaQuery.of(context)
            .padding
            .bottom;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor:
          const Color(0xFFF6F8FC),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            _ChatHeader(
              driverName:
                  widget.driverName,
              driverAvatar:
                  widget.driverAvatar,
              hasPhone: widget
                  .driverPhone
                  .trim()
                  .isNotEmpty,
              onBack: () =>
                  Navigator.pop(
                context,
              ),
              onCall: _callDriver,
            ),

            Expanded(
              child: FutureBuilder<
                  List<_Message>>(
                future:
                    _messagesFuture,
                builder:
                    (context, snapshot) {
                  if (snapshot
                          .connectionState !=
                      ConnectionState
                          .done) {
                    return const Center(
                      child:
                          CircularProgressIndicator(
                        color:
                            Color(
                          0xFF2A86FF,
                        ),
                        strokeWidth:
                            3,
                      ),
                    );
                  }

                  final messages =
                      snapshot.data ??
                          const [];

                  if (messages.isEmpty) {
                    return _ChatEmptyState(
                      driverName:
                          widget
                              .driverName,
                    );
                  }

                  return ListView.builder(
                    controller:
                        _scrollController,
                    physics:
                        const BouncingScrollPhysics(),
                    padding:
                        const EdgeInsets.fromLTRB(
                      16,
                      15,
                      16,
                      16,
                    ),
                    itemCount:
                        messages.length,
                    itemBuilder:
                        (context, index) {
                      final message =
                          messages[index];

                      final isMe =
                          message.senderId ==
                              _myId;

                      final showDate =
                          index == 0 ||
                              !_sameDay(
                                messages[
                                        index -
                                            1]
                                    .createdAt,
                                message
                                    .createdAt,
                              );

                      return Column(
                        children: [
                          if (showDate)
                            _DateLabel(
                              date: message
                                  .createdAt,
                            ),
                          _MessageBubble(
                            message:
                                message,
                            isMe: isMe,
                          ),
                        ],
                      );
                    },
                  );
                },
              ),
            ),

            _MessageComposer(
              controller:
                  _messageController,
              sending: _sending,
              bottomSafe:
                  bottomSafe,
              onSend: _sendMessage,
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(
    DateTime first,
    DateTime second,
  ) {
    final a = first.toLocal();
    final b = second.toLocal();

    return a.year == b.year &&
        a.month == b.month &&
        a.day == b.day;
  }
}

// ============================================================================
// CHAT HEADER
// ============================================================================

class _ChatHeader
    extends StatelessWidget {
  const _ChatHeader({
    required this.driverName,
    required this.driverAvatar,
    required this.hasPhone,
    required this.onBack,
    required this.onCall,
  });

  final String driverName;
  final String driverAvatar;
  final bool hasPhone;
  final VoidCallback onBack;
  final VoidCallback onCall;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding:
          const EdgeInsets.fromLTRB(
        8,
        9,
        12,
        11,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          bottom: BorderSide(
            color:
                Color(0xFFE9EEF5),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(
              0xFF0F172A,
            ).withValues(
              alpha: 0.035,
            ),
            blurRadius: 14,
            offset:
                const Offset(0, 5),
          ),
        ],
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: onBack,
            tooltip: 'Back',
            icon: const Icon(
              Icons
                  .arrow_back_ios_new_rounded,
              size: 19,
            ),
            color:
                const Color(
              0xFF344054,
            ),
          ),

          _DriverAvatar(
            name: driverName,
            imageUrl:
                driverAvatar,
            size: 46,
            showOnlineDot: true,
          ),

          const SizedBox(width: 11),

          Expanded(
            child: Column(
              crossAxisAlignment:
                  CrossAxisAlignment.start,
              children: [
                Text(
                  driverName,
                  maxLines: 1,
                  overflow:
                      TextOverflow.ellipsis,
                  style:
                      const TextStyle(
                    fontWeight:
                        FontWeight.w900,
                    fontSize: 15.5,
                    color:
                        Color(
                      0xFF111827,
                    ),
                    letterSpacing:
                        -0.15,
                  ),
                ),
                const SizedBox(
                  height: 3,
                ),
                const Row(
                  children: [
                    SizedBox(
                      width: 7,
                      height: 7,
                      child:
                          DecoratedBox(
                        decoration:
                            BoxDecoration(
                          color:
                              Color(
                            0xFF22C55E,
                          ),
                          shape:
                              BoxShape
                                  .circle,
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 5,
                    ),
                    Text(
                      'Assigned Driver',
                      style:
                          TextStyle(
                        fontSize:
                            11,
                        color:
                            Color(
                          0xFF7C8BA1,
                        ),
                        fontWeight:
                            FontWeight
                                .w600,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          if (hasPhone)
            Material(
              color:
                  const Color(
                0xFFECFDF3,
              ),
              borderRadius:
                  BorderRadius.circular(
                13,
              ),
              child: InkWell(
                onTap: onCall,
                borderRadius:
                    BorderRadius.circular(
                  13,
                ),
                child:
                    const SizedBox(
                  width: 43,
                  height: 43,
                  child: Icon(
                    Icons
                        .phone_rounded,
                    color:
                        Color(
                      0xFF16A34A,
                    ),
                    size: 20,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

// ============================================================================
// CHAT EMPTY STATE
// ============================================================================

class _ChatEmptyState
    extends StatelessWidget {
  const _ChatEmptyState({
    required this.driverName,
  });

  final String driverName;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding:
            const EdgeInsets.all(30),
        child: Column(
          mainAxisSize:
              MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration:
                  BoxDecoration(
                color:
                    const Color(
                  0xFFEAF3FF,
                ),
                borderRadius:
                    BorderRadius.circular(
                  25,
                ),
              ),
              child: const Icon(
                Icons
                    .waving_hand_outlined,
                color:
                    Color(
                  0xFF2A86FF,
                ),
                size: 32,
              ),
            ),

            const SizedBox(
              height: 18,
            ),

            Text(
              'Start chatting with $driverName',
              textAlign:
                  TextAlign.center,
              style:
                  const TextStyle(
                color:
                    Color(
                  0xFF111827,
                ),
                fontWeight:
                    FontWeight.w900,
                fontSize: 17,
              ),
            ),

            const SizedBox(
              height: 7,
            ),

            const Text(
              'Use this chat to coordinate your pickup, meeting point, and other trip details.',
              textAlign:
                  TextAlign.center,
              style:
                  TextStyle(
                color:
                    Color(
                  0xFF718096,
                ),
                fontWeight:
                    FontWeight.w600,
                fontSize: 12.5,
                height: 1.45,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// MESSAGE COMPOSER
// ============================================================================

class _MessageComposer
    extends StatelessWidget {
  const _MessageComposer({
    required this.controller,
    required this.sending,
    required this.bottomSafe,
    required this.onSend,
  });

  final TextEditingController
      controller;

  final bool sending;
  final double bottomSafe;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        10,
        14,
        10 + bottomSafe,
      ),
      decoration: BoxDecoration(
        color: Colors.white,
        border: const Border(
          top: BorderSide(
            color:
                Color(0xFFE8EDF4),
          ),
        ),
        boxShadow: [
          BoxShadow(
            color:
                const Color(
              0xFF0F172A,
            ).withValues(
              alpha: 0.05,
            ),
            blurRadius: 20,
            offset:
                const Offset(0, -5),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment:
            CrossAxisAlignment.end,
        children: [
          Expanded(
            child: Container(
              constraints:
                  const BoxConstraints(
                minHeight: 48,
              ),
              decoration:
                  BoxDecoration(
                color:
                    const Color(
                  0xFFF5F7FA,
                ),
                borderRadius:
                    BorderRadius.circular(
                  18,
                ),
                border: Border.all(
                  color:
                      const Color(
                    0xFFE1E7EF,
                  ),
                ),
              ),
              child: TextField(
                controller:
                    controller,
                minLines: 1,
                maxLines: 4,
                textInputAction:
                    TextInputAction
                        .send,
                onSubmitted: (_) {
                  if (!sending) {
                    onSend();
                  }
                },
                style:
                    const TextStyle(
                  color:
                      Color(
                    0xFF111827,
                  ),
                  fontWeight:
                      FontWeight.w600,
                  fontSize: 13.5,
                ),
                decoration:
                    const InputDecoration(
                  hintText:
                      'Message your driver...',
                  hintStyle:
                      TextStyle(
                    color:
                        Color(
                      0xFF98A2B3,
                    ),
                    fontWeight:
                        FontWeight.w500,
                    fontSize: 13,
                  ),
                  border:
                      InputBorder.none,
                  isDense: true,
                  contentPadding:
                      EdgeInsets.symmetric(
                    horizontal: 15,
                    vertical: 14,
                  ),
                ),
              ),
            ),
          ),

          const SizedBox(width: 9),

          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap:
                  sending ? null : onSend,
              borderRadius:
                  BorderRadius.circular(
                16,
              ),
              child:
                  AnimatedContainer(
                duration:
                    const Duration(
                  milliseconds: 180,
                ),
                width: 48,
                height: 48,
                decoration:
                    BoxDecoration(
                  gradient:
                      LinearGradient(
                    begin:
                        Alignment.topLeft,
                    end:
                        Alignment.bottomRight,
                    colors: sending
                        ? const [
                            Color(
                              0xFF9ACBFF,
                            ),
                            Color(
                              0xFF73B5FA,
                            ),
                          ]
                        : const [
                            Color(
                              0xFF55ACFF,
                            ),
                            Color(
                              0xFF2A86FF,
                            ),
                            Color(
                              0xFF2563EB,
                            ),
                          ],
                  ),
                  borderRadius:
                      BorderRadius.circular(
                    16,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color:
                          const Color(
                        0xFF2A86FF,
                      ).withValues(
                        alpha: sending
                            ? 0.12
                            : 0.25,
                      ),
                      blurRadius: 13,
                      offset:
                          const Offset(
                        0,
                        6,
                      ),
                    ),
                  ],
                ),
                child: sending
                    ? const Padding(
                        padding:
                            EdgeInsets.all(
                          14,
                        ),
                        child:
                            CircularProgressIndicator(
                          strokeWidth: 2,
                          color:
                              Colors.white,
                        ),
                      )
                    : const Icon(
                        Icons
                            .send_rounded,
                        color:
                            Colors.white,
                        size: 21,
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// MESSAGE BUBBLE
// ============================================================================

class _MessageBubble
    extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    required this.isMe,
  });

  final _Message message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    final screenWidth =
        MediaQuery.sizeOf(context)
            .width;

    return Align(
      alignment: isMe
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: Container(
        margin:
            const EdgeInsets.symmetric(
          vertical: 3.5,
        ),
        constraints:
            BoxConstraints(
          maxWidth:
              screenWidth * 0.74,
        ),
        padding:
            const EdgeInsets.fromLTRB(
          13,
          10,
          12,
          7,
        ),
        decoration: BoxDecoration(
          gradient: isMe
              ? const LinearGradient(
                  begin:
                      Alignment.topLeft,
                  end:
                      Alignment.bottomRight,
                  colors: [
                    Color(
                      0xFF469FFF,
                    ),
                    Color(
                      0xFF2A86FF,
                    ),
                  ],
                )
              : null,
          color: isMe
              ? null
              : Colors.white,
          borderRadius:
              BorderRadius.only(
            topLeft:
                const Radius.circular(
              18,
            ),
            topRight:
                const Radius.circular(
              18,
            ),
            bottomLeft:
                Radius.circular(
              isMe ? 18 : 5,
            ),
            bottomRight:
                Radius.circular(
              isMe ? 5 : 18,
            ),
          ),
          border: isMe
              ? null
              : Border.all(
                  color:
                      const Color(
                    0xFFE6ECF3,
                  ),
                ),
          boxShadow: [
            BoxShadow(
              color:
                  const Color(
                0xFF0F172A,
              ).withValues(
                alpha: 0.055,
              ),
              blurRadius: 10,
              offset:
                  const Offset(
                0,
                4,
              ),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: isMe
              ? CrossAxisAlignment.end
              : CrossAxisAlignment.start,
          children: [
            Text(
              message.text,
              style: TextStyle(
                color: isMe
                    ? Colors.white
                    : const Color(
                        0xFF1F2937,
                      ),
                fontWeight:
                    FontWeight.w600,
                fontSize: 13.5,
                height: 1.38,
              ),
            ),

            const SizedBox(
              height: 5,
            ),

            Row(
              mainAxisSize:
                  MainAxisSize.min,
              children: [
                Text(
                  DateFormat.jm().format(
                    message.createdAt
                        .toLocal(),
                  ),
                  style: TextStyle(
                    fontSize: 9.5,
                    color: isMe
                        ? Colors.white
                            .withValues(
                            alpha: 0.76,
                          )
                        : const Color(
                            0xFF98A2B3,
                          ),
                    fontWeight:
                        FontWeight.w600,
                  ),
                ),

                if (isMe) ...[
                  const SizedBox(
                    width: 4,
                  ),
                  Icon(
                    message.isRead
                        ? Icons
                            .done_all_rounded
                        : Icons
                            .done_rounded,
                    size: 13,
                    color: message
                            .isRead
                        ? const Color(
                            0xFFD7EEFF,
                          )
                        : Colors.white
                            .withValues(
                            alpha: 0.72,
                          ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================================
// DATE LABEL
// ============================================================================

class _DateLabel
    extends StatelessWidget {
  const _DateLabel({
    required this.date,
  });

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final localDate =
        date.toLocal();

    final now = DateTime.now();

    final today = DateTime(
      now.year,
      now.month,
      now.day,
    );

    final day = DateTime(
      localDate.year,
      localDate.month,
      localDate.day,
    );

    final difference =
        today.difference(day).inDays;

    String label;

    if (difference == 0) {
      label = 'Today';
    } else if (difference == 1) {
      label = 'Yesterday';
    } else {
      label = DateFormat(
        'MMMM d, yyyy',
      ).format(localDate);
    }

    return Padding(
      padding:
          const EdgeInsets.symmetric(
        vertical: 13,
      ),
      child: Center(
        child: Container(
          padding:
              const EdgeInsets.symmetric(
            horizontal: 11,
            vertical: 5,
          ),
          decoration:
              BoxDecoration(
            color:
                const Color(
              0xFFEAEFF5,
            ),
            borderRadius:
                BorderRadius.circular(
              999,
            ),
          ),
          child: Text(
            label,
            style:
                const TextStyle(
              fontSize: 10,
              fontWeight:
                  FontWeight.w700,
              color:
                  Color(
                0xFF718096,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// DATA MODELS
// ============================================================================

class _ConversationItem {
  const _ConversationItem({
    required this.id,
    required this.driverId,
    required this.bookingId,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.driverName,
    required this.driverPhone,
    required this.driverAvatar,
  });

  final String id;
  final String driverId;
  final String bookingId;

  final String lastMessage;
  final DateTime? lastMessageAt;

  final String driverName;
  final String driverPhone;
  final String driverAvatar;
}

class _Message {
  const _Message({
    required this.id,
    required this.senderId,
    required this.text,
    required this.isRead,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String text;
  final bool isRead;
  final DateTime createdAt;
}