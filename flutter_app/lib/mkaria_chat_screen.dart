import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'api_client.dart';
import 'mkaria_chat_service.dart';
import 'models.dart';

class MkariaChatScreen extends StatefulWidget {
  const MkariaChatScreen({
    this.apiClient,
    this.fixtureId,
    this.userId,
    super.key,
  });

  final ApiClient? apiClient;
  final String? fixtureId;
  final String? userId;

  @override
  State<MkariaChatScreen> createState() => _MkariaChatScreenState();
}

class _MkariaChatScreenState extends State<MkariaChatScreen> {
  static const _suggestions = [
    "Analyze today's live matches",
    'Generate a cautious 2-pick betslip',
    'Find matches by date, time, league, and country',
  ];

  late final MkariaChatService _chat;
  final _controller = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [
    const _ChatMessage(
      role: _ChatRole.assistant,
      text:
          "Hi, I'm Mkamaria AI. I can analyze live matches and fixtures in the next three days by date, time, league, and country. I won't invent odds or promise outcomes.",
    ),
  ];
  final List<MkariaConversationSummary> _conversations = [];
  String? _conversationId;
  bool _loadingConversations = false;
  bool _drawerOpen = false;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _chat = MkariaChatService(widget.apiClient ?? ApiClient());
    if (widget.userId != null) _loadConversations();
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _send([String? suggestion]) async {
    final text = (suggestion ?? _controller.text).trim();
    if (text.isEmpty || _sending) return;
    final history = _messages
        .where((message) => !message.isError)
        .toList()
        .reversed
        .take(10)
        .toList()
        .reversed
        .map((message) => {
              'role': message.role == _ChatRole.user ? 'user' : 'assistant',
              'content': message.text,
            })
        .toList();

    setState(() {
      _messages.add(_ChatMessage(role: _ChatRole.user, text: text));
      _sending = true;
      _controller.clear();
    });
    _scrollToLatest();

    try {
      final response = await _chat.sendMessage(
        message: text,
        history: history,
        fixtureId: widget.fixtureId,
        conversationId: _conversationId,
      );
      if (!mounted) return;
      setState(() {
        _conversationId = response.conversationId ?? _conversationId;
        _messages.add(_ChatMessage(
          role: _ChatRole.assistant,
          text: response.reply,
          betslip: response.betslip,
        ));
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _messages.add(_ChatMessage(
          role: _ChatRole.assistant,
          text: error.message,
          isError: true,
        ));
      });
    } finally {
      if (mounted) {
        setState(() => _sending = false);
        _scrollToLatest();
        _loadConversations();
      }
    }
  }

  Future<void> _loadConversations() async {
    if (widget.userId == null) return;
    if (_loadingConversations) return;
    setState(() => _loadingConversations = true);
    try {
      final conversations = await _chat.fetchConversations();
      if (!mounted) return;
      setState(() {
        _conversations
          ..clear()
          ..addAll(conversations);
      });
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    } finally {
      if (mounted) setState(() => _loadingConversations = false);
    }
  }

  void _startNewChat() {
    if (_drawerOpen) Navigator.of(context).pop();
    setState(() {
      _conversationId = null;
      _messages
        ..clear()
        ..add(const _ChatMessage(
          role: _ChatRole.assistant,
          text:
              "Hi, I'm Mkamaria AI. I can analyze live matches and fixtures in the next three days by date, time, league, and country. I won't invent odds or promise outcomes.",
        ));
    });
    _scrollToLatest();
  }

  Future<void> _openConversation(MkariaConversationSummary summary) async {
    if (_drawerOpen) Navigator.of(context).pop();
    try {
      final conversation = await _chat.fetchConversation(summary.id);
      if (!mounted) return;
      setState(() {
        _conversationId = conversation.id;
        _messages
          ..clear()
          ..addAll(conversation.messages.map((message) => _ChatMessage(
                role: message.role == 'user'
                    ? _ChatRole.user
                    : _ChatRole.assistant,
                text: message.content,
                betslip: message.betslip,
              )));
      });
      _scrollToLatest();
    } on ApiException catch (error) {
      if (mounted) _showMessage(error.message);
    }
  }

