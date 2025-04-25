// lib/screens/chat_screen.dart
//
// Deps: cloud_firestore, firebase_auth, intl
// (optionally: firebase_messaging somewhere else in the app)

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

/*──────────────────────────────────────────────────────────────*/
class ChatScreen extends StatefulWidget {
  final String name, uid;
  const ChatScreen({required this.name, required this.uid, Key? key})
    : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

/*──────────────────────────────────────────────────────────────*/
class _ChatScreenState extends State<ChatScreen> {
  /* ── core state ── */
  final String _me = FirebaseAuth.instance.currentUser!.uid;
  late final String _chatId;

  final _msgC = TextEditingController();
  final _scrollC = ScrollController();

  List<DocumentSnapshot> _cached = []; // for 1st paint before stream

  /* extra state (reply / edit banners) */
  Map<String, dynamic>? _reply; // {text:, senderId:}
  String? _editingId;

  /*───────────────────────── init / dispose ─────────────────────────*/
  @override
  void initState() {
    super.initState();
    _chatId =
        (_me.compareTo(widget.uid) < 0)
            ? '$_me-${widget.uid}'
            : '${widget.uid}-$_me';
    _primeCache();
  }

  @override
  void dispose() {
    _msgC.dispose();
    _setTyping(false);
    super.dispose();
  }

  Future<void> _primeCache() async {
    final snap =
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .limit(40)
            .get();
    setState(() => _cached = snap.docs);
  }

  /*───────────────────────── helpers ─────────────────────────*/
  void _setTyping(bool isTyping) {
    FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
      'typing': {_me: isTyping},
    }, SetOptions(merge: true));
  }

  void _jumpBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollC.hasClients) _scrollC.jumpTo(0); // list is reversed
    });
  }

  String _initials(String n) {
    final parts = n.trim().split(RegExp(r'\s+'));
    return parts.length == 1
        ? parts[0][0].toUpperCase()
        : (parts[0][0] + parts[1][0]).toUpperCase();
  }

  /*────────────────────── send / edit / delete ─────────────────────*/
  Future<void> _send() async {
    final txt = _msgC.text.trim();
    if (txt.isEmpty) return;

    /* editing existing message */
    if (_editingId != null) {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(_chatId)
          .collection('messages')
          .doc(_editingId!)
          .update({'text': txt, 'edited': true, 'editedAt': Timestamp.now()});
      setState(() => _editingId = null);
      _msgC.clear();
      return;
    }

    /* new message */
    HapticFeedback.mediumImpact();

    final chatDoc = FirebaseFirestore.instance.collection('chats').doc(_chatId);
    await chatDoc.set({
      'participants': [_me, widget.uid],
      'lastMessage': txt,
      'lastSenderId': _me,
      'lastTimestamp': Timestamp.now(),
      'typing': {_me: false, widget.uid: false},
    }, SetOptions(merge: true));

    await chatDoc.collection('messages').add({
      'senderId': _me,
      'receiverId': widget.uid,
      'text': txt,
      'timestamp': Timestamp.now(),
      'read': false,
      'type': 'text',
      if (_reply != null) 'replyTo': _reply,
    });

    setState(() => _reply = null);
    _msgC.clear();
    _setTyping(false);
  }

  Future<void> _deleteMessage(String docId) async {
    await FirebaseFirestore.instance
        .collection('chats')
        .doc(_chatId)
        .collection('messages')
        .doc(docId)
        .update({
          'type': 'deleted',
          'text': '💬 message deleted',
          'deletedAt': Timestamp.now(),
        });
  }

  /*────────────────────────── build ──────────────────────────*/
  @override
  Widget build(BuildContext context) {
    final inputBar = _InputBar(
      controller: _msgC,
      onSend: _send,
      onTyping: _setTyping,
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
            CircleAvatar(
              radius: 20,
              backgroundColor: Colors.grey.shade300,
              child: Text(
                _initials(widget.name),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
            const SizedBox(width: 10),
            _Header(uid: widget.uid, name: widget.name),
          ],
        ),
      ),
      body: Column(
        children: [
          /* ---------------- messages stream ---------------- */
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('chats')
                      .doc(_chatId)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .snapshots(),
              builder: (_, snap) {
                final docs = snap.hasData ? snap.data!.docs : _cached;
                _jumpBottom();

                return ListView.builder(
                  controller: _scrollC,
                  reverse: true,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  itemCount: docs.length,
                  itemBuilder: (_, i) {
                    final m = docs[i].data() as Map<String, dynamic>;
                    final me = m['senderId'] == _me;
                    final id = docs[i].id;

                    /* mark read */
                    if (!me && !(m['read'] ?? true)) {
                      docs[i].reference.update({'read': true});
                    }

                    return _MessageBubble(
                      me: me,
                      map: m,
                      onSlideReply:
                          () => setState(() {
                            _reply = {
                              'text': m['text'],
                              'senderId': m['senderId'],
                            };
                          }),
                      onLongPressEditDelete:
                          me
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
            ),
          ),

          /* ---------------- typing indicator ---------------- */
          StreamBuilder<DocumentSnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('chats')
                    .doc(_chatId)
                    .snapshots(),
            builder: (_, s) {
              final typing =
                  (s.data?.data() as Map<String, dynamic>?)?['typing'];
              final show = typing != null && typing[widget.uid] == true;
              return AnimatedSize(
                duration: const Duration(milliseconds: 200),
                child:
                    show
                        ? const Padding(
                          padding: EdgeInsets.only(left: 20, bottom: 8),
                          child: _Dots(),
                        )
                        : const SizedBox.shrink(),
              );
            },
          ),

          /* ---------------- input bar ---------------- */
          inputBar,
        ],
      ),
    );
  }
}

