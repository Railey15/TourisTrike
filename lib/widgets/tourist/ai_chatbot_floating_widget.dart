import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:http/http.dart' as http;

// ── System prompt ─────────────────────────────────────────────────────────────
const _kSystemPrompt =
    'You are TourisTrike AI Assistant. You help tourists explore municipalities, '
    'tourist destinations, packages, tricycle transportation, routes, and travel '
    'planning within Bulacan, Philippines. Only answer questions related to '
    'TourisTrike tourism and transportation. Give short, helpful, and friendly '
    'answers. If asked about anything unrelated to tourism, travel packages, '
    'tourist spots, routes, transportation, or TourisTrike, politely respond: '
    '"I can only assist with tourism, travel packages, tourist spots, routes, '
    'and transportation services within TourisTrike."';

const _kOffTopicReply =
    "I can only assist with tourism, travel packages, tourist spots, routes, "
    "and transportation services within TourisTrike.";

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
  });

  final String text;
  final bool isUser;
  final bool isError;
}

// ── Wrapper widget ─────────────────────────────────────────────────────────────
/// Wraps any tourist screen with the global AI chatbot FAB + sliding panel.
class TouristAiChatbotWrapper extends StatefulWidget {
  const TouristAiChatbotWrapper({super.key, required this.child});

  final Widget child;

  @override
  State<TouristAiChatbotWrapper> createState() =>
      _TouristAiChatbotWrapperState();
}

class _TouristAiChatbotWrapperState extends State<TouristAiChatbotWrapper>
    with SingleTickerProviderStateMixin {
  bool _chatOpen = false;
  late final AnimationController _slideCtrl;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _slideCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 1),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _slideCtrl, curve: Curves.easeOutCubic));
  }

  @override
  void dispose() {
    _slideCtrl.dispose();
    super.dispose();
  }

  void _openChat() {
    setState(() => _chatOpen = true);
    _slideCtrl.forward();
  }

  void _closeChat() {
    _slideCtrl.reverse().then((_) {
      if (mounted) setState(() => _chatOpen = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).padding.bottom;

    return Stack(
      children: [
        widget.child,

        // Backdrop
        if (_chatOpen)
          Positioned.fill(
            child: GestureDetector(
              onTap: _closeChat,
              child: Container(color: Colors.black.withValues(alpha: 0.42)),
            ),
          ),

        // Sliding chat panel
        if (_chatOpen)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: SlideTransition(
              position: _slideAnim,
              child: _AiChatPanel(onClose: _closeChat),
            ),
          ),

        // FAB (hidden when chat is open)
        if (!_chatOpen)
          Positioned(
            right: 18,
            bottom: 92 + bottomInset,
            child: _ChatFab(onTap: _openChat),
          ),
      ],
    );
  }
}

// ── Floating button ────────────────────────────────────────────────────────────
class _ChatFab extends StatelessWidget {
  const _ChatFab({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
          ),
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF2A86FF).withValues(alpha: 0.40),
              blurRadius: 18,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: const Icon(Icons.assistant_rounded, color: Colors.white, size: 26),
      ),
    );
  }
}

// ── Chat panel ─────────────────────────────────────────────────────────────────
class _AiChatPanel extends StatefulWidget {
  const _AiChatPanel({required this.onClose});
  final VoidCallback onClose;

  @override
  State<_AiChatPanel> createState() => _AiChatPanelState();
}

