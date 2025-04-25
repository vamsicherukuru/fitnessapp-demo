// lib/screens/group_chat_screen.dart
//
// Deps: cloud_firestore, firebase_auth, intl
// ──────────────────────────────────────────────────────────────
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/*────────────────── group chat screen ──────────────────*/
class GroupChatScreen extends StatefulWidget {
  final String chatId; // chats/<id>
  final String name; // group name

  const GroupChatScreen({Key? key, required this.chatId, required this.name})
    : super(key: key);

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

/*────────────────────────────────────────────────────────*/
class _GroupChatScreenState extends State<GroupChatScreen> {
  /* basics */
  final _me = FirebaseAuth.instance.currentUser!.uid;
  final _msgC = TextEditingController();
  final _scrollC = ScrollController();

  /* once  */
  bool _didInitialJump = false;
  List<DocumentSnapshot> _cached = [];

  /* banners / edit */
  Map<String, dynamic>? _reply;
  String? _editingId;

  /* tiny user cache */
  final _uCache = <String, Map<String, dynamic>>{};

  /* state */
  bool _amAdmin = false;
  List<String> _participants = [];

  @override
  void initState() {
    super.initState();
    _primeCache();
    _listenHeader();
  }

  @override
  void dispose() {
    _msgC.dispose();
    super.dispose();
  }

  /*──────── prime first 40 msgs for cold-start ────────*/
  Future<void> _primeCache() async {
    final snap =
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(40)
            .get();
    setState(() => _cached = snap.docs);
  }

  /*──────── listen admins / participants ─────────────*/
  void _listenHeader() {
    FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .snapshots()
        .listen((d) {
          final m = d.data() ?? {};
          final admins = List<String>.from(m['admins'] ?? []);
          final participants = List<String>.from(m['participants'] ?? []);
          if (mounted) {
            setState(() {
              _amAdmin = admins.contains(_me);
              _participants = participants;
            });
          }
        });
  }

