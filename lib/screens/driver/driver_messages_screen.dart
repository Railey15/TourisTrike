import 'dart:async';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:touristrike/widgets/app_bottom_nav_driver.dart';

class DriverMessagesScreen extends StatefulWidget {
  const DriverMessagesScreen({super.key});

  @override
  State<DriverMessagesScreen> createState() => _DriverMessagesScreenState();
}

class _DriverMessagesScreenState extends State<DriverMessagesScreen> {
  final _supabase = Supabase.instance.client;
  late Future<List<_DriverConversationItem>> _convFuture;
  RealtimeChannel? _channel;

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

  Future<List<_DriverConversationItem>> _loadConversations() async {
    try {
      final rows = await _supabase
          .from('conversations')
          .select(
            'id, tourist_id, driver_id, booking_id, last_message, last_message_at',
          )
          .eq('driver_id', _myId)
          .order('last_message_at', ascending: false)
          .limit(50);

      final convList = List<Map<String, dynamic>>.from(rows as List);
      if (convList.isEmpty) return const [];

      final touristIds = convList
          .map((row) => row['tourist_id']?.toString())
          .whereType<String>()
          .toSet()
          .toList();

      final profileRows = await _supabase
          .from('profiles')
          .select(
            'id, full_name, first_name, last_name, mobile, avatar_url, profile_image_url',
          )
          .inFilter('id', touristIds);

      final profileMap = <String, Map<String, dynamic>>{
        for (final row in profileRows as List<dynamic>)
          row['id'].toString(): Map<String, dynamic>.from(row as Map),
      };

      return convList
          .map((row) {
            final tourist = profileMap[row['tourist_id']?.toString() ?? ''];
            final rawName = (tourist?['full_name'] as String? ?? '').trim();
            final displayName = rawName.isNotEmpty
                ? rawName
                : [
                    tourist?['first_name'] as String? ?? '',
                    tourist?['last_name'] as String? ?? '',
                  ].where((part) => part.trim().isNotEmpty).join(' ');
            final avatar = (tourist?['avatar_url'] as String? ?? '').trim();
            return _DriverConversationItem(
              id: row['id'].toString(),
              touristId: row['tourist_id']?.toString() ?? '',
              bookingId: row['booking_id']?.toString() ?? '',
              lastMessage: row['last_message'] as String? ?? '',
              lastMessageAt: row['last_message_at'] != null
                  ? DateTime.tryParse(row['last_message_at'].toString())
                  : null,
              touristName: displayName.isEmpty ? 'Tourist' : displayName,
              touristPhone: tourist?['mobile'] as String? ?? '',
              touristAvatar: avatar.isNotEmpty
                  ? avatar
                  : (tourist?['profile_image_url'] as String? ?? ''),
            );
          })
          .toList(growable: false);
    } catch (_) {
      return const [];
    }
  }

