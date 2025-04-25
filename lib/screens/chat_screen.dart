// lib/screens/chat_screen.dart
//
// depends on: cloud_firestore, firebase_auth, intl, image_picker (optional),
// and nothing else.  Uses only Flutter-SDK widgets & animations.

import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart';

class ChatScreen extends StatefulWidget {
  final String name;
  final String uid;
  const ChatScreen({required this.name, required this.uid, Key? key})
    : super(key: key);

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  /* ────────────────────────────── state ────────────────────────────── */
  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();

  final _me = FirebaseAuth.instance.currentUser!.uid;
  late final String _chatId;

  /// cache so the UI doesn’t “jump” while the first stream comes in
  List<DocumentSnapshot> _cachedMsgs = [];

  /* ─────────────────────────── lifecycle ─────────────────────────── */
  @override
  void initState() {
    super.initState();
    _chatId = _composeChatId(_me, widget.uid);
    _primeCache();
  }

  @override
  void dispose() {
    _msgCtrl.dispose();
    _setTyping(false);
    super.dispose();
  }

  /* ───────────────────────── helpers ───────────────────────── */
  String _composeChatId(String a, String b) =>
      (a.compareTo(b) < 0) ? '$a-$b' : '$b-$a';

  Future<void> _primeCache() async {
    final snap =
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .collection('messages')
            .orderBy('timestamp')
            .get();
    setState(() => _cachedMsgs = snap.docs);
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
        );
      }
    });
  }

  /* ───────────────────────── typing flag ───────────────────────── */
  void _setTyping(bool v) {
    FirebaseFirestore.instance.collection('chats').doc(_chatId).set({
      'typing': {_me: v},
    }, SetOptions(merge: true));
  }

  /* ───────────────────────── send message ───────────────────────── */
  Future<void> _send() async {
    final txt = _msgCtrl.text.trim();
    if (txt.isEmpty) return;
    HapticFeedback.mediumImpact();

    final chatRef = FirebaseFirestore.instance.collection('chats').doc(_chatId);

    await chatRef.set({
      'participants': [_me, widget.uid],
      'lastMessage': txt,
      'lastSenderId': _me,
      'lastTimestamp': Timestamp.now(),
      'typing': {_me: false, widget.uid: false},
    }, SetOptions(merge: true));

    await chatRef.collection('messages').add({
      'senderId': _me,
      'receiverId': widget.uid,
      'text': txt,
      'timestamp': Timestamp.now(),
      'read': false,
      'type': 'text',
    });

    _msgCtrl.clear();
    _setTyping(false);
  }

  /* ────────────────────────── UI helper widgets ────────────────────────── */
  Widget _dot([int delay = 0]) => _TypingDot(delay: delay);

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget _timestamp(Timestamp ts) => Padding(
    padding: const EdgeInsets.only(top: 2),
    child: Text(
      DateFormat('h:mm a').format(ts.toDate()),
      style: const TextStyle(fontSize: 10, color: Colors.grey),
    ),
  );

  Widget _readTick(bool read) => Padding(
    padding: const EdgeInsets.only(left: 4, top: 2),
    child: Icon(
      Icons.done_all,
      size: 15,
      color: read ? Colors.green : Colors.grey,
    ),
  );

  /* ─────────────────────────── build ─────────────────────────── */
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F6F6),
    appBar: AppBar(
      backgroundColor: Colors.white,
      foregroundColor: Colors.black87,
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
          _HeaderName(uid: widget.uid, name: widget.name),
        ],
      ),
    ),
    body: Column(
      children: [
        /* -------------------- messages stream -------------------- */
        Expanded(
          child: StreamBuilder<QuerySnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('chats')
                    .doc(_chatId)
                    .collection('messages')
                    .orderBy('timestamp')
                    .snapshots(),
            builder: (_, snap) {
              final docs = snap.hasData ? snap.data!.docs : _cachedMsgs;

              WidgetsBinding.instance.addPostFrameCallback(
                (_) => _scrollToBottom(),
              );

              return ListView.builder(
                controller: _scrollCtrl,
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 8,
                ),
                itemCount: docs.length,
                itemBuilder: (_, i) {
                  final m = docs[i].data() as Map<String, dynamic>;
                  final me = m['senderId'] == _me;

                  /* mark as read */
                  if (!me && m['read'] == false) {
                    docs[i].reference.update({'read': true});
                  }

                  /* ----- bubble with slide+fade animation ----- */
                  return TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 350),
                    curve: Curves.easeOutCubic,
                    builder:
                        (_, val, child) => Opacity(
                          opacity: val,
                          child: Transform.translate(
                            offset: Offset((me ? 1 : -1) * (30 * (1 - val)), 0),
                            child: child,
                          ),
                        ),
                    child: Align(
                      alignment:
                          me ? Alignment.centerRight : Alignment.centerLeft,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 280),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: me ? const Color(0xFFD2F5E3) : Colors.white,
                            borderRadius: BorderRadius.only(
                              topLeft: const Radius.circular(18),
                              topRight: const Radius.circular(18),
                              bottomLeft: Radius.circular(me ? 18 : 4),
                              bottomRight: Radius.circular(me ? 4 : 18),
                            ),
                            border: Border.all(
                              color: Colors.grey.shade300,
                              width: 1,
                            ),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            child: Text(
                              m['text'],
                              style: const TextStyle(fontSize: 15),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ).wrapWithMeta(
                    me
                        ? [_timestamp(m['timestamp']), _readTick(m['read'])]
                        : [_timestamp(m['timestamp'])],
                  );
                },
              );
            },
          ),
        ),

        /* -------------------- typing indicator -------------------- */
        StreamBuilder<DocumentSnapshot>(
          stream:
              FirebaseFirestore.instance
                  .collection('chats')
                  .doc(_chatId)
                  .snapshots(),
          builder: (_, snap) {
            final typing =
                (snap.data?.data() as Map<String, dynamic>?)?['typing'];
            final isTyping = typing != null && typing[widget.uid] == true;
            return AnimatedSize(
              duration: const Duration(milliseconds: 200),
              child:
                  isTyping
                      ? Padding(
                        padding: const EdgeInsets.only(left: 18, bottom: 8),
                        child: Row(children: [_dot(), _dot(150), _dot(300)]),
                      )
                      : const SizedBox.shrink(),
            );
          },
        ),

        /* -------------------- input bar -------------------- */
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 24),
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
                    controller: _msgCtrl,
                    minLines: 1,
                    maxLines: 6,
                    onChanged: (v) => _setTyping(v.isNotEmpty),
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
                  onPressed: _send,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}