class _AiChatPanelState extends State<_AiChatPanel> {
  final _textCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  bool _thinking = false;

  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      text: "Hi! I'm your TourisTrike AI Assistant 👋\n\n"
          "Ask me about tourist spots, travel packages, tricycle routes, "
          "or anything about exploring Bulacan!",
      isUser: false,
    ),
  ];

  static const _geminiBase =
      'https://generativelanguage.googleapis.com/v1beta/models/'
      'gemini-2.0-flash:generateContent';

  @override
  void dispose() {
    _textCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
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
        _messages.add(const _ChatMessage(text: _kOffTopicReply, isUser: false));
        _thinking = false;
      });
      _scrollToBottom();
      return;
    }

    try {
      final apiKey = dotenv.env['GEMINI_API_KEY'] ?? '';
      if (apiKey.isEmpty) throw Exception('Gemini API key not configured.');

      // Build conversation history (last 10 exchanges for context window)
      final history = <Map<String, dynamic>>[];
      final src = _messages.length > 10
          ? _messages.sublist(_messages.length - 10)
          : _messages;
      for (final m in src) {
        history.add({
          'role': m.isUser ? 'user' : 'model',
          'parts': [
            {'text': m.text},
          ],
        });
      }

      final payload = jsonEncode({
        'system_instruction': {
          'parts': [
            {'text': _kSystemPrompt},
          ],
        },
        'contents': history,
        'generationConfig': {
          'temperature': 0.7,
          'maxOutputTokens': 512,
          'topP': 0.9,
        },
        'safetySettings': [
          {'category': 'HARM_CATEGORY_HARASSMENT', 'threshold': 'BLOCK_NONE'},
          {'category': 'HARM_CATEGORY_HATE_SPEECH', 'threshold': 'BLOCK_NONE'},
        ],
      });

      final res = await http
          .post(
            Uri.parse('$_geminiBase?key=$apiKey'),
            headers: {'Content-Type': 'application/json'},
            body: payload,
          )
          .timeout(const Duration(seconds: 25));

      if (res.statusCode == 200) {
        final json = jsonDecode(res.body) as Map<String, dynamic>;
        final candidates = (json['candidates'] as List?) ?? [];
        String reply = '';
        if (candidates.isNotEmpty) {
          final content = candidates.first['content'] as Map?;
          final parts = (content?['parts'] as List?) ?? [];
          reply = parts.isNotEmpty
              ? ((parts.first['text'] as String?) ?? '').trim()
              : '';
        }
        if (reply.isEmpty) reply = "Try asking about tourist spots, packages, or routes in Bulacan!";
        if (!mounted) return;
        setState(() {
          _messages.add(_ChatMessage(text: reply, isUser: false));
          _thinking = false;
        });
      } else {
        final errBody = jsonDecode(res.body) as Map?;
        final errMsg = errBody?['error']?['message'] as String? ??
            'Server error ${res.statusCode}';
        throw Exception(errMsg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _messages.add(
          _ChatMessage(
            text: 'Sorry, something went wrong. Please try again.',
            isUser: false,
            isError: true,
          ),
        );
        _thinking = false;
      });
    }

    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final screenH = MediaQuery.of(context).size.height;

    return Container(
      height: screenH * 0.80,
      decoration: const BoxDecoration(
        color: Color(0xFFF5F7FB),
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        children: [
          _buildDragHandle(),
          _buildHeader(),
          const Divider(height: 1, color: Color(0xFFE7EEF7)),
          Expanded(child: _buildMessagesList()),
          _buildInputBar(bottomInset),
        ],
      ),
    );
  }

  Widget _buildDragHandle() {
    return Padding(
      padding: const EdgeInsets.only(top: 10, bottom: 2),
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
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(13),
            ),
            child: const Icon(Icons.assistant_rounded,
                color: Colors.white, size: 22),
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
          // Online indicator
          Container(
            width: 8,
            height: 8,
            margin: const EdgeInsets.only(right: 6),
            decoration: const BoxDecoration(
              color: Color(0xFF22C55E),
              shape: BoxShape.circle,
            ),
          ),
          IconButton(
            onPressed: widget.onClose,
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
        return _MessageBubble(message: _messages[i]);
      },
    );
  }

  Widget _buildInputBar(double bottomInset) {
    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(16, 10, 16, 12 + bottomInset),
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
                controller: _textCtrl,
                maxLines: 4,
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
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 16, vertical: 12),
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
                          color: const Color(0xFF2A86FF).withValues(alpha: 0.30),
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
                  : const Icon(Icons.send_rounded,
                      color: Colors.white, size: 20),
            ),
          ),
        ],
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
        constraints:
            BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.80),
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
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [Color(0xFF5BB2FF), Color(0xFF2A86FF)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: const Icon(Icons.assistant_rounded,
                    color: Colors.white, size: 15),
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

// ── Typing indicator (animated dots) ──────────────────────────────────────────
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
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
                final opacity =
                    (0.5 + 0.5 * math.sin(phase * 2 * math.pi)).clamp(
                  0.2,
                  1.0,
                );
                return Container(
                  margin: EdgeInsets.only(right: i < 2 ? 5 : 0),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color:
                        Color.fromRGBO(42, 134, 255, opacity),
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
