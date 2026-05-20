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
  final _supabase = Supabase.instance.client;
  late Future<List<_ConversationItem>> _convFuture;
  RealtimeChannel? _channel;

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

  String get _myId => _supabase.auth.currentUser?.id ?? '';

  Future<List<_ConversationItem>> _loadConversations() async {
    try {
      final rows = await _supabase
          .from('conversations')
          .select(
            'id, tourist_id, driver_id, booking_id, last_message, last_message_at',
          )
          .eq('tourist_id', _myId)
          .order('last_message_at', ascending: false)
          .limit(50);

      final convList = List<Map<String, dynamic>>.from(rows as List);
      if (convList.isEmpty) return [];

      final driverIds = convList
          .map((r) => r['driver_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final profileRows = await _supabase
          .from('profiles')
          .select(
            'id, full_name, first_name, last_name, mobile, avatar_url, profile_image_url',
          )
          .inFilter('id', driverIds);

      final profileMap = <String, Map<String, dynamic>>{
        for (final p in (profileRows as List<dynamic>))
          p['id'].toString(): Map<String, dynamic>.from(p as Map),
      };

      return convList.map((r) {
        final driver = profileMap[r['driver_id']?.toString() ?? ''];
        final rawName = driver?['full_name'] as String? ?? '';
        final fullName = rawName.isNotEmpty
            ? rawName
            : [
                driver?['first_name'],
                driver?['last_name'],
              ].whereType<String>().join(' ').trim();
        final avatar = (driver?['avatar_url'] as String? ?? '').isNotEmpty
            ? driver!['avatar_url'] as String
            : (driver?['profile_image_url'] as String? ?? '');
        return _ConversationItem(
          id: r['id'].toString(),
          driverId: r['driver_id']?.toString() ?? '',
          bookingId: r['booking_id']?.toString() ?? '',
          lastMessage: r['last_message'] as String? ?? '',
          lastMessageAt: r['last_message_at'] != null
              ? DateTime.tryParse(r['last_message_at'].toString())
              : null,
          driverName: fullName.isEmpty ? 'Driver' : fullName,
          driverPhone: driver?['mobile'] as String? ?? '',
          driverAvatar: avatar,
        );
      }).toList();
    } catch (_) {
      return const [];
    }
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('tourist-conversations:$_myId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'conversations',
          callback: (_) {
            if (!mounted) return;
            setState(() {
              _convFuture = _loadConversations();
            });
          },
        )
        .subscribe();
  }

  void _openChat(_ConversationItem conv) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => TouristChatScreen(
          conversationId: conv.id,
          driverId: conv.driverId,
          driverName: conv.driverName,
          driverPhone: conv.driverPhone,
          driverAvatar: conv.driverAvatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return TouristAiChatbotWrapper(
      child: Scaffold(
        backgroundColor: const Color(0xFFF5F7FB),
        bottomNavigationBar: const AppBottomNav(selectedIndex: 4),
        body: SafeArea(
        child: Column(
          children: [
            // Header
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 0),
              child: Row(
                children: [
                  const Text(
                    'Messages',
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF0F172A),
                      letterSpacing: -0.5,
                    ),
                  ),
                  const Spacer(),
                  Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0xFFEAF2FF),
                      borderRadius: BorderRadius.circular(14),
                    ),
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: Color(0xFF2A86FF),
                      size: 22,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<_ConversationItem>>(
                future: _convFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2A86FF),
                      ),
                    );
                  }
                  if (snap.hasError) {
                    return _ErrorState(
                      message: snap.error.toString(),
                      onRetry: () => setState(() {
                        _convFuture = _loadConversations();
                      }),
                    );
                  }
                  final convs = snap.data ?? [];
                  if (convs.isEmpty) return const _EmptyState();

                  return RefreshIndicator(
                    color: const Color(0xFF2A86FF),
                    onRefresh: () async {
                      if (!mounted) return;
                      setState(() {
                        _convFuture = _loadConversations();
                      });
                    },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: convs.length,
                      itemBuilder: (_, i) => Padding(
                        padding: const EdgeInsets.only(bottom: 10),
                        child: _ConvCard(
                          conv: convs[i],
                          onTap: () => _openChat(convs[i]),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    ));
  }
}

// ── Conversation card ──────────────────────────────────────────────────────

class _ConvCard extends StatelessWidget {
  const _ConvCard({required this.conv, required this.onTap});

  final _ConversationItem conv;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final timeStr = conv.lastMessageAt == null
        ? ''
        : _formatTime(conv.lastMessageAt!);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: const Color(0xFFE7EEF7)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.05),
              blurRadius: 16,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            _DriverAvatar(name: conv.driverName, imageUrl: conv.driverAvatar),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          conv.driverName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            color: Color(0xFF0F172A),
                            fontSize: 15.5,
                          ),
                        ),
                      ),
                      if (timeStr.isNotEmpty)
                        Text(
                          timeStr,
                          style: const TextStyle(
                            fontSize: 11.5,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    conv.lastMessage.isEmpty
                        ? 'No messages yet'
                        : conv.lastMessage,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: conv.lastMessage.isEmpty
                          ? const Color(0xFFCBD5E1)
                          : const Color(0xFF64748B),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            const Icon(Icons.chevron_right_rounded, color: Color(0xFFCBD5E1)),
          ],
        ),
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);
    if (diff.inDays == 0) return DateFormat.jm().format(dt);
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return DateFormat.EEEE().format(dt);
    return DateFormat.MMMd().format(dt);
  }
}