/* ────────────────────────────────────────────────────────────── */
/* widgets & extensions                                           */
/* ────────────────────────────────────────────────────────────── */

extension _WithMeta on Widget {
  /// Display timestamp / read-tick under the bubble, nicely aligned
  Widget wrapWithMeta(List<Widget> meta) => Column(
    crossAxisAlignment:
        meta.length == 1 ? CrossAxisAlignment.center : CrossAxisAlignment.end,
    children: [
      this,
      Row(mainAxisSize: MainAxisSize.min, children: meta),
      const SizedBox(height: 4),
    ],
  );
}

/* ------- dot used in typing indicator ------- */
class _TypingDot extends StatefulWidget {
  final int delay;
  const _TypingDot({this.delay = 0});

  @override
  State<_TypingDot> createState() => _TypingDotState();
}

class _TypingDotState extends State<_TypingDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 600),
  )..repeat(reverse: true);

  late final Animation<double> _anim = CurvedAnimation(
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
    opacity: _anim,
    child: SizeTransition(
      sizeFactor: _anim,
      axis: Axis.vertical,
      axisAlignment: -1,
      child: Container(
        width: 8,
        height: 8,
        margin: EdgeInsets.only(
          left: widget.delay == 0 ? 0 : 4,
          right: 4,
          bottom: 4,
        ),
        decoration: BoxDecoration(
          color: Colors.grey,
          borderRadius: BorderRadius.circular(4),
        ),
      ),
    ),
  );
}

/* ------- header (name + online status) ------- */
class _HeaderName extends StatelessWidget {
  final String uid, name;
  const _HeaderName({required this.uid, required this.name});

  @override
  Widget build(BuildContext context) => StreamBuilder<DocumentSnapshot>(
    stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
    builder: (_, snap) {
      final data = snap.data?.data() as Map<String, dynamic>?;

      final online = data?['online'] == true;
      final lastSeenTs = data?['lastSeen'] as Timestamp?;

      String status;
      if (online) {
        status = 'Online';
      } else if (lastSeenTs != null) {
        status =
            'Last seen ${DateFormat('h:mm a').format(lastSeenTs.toDate())}';
      } else {
        status = 'Offline';
      }

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