/*────────────────────  message-bubble  ───────────────────*/
class _MessageBubble extends StatefulWidget {
  const _MessageBubble({
    required this.me,
    required this.map,
    required this.onSlideReply,
    this.onLongPressEditDelete,
  });

  final bool me;
  final Map<String, dynamic> map;
  final VoidCallback onSlideReply;
  final Future<void> Function(Offset globalPos)? onLongPressEditDelete;

  @override
  State<_MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<_MessageBubble>
    with SingleTickerProviderStateMixin {
  /* slide-to-reply offset */
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

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onHorizontalDragStart: (_) => _spring.stop(),
      onHorizontalDragUpdate: (d) {
        setState(() {
          _dx += d.delta.dx;
          _dx = widget.me ? _dx.clamp(-90, 0) : _dx.clamp(0, 90);
        });
      },
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
      child: _Slidable(dx: _dx, spring: _spring, child: _buildBubble()),
    );
  }

  Widget _buildBubble() {
    final m = widget.map;

    /* time + (optional) read-tick */
    final ts = m['timestamp'] as Timestamp;
    final timeReadRow = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          DateFormat('h:mm a').format(ts.toDate()),
          style: const TextStyle(fontSize: 10, color: Colors.grey),
        ),
        if (widget.me)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              Icons.done_all,
              size: 15,
              color: (m['read'] ?? false) ? Colors.green : Colors.grey,
            ),
          ),
      ],
    );

    /* main bubble container */
    final bubble = Column(
      crossAxisAlignment:
          widget.me ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      children: [
        if (m['replyTo'] != null) _ReplyPreview(m['replyTo']),
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border.all(color: Colors.grey.shade300),
            color:
                m['type'] == 'deleted'
                    ? Colors.grey.shade300
                    : widget.me
                    ? const Color(0xFFD2F5E3)
                    : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(18),
              topRight: const Radius.circular(18),
              bottomLeft: Radius.circular(widget.me ? 18 : 6),
              bottomRight: Radius.circular(widget.me ? 6 : 18),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            child: Text(
              m['text'],
              style: TextStyle(
                fontSize: 15,
                fontStyle:
                    m['type'] == 'deleted'
                        ? FontStyle.italic
                        : FontStyle.normal,
                color:
                    m['type'] == 'deleted'
                        ? Colors.grey.shade600
                        : Colors.black,
              ),
            ),
          ),
        ),
        timeReadRow,
      ],
    );

    /* fade & slide-in on initial build */
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      builder:
          (_, v, child) => Opacity(
            opacity: v,
            child: Transform.translate(
              offset: Offset((widget.me ? 1 : -1) * 30 * (1 - v), 0),
              child: child,
            ),
          ),
      child: bubble,
    );
  }
}