  void _scrollToLatest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 320),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<void> _copySlip(MkariaBetslip slip) async {
    await Clipboard.setData(ClipboardData(text: _formatSlip(slip)));
    if (mounted) _showMessage('Betslip copied.');
  }

  Future<void> _saveSlip(MkariaBetslip slip) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final slips = preferences.getStringList('mkaria_saved_slips') ?? [];
      slips.insert(
        0,
        jsonEncode({
          'savedAt': DateTime.now().toIso8601String(),
          ...slip.toJson(),
        }),
      );
      await preferences.setStringList(
        'mkaria_saved_slips',
        slips.take(20).toList(),
      );
      if (mounted) _showMessage('Betslip saved on this device.');
    } catch (error) {
      if (mounted) _showMessage('Could not save this betslip: $error');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: scheme.surface,
      appBar: AppBar(
        backgroundColor: scheme.surface,
        titleSpacing: 4,
        leading: Builder(
          builder: (context) => IconButton(
            tooltip: 'Chat history',
            icon: const Icon(Icons.menu_rounded),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(14),
                border:
                    Border.all(color: scheme.primary.withValues(alpha: .42)),
              ),
              child: Icon(Icons.auto_awesome, color: scheme.primary),
            ),
            const SizedBox(width: 11),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Mkamaria AI',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 17),
                ),
                SizedBox(height: 2),
                Row(
                  children: [
                    Icon(Icons.circle, size: 7, color: scheme.primary),
                    SizedBox(width: 5),
                    Text(
                      'FOOTBALL ANALYST',
                      style: TextStyle(
                        color: scheme.onSurfaceVariant,
                        fontSize: 9,
                        letterSpacing: 1.1,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'New Chat',
            onPressed: _sending ? null : _startNewChat,
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 18, 18, 12),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, color: scheme.primary),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Chat history',
                        style: TextStyle(
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    IconButton(
                      tooltip: 'Refresh history',
                      onPressed: _loadConversations,
                      icon: const Icon(Icons.refresh),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: FilledButton.icon(
                  onPressed: _sending ? null : _startNewChat,
                  icon: const Icon(Icons.add),
                  label: const Text('New Chat'),
                ),
              ),
              const SizedBox(height: 12),
              if (_loadingConversations && _conversations.isEmpty)
                const LinearProgressIndicator(),
              Expanded(
                child: _conversations.isEmpty
                    ? Center(
                        child: Text(
                          _loadingConversations
                              ? 'Loading conversations…'
                              : 'Your conversations will appear here.',
                          style: TextStyle(color: scheme.onSurfaceVariant),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : ListView.builder(
                        itemCount: _conversations.length,
                        itemBuilder: (context, index) {
                          final conversation = _conversations[index];
                          final selected = conversation.id == _conversationId;
                          return ListTile(
                            selected: selected,
                            selectedTileColor:
                                scheme.primary.withValues(alpha: .1),
                            leading: Icon(
                              Icons.chat_bubble_outline_rounded,
                              color: selected
                                  ? scheme.primary
                                  : scheme.onSurfaceVariant,
                            ),
                            title: Text(
                              conversation.title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            subtitle: conversation.lastMessage == null
                                ? null
                                : Text(
                                    conversation.lastMessage!,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                            onTap: () => _openConversation(conversation),
                          );
                        },
                      ),
              ),
            ],
          ),
        ),
      ),
      onDrawerChanged: (isOpen) => _drawerOpen = isOpen,
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 18),
                itemCount: _messages.length + (_sending ? 1 : 0),
                itemBuilder: (context, index) {
                  if (index == _messages.length) {
                    return const _TypingIndicator();
                  }
                  final message = _messages[index];
                  return _MessageBubble(
                    message: message,
                    onCopySlip: message.betslip == null
                        ? null
                        : () => _copySlip(message.betslip!),
                    onSaveSlip: message.betslip == null
                        ? null
                        : () => _saveSlip(message.betslip!),
                  );
                },
              ),
            ),
            _SuggestionChips(
              suggestions: _suggestions,
              enabled: !_sending,
              onSelected: (suggestion) => _send(suggestion),
            ),
            _ChatComposer(
              controller: _controller,
              sending: _sending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}

enum _ChatRole { user, assistant }

class _ChatMessage {
  const _ChatMessage({
    required this.role,
    required this.text,
    this.betslip,
    this.isError = false,
  });

  final _ChatRole role;
  final String text;
  final MkariaBetslip? betslip;
  final bool isError;
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.message,
    this.onCopySlip,
    this.onSaveSlip,
  });

  final _ChatMessage message;
  final VoidCallback? onCopySlip;
  final VoidCallback? onSaveSlip;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isUser = message.role == _ChatRole.user;
    final bubbleColor = message.isError
        ? scheme.errorContainer
        : isUser
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final textColor = isUser ? scheme.onPrimaryContainer : scheme.onSurface;
    return Padding(
      padding: const EdgeInsets.only(bottom: 15),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 8, top: 3),
              decoration: BoxDecoration(
                color: scheme.primary.withValues(alpha: .12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(Icons.auto_awesome, size: 17, color: scheme.primary),
            ),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment:
                  isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
              children: [
                Container(
                  constraints: const BoxConstraints(maxWidth: 340),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 15, vertical: 12),
                  decoration: BoxDecoration(
                    color: bubbleColor,
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(18),
                      topRight: const Radius.circular(18),
                      bottomLeft: Radius.circular(isUser ? 18 : 5),
                      bottomRight: Radius.circular(isUser ? 5 : 18),
                    ),
                    border: isUser || message.isError
                        ? null
                        : Border.all(
                            color: scheme.primary.withValues(alpha: .13)),
                  ),
                  child: Text(
                    message.text,
                    style: TextStyle(
                      color:
                          message.isError ? scheme.onErrorContainer : textColor,
                      height: 1.45,
                      fontSize: 14,
                    ),
                  ),
                ),
                if (message.betslip case final slip?) ...[
                  const SizedBox(height: 10),
                  BetslipCard(
                    slip: slip,
                    onCopy: onCopySlip!,
                    onSave: onSaveSlip!,
                  ),
                ],
              ],
            ),
          ),
          if (isUser) const SizedBox(width: 38),
        ],
      ),
    );
  }
}