  /*──────── helpers ─────────────*/
  void _jumpBottom() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (_scrollC.hasClients) _scrollC.jumpTo(0);
  });

  Future<Map<String, dynamic>> _getUser(String uid) async {
    if (_uCache.containsKey(uid)) return _uCache[uid]!;
    final d =
        (await FirebaseFirestore.instance.collection('users').doc(uid).get())
            .data()!;
    _uCache[uid] = d;
    return d;
  }

  String _initials(String n) {
    final p = n.trim().split(RegExp(r'\s+'));
    return p.length == 1
        ? p[0][0].toUpperCase()
        : (p[0][0] + p[1][0]).toUpperCase();
  }

  /* nice pastel colour based on uid */
  Color _colourFor(String uid) {
    final h = uid.codeUnits.fold<int>(0, (p, c) => p + c);
    final hue = (h * 37) % 360; // pseudo-random but stable
    return HSLColor.fromAHSL(1, hue.toDouble(), 0.45, 0.75).toColor();
  }

  /*──────── send / edit / delete ─────────────*/
  Future<void> _send() async {
    final txt = _msgC.text.trim();
    if (txt.isEmpty) return;

    /* edit */
    if (_editingId != null) {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .doc(_editingId!)
          .update({'text': txt, 'edited': true, 'editedAt': Timestamp.now()});
      setState(() => _editingId = null);
      _msgC.clear();
      return;
    }

    final chatDoc = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId);

    await chatDoc.set({
      'lastMessage': txt,
      'lastSenderId': _me,
      'lastTimestamp': Timestamp.now(),
    }, SetOptions(merge: true));

    await chatDoc.collection('messages').add({
      'senderId': _me,
      'text': txt,
      'timestamp': Timestamp.now(),
      'type': 'text',
      if (_reply != null) 'replyTo': _reply,
    });

    _msgC.clear();
    setState(() => _reply = null);
    _jumpBottom();
  }

  Future<void> _deleteMessage(String id) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .collection('messages')
        .doc(id)
        .update({
          'type': 'deleted',
          'text': '💬 message deleted',
          'deletedAt': Timestamp.now(),
        });
  }

  /*──────── Add-members sheet ─────────────*/
  void _openAddMembers() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final pick = <String>{};
        String q = '';

        Future<List<Map<String, dynamic>>> _friendsNotInGroup() async {
          final meDoc =
              await FirebaseFirestore.instance
                  .collection('users')
                  .doc(_me)
                  .get();
          final friends = List<String>.from(meDoc['friends'] ?? []);
          final remaining =
              friends.where((f) => !_participants.contains(f)).toList();

          final List<Map<String, dynamic>> out = [];
          for (final uid in remaining) {
            final u = await _getUser(uid);
            out.add({'uid': uid, 'username': u['username']});
          }
          return out;
        }

        return FutureBuilder<List<Map<String, dynamic>>>(
          future: _friendsNotInGroup(),
          builder: (_, snap) {
            final list =
                (snap.data ?? [])
                    .where(
                      (e) =>
                          e['username'].toLowerCase().contains(q.toLowerCase()),
                    )
                    .toList();

            return StatefulBuilder(
              builder:
                  (_, setLocal) => Padding(
                    padding: MediaQuery.of(ctx).viewInsets,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(height: 12),
                        Container(
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: Colors.grey[400],
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        const SizedBox(height: 16),
                        const Text(
                          'Add members',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: TextField(
                            decoration: const InputDecoration(
                              prefixIcon: Icon(Icons.search),
                              hintText: 'Search friends',
                            ),
                            onChanged: (v) => setLocal(() => q = v),
                          ),
                        ),
                        SizedBox(
                          height: math.min(list.length * 56 + 10, 300),
                          child: ListView.builder(
                            itemCount: list.length,
                            itemBuilder: (_, i) {
                              final u = list[i];
                              final uid = u['uid'];
                              final checked = pick.contains(uid);
                              return CheckboxListTile(
                                value: checked,
                                dense: true,
                                title: Text('@${u['username']}'),
                                controlAffinity:
                                    ListTileControlAffinity.leading,
                                onChanged:
                                    (v) => setLocal(
                                      () =>
                                          v! ? pick.add(uid) : pick.remove(uid),
                                    ),
                              );
                            },
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(16),
                          child: ElevatedButton.icon(
                            icon: const Icon(Icons.person_add),
                            label: const Text('Add'),
                            style: ElevatedButton.styleFrom(
                              minimumSize: const Size.fromHeight(44),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            onPressed:
                                pick.isEmpty
                                    ? null
                                    : () async {
                                      /* update participants + typing map */
                                      final chat = FirebaseFirestore.instance
                                          .collection('chats')
                                          .doc(widget.chatId);
                                      await chat.update({
                                        'participants': FieldValue.arrayUnion(
                                          pick.toList(),
                                        ),
                                        'typing': {
                                          for (final p in pick) p: false,
                                        },
                                      });

                                      /* system message */
                                      final names = await Future.wait(
                                        pick.map(
                                          (uid) async =>
                                              (await _getUser(uid))['username'],
                                        ),
                                      );
                                      final actor =
                                          (await _getUser(_me))['username'];
                                      final txt =
                                          '$actor added ${names.join(', ')}';

                                      await chat.collection('messages').add({
                                        'type': 'system',
                                        'text': txt,
                                        'timestamp': Timestamp.now(),
                                      });

                                      if (mounted) Navigator.pop(ctx);
                                    },
                          ),
                        ),
                        const SizedBox(height: 16),
                      ],
                    ),
                  ),
            );
          },
        );
      },
    );
  }

  /*──────── build ─────────────*/
  @override
  Widget build(BuildContext context) {
    final inputBar = _InputBar(
      controller: _msgC,
      onSend: _send,
      reply: _reply,
      onCancelReply: () => setState(() => _reply = null),
      isEditing: _editingId != null,
      onCancelEdit:
          () => setState(() {
            _editingId = null;
            _msgC.clear();
          }),
    );

    return Scaffold(
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
        titleSpacing: 0,
        title: Row(
          children: [
            const CircleAvatar(
              radius: 20,
              backgroundColor: Color(0xFFB2DFDB),
              child: Icon(Icons.group, color: Colors.teal),
            ),
            const SizedBox(width: 10),
            Text(
              widget.name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.black,
              ),
            ),
          ],
        ),
        actions: [
          if (_amAdmin)
            IconButton(
              tooltip: 'Add members',
              icon: const Icon(Icons.person_add_alt_1_outlined),
              onPressed: _openAddMembers,
            ),
        ],
      ),
      body: Column(
        children: [
          /*──────── messages list ────────*/
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
              builder: (_, snap) {
                final docs = snap.hasData ? snap.data!.docs : _cached;

                if (!_didInitialJump && docs.isNotEmpty) {
                  _didInitialJump = true;
                  _jumpBottom();
                }

                return ListView.builder(
                  controller: _scrollC,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final id = docs[i].id;
                    final m = docs[i].data()! as Map<String, dynamic>;
                    final me = m['senderId'] == _me;
                    final type = m['type'] ?? 'text';

                    if (type == 'system') return _SystemStrip(text: m['text']);

                    return FutureBuilder<Map<String, dynamic>>(
                      future: me ? Future.value({}) : _getUser(m['senderId']),
                      builder: (_, usnap) {
                        final user = usnap.data ?? {};
                        return _GroupBubble(
                          id: id,
                          me: me,
                          map: m,
                          name: user['username'] ?? '',
                          colour: _colourFor(m['senderId']),
                          initials:
                              me ? '' : _initials(user['username'] ?? '?'),
                          onSlideReply:
                              () => setState(
                                () =>
                                    _reply = {
                                      'text': m['text'],
                                      'senderId': m['senderId'],
                                      'senderName': user['username'] ?? '',
                                    },
                              ),
                          onLongPressEditDelete:
                              me && type != 'deleted'
                                  ? (pos) async {
                                    final sel = await showMenu<String>(
                                      context: context,
                                      position: RelativeRect.fromLTRB(
                                        pos.dx,
                                        pos.dy,
                                        pos.dx,
                                        pos.dy,
                                      ),
                                      items: const [
                                        PopupMenuItem(
                                          value: 'edit',
                                          child: Text('Edit'),
                                        ),
                                        PopupMenuItem(
                                          value: 'del',
                                          child: Text('Delete'),
                                        ),
                                      ],
                                    );
                                    if (sel == 'edit') {
                                      setState(() {
                                        _editingId = id;
                                        _msgC.text = m['text'];
                                      });
                                    } else if (sel == 'del') {
                                      _deleteMessage(id);
                                    }
                                  }
                                  : null,
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),

          /*──────── input bar ────────*/
          inputBar,
        ],
      ),
    );
  }
}

/*────────────────── centred grey strip ───────────────*/
class _SystemStrip extends StatelessWidget {
  final String text;
  const _SystemStrip({required this.text});
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 10),
    child: Center(
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(
            text,
            style: const TextStyle(fontSize: 12, color: Colors.black54),
          ),
        ),
      ),
    ),
  );
}