/* small helper that animates the slide-back */
class _Slidable extends StatelessWidget {
  final double dx;
  final AnimationController spring;
  final Widget child;
  const _Slidable({
    required this.dx,
    required this.spring,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: spring,
      builder:
          (_, __) => Transform.translate(
            offset: Offset(dx * (1 - spring.value), 0),
            child: child,
          ),
    );
  }
}

/*──────────────────── reply preview ───────────────────*/
class _ReplyPreview extends StatelessWidget {
  final Map<String, dynamic> data;
  const _ReplyPreview(this.data, {Key? key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bool me = data['senderId'] == FirebaseAuth.instance.currentUser?.uid;
    return Container(
      margin: const EdgeInsets.only(bottom: 4),
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: me ? Colors.green.shade100 : Colors.grey.shade200,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        data['text'],
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12, color: Colors.black54),
      ),
    );
  }
}

/*──────────────────── header (name + status) ───────────────────*/
class _Header extends StatelessWidget {
  final String uid, name;
  const _Header({required this.uid, required this.name});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot>(
      stream:
          FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
      builder: (_, snap) {
        final data = snap.data?.data() as Map<String, dynamic>? ?? {};
        final online = data['online'] == true;
        final lastSeen = data['lastSeen'] as Timestamp?;
        final status =
            online
                ? 'Online'
                : lastSeen != null
                ? 'Last seen ${DateFormat('h:mm a').format(lastSeen.toDate())}'
                : 'Offline';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name,
              style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 16,
                color: Colors.black,
              ),
            ),
            Text(
              status,
              style: TextStyle(
                fontSize: 12,
                color: online ? Colors.green : Colors.grey,
              ),
            ),
          ],
        );
      },
    );
  }
}

/*──────────────────── typing indicator dots ───────────────────*/
class _Dots extends StatelessWidget {
  const _Dots();

  @override
  Widget build(BuildContext context) => Row(
    children: const [
      _Dot(0),
      SizedBox(width: 4),
      _Dot(150),
      SizedBox(width: 4),
      _Dot(300),
    ],
  );
}

class _Dot extends StatefulWidget {
  final int delay;
  const _Dot(this.delay);

  @override
  State<_Dot> createState() => _DotState();
}

class _DotState extends State<_Dot> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  late final Animation<double> _a = CurvedAnimation(
    parent: _c,
    curve: Curves.easeInOut,
  );

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => FadeTransition(
    opacity: _a,
    child: SizeTransition(
      sizeFactor: _a,
      axisAlignment: -1,
      child: Container(
        width: 8,
        height: 8,
        decoration: BoxDecoration(
          color: Colors.grey,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    ),
  );
}

/*──────────────────── input bar  +  banners ───────────────────*/
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onTyping,
    required this.reply,
    required this.onCancelReply,
    required this.isEditing,
    required this.onCancelEdit,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<bool> onTyping;
  final Map<String, dynamic>? reply;
  final VoidCallback onCancelReply;
  final bool isEditing;
  final VoidCallback onCancelEdit;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      if (reply != null)
        _Banner(
          text: reply!['text'],
          label: 'Reply',
          colour: Colors.blue,
          onClose: onCancelReply,
        ),
      if (isEditing)
        _Banner(
          text: 'Editing message',
          label: 'Edit',
          colour: Colors.orange,
          onClose: onCancelEdit,
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
                  onChanged: (v) => onTyping(v.isNotEmpty),
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
    required this.text,
    required this.label,
    required this.colour,
    required this.onClose,
  });

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