class BetslipCard extends StatelessWidget {
  const BetslipCard({
    required this.slip,
    required this.onCopy,
    required this.onSave,
    super.key,
  });

  final MkariaBetslip slip;
  final VoidCallback onCopy;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(maxWidth: 380),
      padding: const EdgeInsets.all(15),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [scheme.surfaceContainerHighest, scheme.surface],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: .42)),
        boxShadow: [
          BoxShadow(
            color: scheme.primary.withValues(alpha: .07),
            blurRadius: 22,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.receipt_long, color: scheme.primary, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'MKAMARIA BETSLIP',
                  style: TextStyle(
                    color: scheme.primary,
                    fontSize: 11,
                    letterSpacing: 1.1,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              _RiskPill(risk: slip.overallRisk),
            ],
          ),
          const SizedBox(height: 14),
          for (var index = 0; index < slip.picks.length; index++) ...[
            if (index > 0) Divider(height: 18, color: scheme.outlineVariant),
            _PickRow(pick: slip.picks[index]),
          ],
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Combined odds',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
              ),
              Text(
                slip.combinedOdds == null
                    ? 'Not available'
                    : slip.combinedOdds!.toStringAsFixed(2),
                style: TextStyle(
                  color: scheme.onSurface,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 11),
          Text(
            slip.note,
            style: TextStyle(
              color: scheme.onSurfaceVariant,
              fontSize: 11,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 13),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCopy,
                  icon: const Icon(Icons.copy_rounded, size: 16),
                  label: const Text('Copy slip'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: scheme.primary,
                    side:
                        BorderSide(color: scheme.primary.withValues(alpha: .5)),
                  ),
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: FilledButton.icon(
                  onPressed: onSave,
                  icon: const Icon(Icons.bookmark_add_outlined, size: 17),
                  label: const Text('Save'),
                  style: FilledButton.styleFrom(
                    backgroundColor: scheme.primary,
                    foregroundColor: scheme.onPrimary,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PickRow extends StatelessWidget {
  const _PickRow({required this.pick});

  final MkariaBetPick pick;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 27,
          height: 27,
          decoration: BoxDecoration(
            color: scheme.primary.withValues(alpha: .12),
            borderRadius: BorderRadius.circular(9),
          ),
          child: Icon(Icons.sports_soccer, size: 15, color: scheme.primary),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                pick.match,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 3),
              Text(
                pick.market,
                style: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 11,
                ),
              ),
              if (pick.confidence != null) ...[
                const SizedBox(height: 6),
                Text(
                  'Model confidence: ${pick.confidence}%',
                  style: TextStyle(color: scheme.primary, fontSize: 10),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 6),
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              pick.odds == null ? '—' : pick.odds!.toStringAsFixed(2),
              style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
            const SizedBox(height: 4),
            _RiskPill(risk: pick.risk),
          ],
        ),
      ],
    );
  }
}