/*────────────────── one bubble ───────────────────────*/
class _GroupBubble extends StatefulWidget {
  const _GroupBubble({
    required this.id,
    required this.me,
    required this.map,
    required this.name,
    required this.initials,
    required this.colour,
    required this.onSlideReply,
    this.onLongPressEditDelete,
  });

  final String id;
  final bool me;
  final Map<String, dynamic> map;
  final String name, initials;
  final Color colour;
  final VoidCallback onSlideReply;
  final Future<void> Function(Offset globalPos)? onLongPressEditDelete;

  @override
  State<_GroupBubble> createState() => _GroupBubbleState();
}

class _GroupBubbleState extends State<_GroupBubble>
    with SingleTickerProviderStateMixin {
  double _dx = 0;
  late final AnimationController _spring = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 250),
  );

  void _snapBack() => _spring.forward(from: 0);

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  String _fmt(Timestamp ts) => DateFormat('h:mm a').format(ts.toDate());

  @override
  Widget build(BuildContext context) {
    final m = widget.map;
    final ts = m['timestamp'] as Timestamp;
    final type = m['type'] ?? 'text';
    final me = widget.me;

    final meta = Text(
      _fmt(ts),
      style: const TextStyle(fontSize: 10, color: Colors.grey),
    );

    final bubbleColour =
        type == 'deleted'
            ? Colors.grey.shade300
            : me
            ? const Color(0xFFD2F5E3)
            : Colors.white;

    final bubble = Column(
      crossAxisAlignment:
          me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (!me) ...[
          Row(
            children: [
              CircleAvatar(
                radius: 10,
                backgroundColor: widget.colour,
                child: Text(
                  widget.initials,
                  style: const TextStyle(fontSize: 10, color: Colors.white),
                ),
              ),
              const SizedBox(width: 6),
              Text(
                widget.name,
                style: const TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
        if (m['replyTo'] != null)
          Container(
            margin: const EdgeInsets.only(bottom: 4),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.blue.shade100,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              m['replyTo']['text'],
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12, color: Colors.black54),
            ),
          ),
        DecoratedBox(
          decoration: BoxDecoration(
            color: bubbleColour,
            border: Border.all(color: Colors.grey.shade300),
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(me ? 18 : 6),
              bottomRight: Radius.circular(me ? 6 : 18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              m['text'],
              style: TextStyle(
                fontSize: 15,
                fontStyle:
                    type == 'deleted' ? FontStyle.italic : FontStyle.normal,
                color: type == 'deleted' ? Colors.grey.shade600 : Colors.black,
              ),
            ),
          ),
        ),
        meta,
      ],
    );

    return GestureDetector(
      onHorizontalDragStart: (_) => _spring.stop(),
      onHorizontalDragUpdate:
          (d) => setState(() {
            _dx += d.delta.dx;
            _dx = me ? _dx.clamp(-90, 0) : _dx.clamp(0, 90);
          }),
      onHorizontalDragEnd: (_) {
        if (_dx.abs() > 60) widget.onSlideReply();
        _snapBack();
        _dx = 0;
      },
      onLongPressStart: (details) async {
        if (widget.onLongPressEditDelete != null) {
          await widget.onLongPressEditDelete!(details.globalPosition);
        }
      },
      child: AnimatedBuilder(
        animation: _spring,
        builder:
            (_, __) => Transform.translate(
              offset: Offset(_dx * (1 - _spring.value), 0),
              child: _Entrance(fromRight: me, child: bubble),
            ),
      ),
    );
  }
}