// ── Driver avatar ──────────────────────────────────────────────────────────

class _DriverAvatar extends StatelessWidget {
  const _DriverAvatar({required this.name, required this.imageUrl});

  final String name;
  final String imageUrl;

  @override
  Widget build(BuildContext context) {
    final initial = name.trim().isEmpty ? 'D' : name.trim()[0].toUpperCase();

    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        color: const Color(0xFFEAF2FF),
        shape: BoxShape.circle,
        border: Border.all(color: const Color(0xFFE7EEF7), width: 2),
      ),
      clipBehavior: Clip.antiAlias,
      child: imageUrl.isEmpty
          ? Center(
              child: Text(
                initial,
                style: const TextStyle(
                  color: Color(0xFF2A86FF),
                  fontWeight: FontWeight.w900,
                  fontSize: 22,
                ),
              ),
            )
          : Image.network(
              imageUrl,
              fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Center(
                child: Text(
                  initial,
                  style: const TextStyle(
                    color: Color(0xFF2A86FF),
                    fontWeight: FontWeight.w900,
                    fontSize: 22,
                  ),
                ),
              ),
            ),
    );
  }
}

// ── Empty state ────────────────────────────────────────────────────────────

class _EmptyState extends StatelessWidget {
  const _EmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 80,
              height: 80,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(28),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                color: Color(0xFF2A86FF),
                size: 38,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'No conversations yet',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w900,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Messages with assigned drivers will appear here once you have an active booking.',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 14,
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Error state ────────────────────────────────────────────────────────────

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.wifi_off_rounded,
              color: Color(0xFF94A3B8),
              size: 48,
            ),
            const SizedBox(height: 14),
            Text(
              'Could not load messages',
              style: const TextStyle(
                fontWeight: FontWeight.w900,
                fontSize: 16,
                color: Color(0xFF0F172A),
              ),
            ),
            const SizedBox(height: 8),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: const Text('Try again'),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Chat screen ────────────────────────────────────────────────────────────

class TouristChatScreen extends StatefulWidget {
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
  State<TouristChatScreen> createState() => _TouristChatScreenState();
}