class _RiskPill extends StatelessWidget {
  const _RiskPill({required this.risk});

  final String risk;

  @override
  Widget build(BuildContext context) {
    final color = switch (risk.toLowerCase()) {
      'low' => const Color(0xFF61DDAA),
      'high' => const Color(0xFFFF8191),
      _ => const Color(0xFFFFC56D),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .12),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        risk.toUpperCase(),
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w800,
          fontSize: 8,
          letterSpacing: .5,
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatefulWidget {
  const _TypingIndicator();

  @override
  State<_TypingIndicator> createState() => _TypingIndicatorState();
}

class _TypingIndicatorState extends State<_TypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _animation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: .12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(Icons.auto_awesome, size: 17, color: scheme.primary),
          ),
          const SizedBox(width: 8),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 10),
            decoration: BoxDecoration(
              color: scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Text(
                  'Mkamaria AI is analyzing',
                  style: TextStyle(
                    color: scheme.onSurfaceVariant,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(width: 6),
                for (var index = 0; index < 3; index++)
                  AnimatedBuilder(
                    animation: _animation,
                    builder: (context, child) {
                      final progress = (_animation.value + index / 3) % 1;
                      final opacity =
                          .25 + .75 * (1 - (progress - .5).abs() * 2);
                      return Padding(
                        padding: const EdgeInsets.only(right: 2),
                        child: Opacity(
                          opacity: opacity.clamp(0.0, 1.0).toDouble(),
                          child: Text(
                            '.',
                            style: TextStyle(
                              color: scheme.primary,
                              fontWeight: FontWeight.w900,
                              fontSize: 17,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SuggestionChips extends StatelessWidget {
  const _SuggestionChips({
    required this.suggestions,
    required this.enabled,
    required this.onSelected,
  });

  final List<String> suggestions;
  final bool enabled;
  final ValueChanged<String> onSelected;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 46,
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
          scrollDirection: Axis.horizontal,
          itemCount: suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (context, index) => ActionChip(
            onPressed: enabled ? () => onSelected(suggestions[index]) : null,
            backgroundColor:
                Theme.of(context).colorScheme.surfaceContainerHighest,
            side: BorderSide(
              color: Theme.of(context).colorScheme.outlineVariant,
            ),
            label: Text(
              suggestions[index],
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurface,
                fontSize: 11,
              ),
            ),
          ),
        ),
      );
}

class _ChatComposer extends StatelessWidget {
  const _ChatComposer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: EdgeInsets.fromLTRB(
        14,
        8,
        14,
        10 + MediaQuery.paddingOf(context).bottom,
      ),
      decoration: BoxDecoration(
        color: scheme.surface,
        border: Border(
          top: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              onSubmitted: (_) => onSend(),
              style: TextStyle(color: scheme.onSurface, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'Ask about form, goals or card risk...',
                hintStyle: TextStyle(
                  color: scheme.onSurfaceVariant,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: scheme.surfaceContainerHighest,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: scheme.outlineVariant),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(22),
                  borderSide: BorderSide(color: scheme.primary),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            width: 48,
            height: 48,
            child: FilledButton(
              onPressed: sending ? null : onSend,
              style: FilledButton.styleFrom(
                backgroundColor: scheme.primary,
                foregroundColor: scheme.onPrimary,
                padding: EdgeInsets.zero,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(17),
                ),
              ),
              child: sending
                  ? SizedBox(
                      width: 19,
                      height: 19,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: scheme.onPrimary,
                      ),
                    )
                  : const Icon(Icons.arrow_upward_rounded),
            ),
          ),
        ],
      ),
    );
  }
}

String _formatSlip(MkariaBetslip slip) {
  final lines = <String>['Mkamaria AI betslip'];
  for (final pick in slip.picks) {
    final odds =
        pick.odds == null ? 'odds unavailable' : pick.odds!.toStringAsFixed(2);
    lines.add('${pick.match}: ${pick.market} ($odds, ${pick.risk} risk)');
  }
  lines.add(
      'Combined odds: ${slip.combinedOdds?.toStringAsFixed(2) ?? 'unavailable'}');
  lines.add(slip.note);
  return lines.join('\n');
}