/*──────── fancy entrance (slide + scale + fade) ───────*/
class _Entrance extends StatelessWidget {
  final bool fromRight;
  final Widget child;
  const _Entrance({required this.fromRight, required this.child});

  @override
  Widget build(BuildContext context) => TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: const Duration(milliseconds: 450),
    curve: Curves.easeOutBack,
    builder:
        (_, v, c) => Opacity(
          opacity: v.clamp(0.0, 1.0), // ← add clamp here
          child: Transform.translate(
            offset: Offset((fromRight ? 1 : -1) * 40 * (1 - v), 0),
            child: Transform.scale(scale: .8 + .2 * v, child: c),
          ),
        ),
    child: child,
  );
}

/*──────── input bar (banner + field) ───────*/
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.reply,
    required this.onCancelReply,
    required this.isEditing,
    required this.onCancelEdit,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final Map<String, dynamic>? reply;
  final VoidCallback onCancelReply;
  final bool isEditing;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      AnimatedSwitcher(
        duration: const Duration(milliseconds: 200),
        child:
            reply != null
                ? _Banner(
                  key: const ValueKey('reply'),
                  text: reply!['text'],
                  label: 'Reply → ${reply!['senderName'] ?? ''}',
                  colour: Colors.blue,
                  onClose: onCancelReply,
                )
                : isEditing
                ? _Banner(
                  key: const ValueKey('edit'),
                  text: 'Editing message',
                  label: 'Edit',
                  colour: Colors.orange,
                  onClose: onCancelEdit,
                )
                : const SizedBox.shrink(key: ValueKey('none')),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(28),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(.05),
                blurRadius: 8,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              const SizedBox(width: 14),
              const Icon(Icons.emoji_emotions_outlined, color: Colors.grey),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 6,
                  decoration: const InputDecoration(
                    hintText: 'Message…',
                    border: InputBorder.none,
                  ),
                ),
              ),
              IconButton(
                icon: Transform.rotate(
                  angle: -math.pi / 18,
                  child: const Icon(
                    Icons.send_rounded,
                    color: Color(0xFF0F9D58),
                  ),
                ),
                onPressed: onSend,
              ),
            ],
          ),
        ),
      ),
    ],
  );
}

class _Banner extends StatelessWidget {
  const _Banner({
    Key? key,
    required this.text,
    required this.label,
    required this.colour,
    required this.onClose,
  }) : super(key: key);

  final String text, label;
  final Color colour;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) => Material(
    color: colour.withOpacity(.15),
    child: ListTile(
      dense: true,
      leading: CircleAvatar(
        radius: 10,
        backgroundColor: colour,
        child: Text(
          label[0],
          style: const TextStyle(fontSize: 12, color: Colors.white),
        ),
      ),
      title: Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 13),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18),
        onPressed: onClose,
      ),
    ),
  );
}