  void _subscribeRealtime() {
    _channel = _supabase
        .channel('driver-conversations:$_myId')
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

  void _openChat(_DriverConversationItem conversation) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => DriverChatScreen(
          conversationId: conversation.id,
          touristId: conversation.touristId,
          touristName: conversation.touristName,
          touristPhone: conversation.touristPhone,
          touristAvatar: conversation.touristAvatar,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FB),
      bottomNavigationBar: const AppBottomNavDriver(currentIndex: 4),
      body: SafeArea(
        child: Column(
          children: [
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
                      color: Color(0xFF2F6FFF),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),
            Expanded(
              child: FutureBuilder<List<_DriverConversationItem>>(
                future: _convFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2F6FFF),
                      ),
                    );
                  }
                  if (snapshot.hasError) {
                    return _DriverMessagesErrorState(
                      message: snapshot.error.toString(),
                      onRetry: () => setState(() {
                        _convFuture = _loadConversations();
                      }),
                    );
                  }

                  final conversations = snapshot.data ?? const [];
                  if (conversations.isEmpty) {
                    return const _DriverMessagesEmptyState();
                  }

                  return RefreshIndicator(
                    color: const Color(0xFF2F6FFF),
                    onRefresh: () async {
                      if (!mounted) return;
                      setState(() {
                        _convFuture = _loadConversations();
                      });
                    },
                    child: ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                      itemCount: conversations.length,
                      itemBuilder: (context, index) {
                        final item = conversations[index];
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: _DriverConversationCard(
                            conversation: item,
                            onTap: () => _openChat(item),
                          ),
                        );
                      },
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class DriverChatScreen extends StatefulWidget {
  const DriverChatScreen({
    super.key,
    required this.conversationId,
    required this.touristId,
    required this.touristName,
    required this.touristPhone,
    required this.touristAvatar,
  });

  final String conversationId;
  final String touristId;
  final String touristName;
  final String touristPhone;
  final String touristAvatar;

  @override
  State<DriverChatScreen> createState() => _DriverChatScreenState();
}

class _DriverChatScreenState extends State<DriverChatScreen> {
  final _supabase = Supabase.instance.client;
  final _messageCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late Future<List<_DriverMessage>> _msgFuture;
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

  Future<List<_DriverMessage>> _loadMessages() async {
    try {
      final rows = await _supabase
          .from('messages')
          .select('id, sender_id, message_text, is_read, created_at')
          .eq('conversation_id', widget.conversationId)
          .order('created_at', ascending: true)
          .limit(200);

      final messages = (rows as List<dynamic>)
          .map(
            (row) => _DriverMessage(
              id: row['id'].toString(),
              senderId: row['sender_id']?.toString() ?? '',
              text: row['message_text'] as String? ?? '',
              isRead: row['is_read'] as bool? ?? false,
              createdAt: row['created_at'] != null
                  ? DateTime.tryParse(row['created_at'].toString()) ??
                        DateTime.now()
                  : DateTime.now(),
            ),
          )
          .toList(growable: false);

      unawaited(_markRead());
      return messages;
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
        .channel('driver-chat:${widget.conversationId}')
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
    if (!_scrollCtrl.hasClients) return;
    _scrollCtrl.animateTo(
      _scrollCtrl.position.maxScrollExtent,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
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
        'receiver_id': widget.touristId,
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
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not send your message right now. $error'),
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

  Future<void> _callTourist() async {
    final phone = widget.touristPhone.trim();
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF5F7FB),
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
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
                  _DriverChatAvatar(
                    name: widget.touristName,
                    imageUrl: widget.touristAvatar,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.touristName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                            color: Color(0xFF0F172A),
                          ),
                        ),
                        const Text(
                          'Tourist',
                          style: TextStyle(
                            fontSize: 12,
                            color: Color(0xFF64748B),
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (widget.touristPhone.isNotEmpty)
                    IconButton(
                      onPressed: _callTourist,
                      icon: const Icon(
                        Icons.phone_rounded,
                        color: Color(0xFF22C55E),
                      ),
                      tooltip: 'Call tourist',
                    ),
                ],
              ),
            ),
            const Divider(height: 1, color: Color(0xFFE7EEF7)),
            Expanded(
              child: FutureBuilder<List<_DriverMessage>>(
                future: _msgFuture,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    return const Center(
                      child: CircularProgressIndicator(
                        color: Color(0xFF2F6FFF),
                      ),
                    );
                  }

                  final messages = snapshot.data ?? const [];
                  if (messages.isEmpty) {
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
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                    itemCount: messages.length,
                    itemBuilder: (context, index) {
                      final message = messages[index];
                      final mine = message.senderId == _myId;
                      return Align(
                        alignment: mine
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          constraints: BoxConstraints(
                            maxWidth: MediaQuery.of(context).size.width * 0.74,
                          ),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          decoration: BoxDecoration(
                            color: mine
                                ? const Color(0xFF2F6FFF)
                                : Colors.white,
                            borderRadius: BorderRadius.circular(18),
                            boxShadow: mine
                                ? null
                                : [
                                    BoxShadow(
                                      color: Colors.black.withValues(
                                        alpha: 0.04,
                                      ),
                                      blurRadius: 12,
                                      offset: const Offset(0, 4),
                                    ),
                                  ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                message.text,
                                style: TextStyle(
                                  color: mine
                                      ? Colors.white
                                      : const Color(0xFF0F172A),
                                  height: 1.4,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 6),
                              Text(
                                DateFormat('h:mm a').format(message.createdAt),
                                style: TextStyle(
                                  color: mine
                                      ? Colors.white70
                                      : const Color(0xFF94A3B8),
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                },
              ),
            ),
            Container(
              color: Colors.white,
              padding: EdgeInsets.fromLTRB(
                14, 10, 14,
                10 + MediaQuery.of(context).padding.bottom,
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _messageCtrl,
                      minLines: 1,
                      maxLines: 4,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: InputDecoration(
                        hintText: 'Type your message',
                        filled: true,
                        fillColor: const Color(0xFFF8FAFC),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(18),
                          borderSide: BorderSide.none,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 52,
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _sending ? null : _sendMessage,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF2F6FFF),
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                        elevation: 0,
                        padding: EdgeInsets.zero,
                      ),
                      child: _sending
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.3,
                              ),
                            )
                          : const Icon(Icons.send_rounded),
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
}

class _DriverConversationItem {
  const _DriverConversationItem({
    required this.id,
    required this.touristId,
    required this.bookingId,
    required this.lastMessage,
    required this.lastMessageAt,
    required this.touristName,
    required this.touristPhone,
    required this.touristAvatar,
  });

  final String id;
  final String touristId;
  final String bookingId;
  final String lastMessage;
  final DateTime? lastMessageAt;
  final String touristName;
  final String touristPhone;
  final String touristAvatar;
}

class _DriverMessage {
  const _DriverMessage({
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

class _DriverConversationCard extends StatelessWidget {
  const _DriverConversationCard({
    required this.conversation,
    required this.onTap,
  });

  final _DriverConversationItem conversation;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final subtitle = conversation.lastMessage.trim().isEmpty
        ? 'Tap to start chatting.'
        : conversation.lastMessage.trim();
    final timestamp = conversation.lastMessageAt == null
        ? ''
        : DateFormat('MMM d').format(conversation.lastMessageAt!);

    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(22),
      child: InkWell(
        borderRadius: BorderRadius.circular(22),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(22),
            border: Border.all(color: const Color(0xFFE7EEF7)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.04),
                blurRadius: 14,
                offset: const Offset(0, 5),
              ),
            ],
          ),
          child: Row(
            children: [
              _DriverChatAvatar(
                name: conversation.touristName,
                imageUrl: conversation.touristAvatar,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      conversation.touristName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF0F172A),
                        fontWeight: FontWeight.w900,
                        fontSize: 15,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Color(0xFF64748B),
                        fontWeight: FontWeight.w700,
                        height: 1.3,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (timestamp.isNotEmpty)
                    Text(
                      timestamp,
                      style: const TextStyle(
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w800,
                        fontSize: 11.5,
                      ),
                    ),
                  const SizedBox(height: 8),
                  const Icon(
                    Icons.chevron_right_rounded,
                    color: Color(0xFF94A3B8),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _DriverChatAvatar extends StatelessWidget {
  const _DriverChatAvatar({
    required this.name,
    required this.imageUrl,
    this.radius = 22,
  });

  final String name;
  final String imageUrl;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return CircleAvatar(
      radius: radius,
      backgroundColor: const Color(0xFFEAF2FF),
      backgroundImage: imageUrl.trim().isNotEmpty
          ? NetworkImage(imageUrl)
          : null,
      child: imageUrl.trim().isEmpty
          ? Text(
              name.trim().isEmpty ? 'T' : name.trim()[0].toUpperCase(),
              style: const TextStyle(
                color: Color(0xFF2F6FFF),
                fontWeight: FontWeight.w900,
              ),
            )
          : null,
    );
  }
}

class _DriverMessagesEmptyState extends StatelessWidget {
  const _DriverMessagesEmptyState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 74,
              height: 74,
              decoration: BoxDecoration(
                color: const Color(0xFFEAF2FF),
                borderRadius: BorderRadius.circular(24),
              ),
              child: const Icon(
                Icons.forum_outlined,
                color: Color(0xFF2F6FFF),
                size: 34,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'No conversations yet.',
              style: TextStyle(
                color: Color(0xFF0F172A),
                fontWeight: FontWeight.w900,
                fontSize: 18,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Tourist chats will appear here once you have assigned package bookings.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DriverMessagesErrorState extends StatelessWidget {
  const _DriverMessagesErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline_rounded,
              size: 40,
              color: Color(0xFFDC2626),
            ),
            const SizedBox(height: 12),
            Text(
              message,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: Color(0xFF64748B),
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 14),
            ElevatedButton(onPressed: onRetry, child: const Text('Retry')),
          ],
        ),
      ),
    );
  }
}