class _TouristChatScreenState extends State<TouristChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late Future<List<_Message>> _msgFuture;
  RealtimeChannel? _channel;
  bool _sending = false;

  String get _myId => _supabase.auth.currentUser?.id ?? '';

  @override
  void initState() {
    super.initState();
    _msgFuture = _loadMessages();
    _subscribeRealtime();
  }

  @override
  void dispose() {
    _channel?.unsubscribe();
    _messageCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<List<_Message>> _loadMessages() async {
    try {
      final rows = await _supabase
          .from('messages')
          .select('id, sender_id, message_text, is_read, created_at')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true)
          .limit(200);

      final msgs = (rows as List<dynamic>).map((r) {
        return _Message(
          id: r['id'].toString(),
          senderId: r['sender_id']?.toString() ?? '',
          text: r['message_text'] as String? ?? '',
          isRead: r['is_read'] as bool? ?? false,
          createdAt: r['created_at'] != null
              ? DateTime.tryParse(r['created_at'].toString()) ?? DateTime.now()
              : DateTime.now(),
        );
      }).toList();

      _markRead();
      return msgs;
    } catch (_) {
      return const [];
    }
  }

  Future<void> _markRead() async {
    try {
      await _supabase
          .from('messages')
          .update({'is_read': true})
          .eq('conversation_id', widget.conversationId)
          .neq('sender_id', _myId);
    } catch (_) {}
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('chat:${widget.conversationId}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'conversation_id',
            value: widget.conversationId,
          ),
          callback: (_) => _refreshMessages(),
        )
        .subscribe();
  }

  void _refreshMessages() {
    if (!mounted) return;
    setState(() {
      _msgFuture = _loadMessages();
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());
  }

  void _scrollToBottom() {
    if (_scrollCtrl.hasClients) {
      _scrollCtrl.animateTo(
        _scrollCtrl.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    }
  }

  Future<void> _sendMessage() async {
    final text = _messageCtrl.text.trim();
    if (text.isEmpty || _sending) return;

    setState(() {
      _sending = true;
    });

    try {
      await _supabase.from('messages').insert({
        'conversation_id': widget.conversationId,
        'sender_id': _myId,
        'receiver_id': widget.driverId,
        'message_text': text,
        'is_read': false,
      });

      await _supabase
          .from('conversations')
          .update({
            'last_message': text,
            'last_message_at': DateTime.now().toIso8601String(),
          })
          .eq('id', widget.conversationId);

      if (!mounted) return;
      _messageCtrl.clear();
      _refreshMessages();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send your message right now. $e'),
          backgroundColor: const Color(0xFFDC2626),
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

  Future<void> _callDriver() async {
    final phone = widget.driverPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        child: Column(
          children: [
            // AppBar
            Container(
              color: Colors.white,
              padding: const EdgeInsets.fromLTRB(8, 10, 16, 10),
              child: Row(
                children: [
                  IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.arrow_back_rounded),
                    color: const Color(0xFF0F172A),
                  ),
                  _DriverAvatar(
                    name: widget.driverName,
                    imageUrl: widget.driverAvatar,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.driverName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const Text(
                          'Driver',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.driverPhone.isNotEmpty)
                    IconButton(
                      onPressed: _callDriver,
                      icon: const Icon(
                        Icons.phone_rounded,
                        color: Color(0xFF22C55E),
                      ),
                      tooltip: 'Call driver',
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE7EEF7)),
            // Messages
            Expanded(
              child: FutureBuilder<List<_Message>>(
                future: _msgFuture,
                builder: (context, snap) {
                  if (snap.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2A86FF),
                      ),
                    );
                  }
                  final msgs = snap.data ?? [];
                  if (msgs.isEmpty) {
                    return const Center(
                      child: Text(
                        'No messages yet. Say hello!',
                        style: TextStyle(
                          color: Color(0xFF94A3B8),
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  }
                  return ListView.builder(
                    controller: _scrollCtrl,
                    physics: const BouncingScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                    itemCount: msgs.length,
                    itemBuilder: (_, i) {
                      final msg = msgs[i];
                      final isMe = msg.senderId == _myId;
                      final showDate =
                          i == 0 ||
                          !_sameDay(msgs[i - 1].createdAt, msg.createdAt);
                      return Column(
                        children: [
                          if (showDate) _DateLabel(dt: msg.createdAt),
                          _MessageBubble(message: msg, isMe: isMe),
                        ],
                      );
                    },
                  );
                },
              ),
            ),
            // Input
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(16, 10, 16, 10 + bottomInset),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      decoration: BoxDecoration(
                        color: const Color(0xFFF1F5F9),
                        borderRadius: BorderRadius.circular(24),
                        border: Border.all(color: const Color(0xFFE2E8F0)),
                      ),
                      child: TextField(
                        controller: _messageCtrl,
                        maxLines: 4,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: Color(0xFF0F172A),
                        ),
                        decoration: const InputDecoration(
                          hintText: 'Type a message...',
                          hintStyle: TextStyle(
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w600,
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
                    onTap: _sending ? null : _sendMessage,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
                        ),
                        borderRadius: BorderRadius.circular(16),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(
                              0xFF2A86FF,
                            ).withValues(alpha: 0.30),
                            blurRadius: 12,
                            offset: const Offset(0, 6),
                          ),
                        ],
                      ),
                      child: _sending
                          ? const Padding(
                              padding: EdgeInsets.all(12),
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(
                              Icons.send_rounded,
                              color: Colors.white,
                              size: 22,
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}

// ── Message bubble ─────────────────────────────────────────────────────────

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message, required this.isMe});

  final _Message message;
  final bool isMe;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 3),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.72,
        ),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: isMe ? const Color(0xFF2A86FF) : Colors.white,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(18),
            topRight: const Radius.circular(18),
            bottomLeft: Radius.circular(isMe ? 18 : 4),
            bottomRight: Radius.circular(isMe ? 4 : 18),
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 10,
              offset: const Offset(0, 4),
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
                color: isMe ? Colors.white : const Color(0xFF0F172A),
                fontWeight: FontWeight.w700,
                fontSize: 14.5,
                height: 1.38,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              DateFormat.jm().format(message.createdAt),
              style: TextStyle(
                fontSize: 10.5,
                color: isMe
                    ? Colors.white.withValues(alpha: 0.75)
                    : const Color(0xFF94A3B8),
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── Date label ─────────────────────────────────────────────────────────────

class _DateLabel extends StatelessWidget {
  const _DateLabel({required this.dt});

  final DateTime dt;

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    String label;
    if (dt.year == now.year && dt.month == now.month && dt.day == now.day) {
      label = 'Today';
    } else if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day - 1) {
      label = 'Yesterday';
    } else {
      label = DateFormat('MMMM d, yyyy').format(dt);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
          decoration: BoxDecoration(
            color: const Color(0xFFE2E8F0),
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              fontWeight: FontWeight.w800,
              color: Color(0xFF64748B),
            ),
          ),
        ),
      ),
    );
  }
}

// ── Data models ────────────────────────────────────────────────────────────

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
