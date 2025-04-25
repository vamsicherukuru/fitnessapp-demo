// lib/screens/friends_screen.dart
//
// deps: cloud_firestore, firebase_auth, intl
// (chat_screen.dart already exists)

import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import 'chat_screen.dart';

/*─────────────────────────────────────────────────────────────*/
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({Key? key}) : super(key: key);
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

/*─────────────────────────────────────────────────────────────*/
class _FriendsScreenState extends State<FriendsScreen> {
  /* ───────── my ids / refs ───────── */
  final _me = FirebaseAuth.instance.currentUser!.uid;
  final _searchC = TextEditingController();

  /* ───────── data ───────── */
  List<Map<String, dynamic>> _search = [];
  List<Map<String, dynamic>> _convos = [];
  List<String> _following = [];
  List<String> _requests = [];
  Map<String, String> _followingNames = {}; // uid → @name

  /* ───────── subs ───────── */
  late final StreamSubscription<QuerySnapshot> _chatSub;

  /*────────────────── init ─────────────────*/
  @override
  void initState() {
    super.initState();
    _loadSelf();
    _listenChats();
  }

  @override
  void dispose() {
    _searchC.dispose();
    _chatSub.cancel();
    super.dispose();
  }

  /*────────────────── firestore helpers ─────────────────*/
  Future<void> _loadSelf() async {
    final meDoc =
        await FirebaseFirestore.instance.collection('users').doc(_me).get();
    final d = meDoc.data() ?? {};
    final foll = List<String>.from(d['following'] ?? []);
    final req = List<String>.from(d['followRequests'] ?? []);

    /* fetch their @names (one small loop, tiny reads) */
    final Map<String, String> names = {};
    for (final uid in foll) {
      final u =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      names[uid] = u.data()?['username'] ?? 'user';
    }

    if (mounted) {
      setState(() {
        _following = foll;
        _requests = req;
        _followingNames = names;
      });
    }
  }

  void _listenChats() {
    _chatSub = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: _me)
        .snapshots()
        .listen((snap) async {
          final List<Map<String, dynamic>> list = [];

          for (final doc in snap.docs) {
            final parts = List<String>.from(doc['participants']);
            final otherId = parts.firstWhere((id) => id != _me);

            /* user meta */
            final uSnap =
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherId)
                    .get();
            if (!uSnap.exists) continue;
            final u = uSnap.data()!;
            final uname = u['username'];

            /* last message */
            final lastMsgSnap =
                await doc.reference
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .limit(1)
                    .get();
            final last =
                lastMsgSnap.docs.isNotEmpty
                    ? lastMsgSnap.docs.first.data()
                    : null;

            /* unread count for badge */
            final unreadSnap =
                await doc.reference
                    .collection('messages')
                    .where('senderId', isEqualTo: otherId)
                    .where('read', isEqualTo: false)
                    .get();

            list.add({
              'chatId': doc.id,
              'uid': otherId,
              'username': uname,
              'currentStreak': u['currentStreak'] ?? 0,
              'lastMessage': last?['text'] ?? '',
              'lastTs': last?['timestamp'] as Timestamp?,
              'unread': unreadSnap.size,
            });
          }

          list.sort((a, b) {
            final ta = a['lastTs'] as Timestamp?;
            final tb = b['lastTs'] as Timestamp?;
            return (tb?.toDate() ?? DateTime(0)).compareTo(
              ta?.toDate() ?? DateTime(0),
            );
          });

          if (mounted) setState(() => _convos = list);
        });
  }

  /*────────────────── UI helpers ─────────────────*/
  String _fmt(Timestamp? t) {
    if (t == null) return '';
    final dt = t.toDate();
    final now = DateTime.now();
    return dt.day == now.day && dt.month == now.month && dt.year == now.year
        ? DateFormat('h:mm a').format(dt)
        : DateFormat('dd MMM').format(dt);
  }

  /*────────────────── search ─────────────────*/
  Future<void> _runSearch(String q) async {
    if (q.trim().length < 3) return setState(() => _search = []);

    final us = await FirebaseFirestore.instance.collection('usernames').get();
    final List<Map<String, dynamic>> res = [];

    for (final doc in us.docs) {
      if (!doc.id.toLowerCase().contains(q.toLowerCase())) continue;
      final uid = doc['uid'];
      final u =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!u.exists) continue;
      final d = u.data()!;
      res.add({
        'uid': uid,
        'username': d['username'],
        'isPrivate': d['isPrivate'],
      });
    }

    if (mounted) setState(() => _search = res);
  }

  /*────────────────── follow helpers ─────────────────*/
  Future<void> _follow(String target, bool priv) async {
    final meRef = FirebaseFirestore.instance.collection('users').doc(_me);
    final tRef = FirebaseFirestore.instance.collection('users').doc(target);

    if (priv) {
      await tRef.update({
        'followRequests': FieldValue.arrayUnion([_me]),
      });
    } else {
      await tRef.update({
        'followers': FieldValue.arrayUnion([_me]),
      });
      await meRef.update({
        'following': FieldValue.arrayUnion([target]),
      });
    }
    _loadSelf();
  }

  Future<void> _unfollow(String target) async {
    final meRef = FirebaseFirestore.instance.collection('users').doc(_me);
    final tRef = FirebaseFirestore.instance.collection('users').doc(target);

    await tRef.update({
      'followers': FieldValue.arrayRemove([_me]),
    });
    await meRef.update({
      'following': FieldValue.arrayRemove([target]),
    });
    _loadSelf();
  }

  /*────────────────── chat nav ─────────────────*/
  void _openChat(String uid, String uname) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(name: uname, uid: uid)),
    );
  }

  /*────────────────── build ─────────────────*/
  @override
  Widget build(BuildContext ctx) => Scaffold(
    backgroundColor: const Color(0xFFF6F6F6),
    body: CustomScrollView(
      slivers: [
        SliverAppBar(
          pinned: true,
          backgroundColor: Colors.white,
          elevation: 0,
          title: const Text(
            'Friends',
            style: TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _searchBar(),
          ),
        ),
        SliverToBoxAdapter(child: _storiesRibbon()),
        (_search.isNotEmpty)
            ? SliverList(
              delegate: SliverChildBuilderDelegate(
                (_, i) => _searchTile(_search[i]),
                childCount: _search.length,
              ),
            )
            : _chatSection(),
      ],
    ),
  );

  /*──────────────── slots ─────────────────*/
  Widget _searchBar() => TextField(
    controller: _searchC,
    decoration: InputDecoration(
      hintText: 'Search by @username…',
      prefixIcon: const Icon(Icons.search),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(26),
        borderSide: BorderSide.none,
      ),
    ),
    onChanged: _runSearch,
  );

  Widget _storiesRibbon() => SizedBox(
    height: 100,
    child: ListView(
      padding: const EdgeInsets.only(left: 16),
      scrollDirection: Axis.horizontal,
      children: [
        _storyTile(label: 'Your story', add: true),
        ..._following.map(
          (uid) => _storyTile(label: '@${_followingNames[uid] ?? ''}'),
        ),
      ],
    ),
  );

  Widget _storyTile({required String label, bool add = false}) => Container(
    width: 72,
    margin: const EdgeInsets.only(right: 12),
    child: Column(
      children: [
        Stack(
          alignment: Alignment.bottomRight,
          children: [
            CircleAvatar(
              radius: 28,
              backgroundColor: Colors.deepPurple.shade100,
              child: const Icon(Icons.person, color: Colors.deepPurple),
            ),
            if (add)
              CircleAvatar(
                radius: 10,
                backgroundColor: Colors.white,
                child: const Icon(Icons.add, size: 16, color: Colors.green),
              ),
          ],
        ),
        const SizedBox(height: 6),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 11),
        ),
      ],
    ),
  );

  /*────────────────── search result row ─────────────────*/
  Widget _searchTile(Map<String, dynamic> u) {
    final isMe = u['uid'] == _me;
    final already = _following.contains(u['uid']);
    final requested = _requests.contains(u['uid']);

    Widget trailing = const SizedBox.shrink();
    if (!isMe) {
      if (already) {
        trailing = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconButton(
              icon: const Icon(
                Icons.chat_bubble_outline,
                color: Colors.deepOrange,
              ),
              onPressed: () => _openChat(u['uid'], u['username']),
            ),
            IconButton(
              icon: const Icon(Icons.remove_circle_outline, color: Colors.grey),
              onPressed: () => _unfollow(u['uid']),
            ),
          ],
        );
      } else if (requested) {
        trailing = OutlinedButton(
          onPressed: null,
          child: const Text('Requested'),
        );
      } else {
        trailing = ElevatedButton(
          onPressed: () => _follow(u['uid'], u['isPrivate']),
          child: Text(u['isPrivate'] ? 'Request' : 'Follow'),
        );
      }
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        elevation: 2,
        child: ListTile(
          leading: CircleAvatar(child: Text(u['username'][0].toUpperCase())),
          title: Text('@${u['username']}'),
          trailing: trailing,
        ),
      ),
    );
  }

  /*────────────────── chats section ─────────────────*/
  Widget _chatSection() => SliverList(
    delegate: SliverChildBuilderDelegate((_, i) {
      if (i == 0) {
        return const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Chats',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        );
      }
      final c = _convos[i - 1];
      return _chatTile(c, i - 1);
    }, childCount: _convos.length + 1),
  );

  Widget _chatTile(
    Map<String, dynamic> c,
    int idx,
  ) => TweenAnimationBuilder<double>(
    duration: const Duration(milliseconds: 400),
    tween: Tween(begin: 0.0, end: 1.0),
    curve: Curves.easeOutBack, // nice elastic entrance
    builder:
        (_, v, child) => Transform.translate(
          offset: Offset(0, 30 * (1 - v)),
          // 🔑 clamp because the curve briefly goes above 1.0
          child: Opacity(opacity: v.clamp(0.0, 1.0), child: child),
        ),
    child: InkWell(
      onTap: () => _openChat(c['uid'], c['username']),
      borderRadius: BorderRadius.circular(18),
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(.06),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.deepPurple.shade100,
              child: Text(
                c['username'][0].toUpperCase(),
                style: const TextStyle(color: Colors.deepPurple),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '@${c['username']}',
                    style: TextStyle(
                      fontWeight:
                          c['unread'] > 0 ? FontWeight.w900 : FontWeight.w600,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    c['lastMessage'],
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color:
                          c['unread'] > 0
                              ? Colors.deepOrange
                              : Colors.grey[700],
                      fontWeight:
                          c['unread'] > 0 ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _fmt(c['lastTs']),
                  style: TextStyle(fontSize: 12, color: Colors.grey[600]),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: Colors.deepOrange,
                      size: 18,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '${c['currentStreak']}-day',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                if (c['unread'] > 0) ...[
                  const SizedBox(height: 6),
                  AnimatedScale(
                    scale: 1,
                    duration: const Duration(milliseconds: 300),
                    curve: Curves.elasticOut,
                    child: CircleAvatar(
                      radius: 10,
                      backgroundColor: Colors.deepOrange,
                      child: Text(
                        '${c['unread']}',
                        style: const TextStyle(
                          fontSize: 11,
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    ),
  );
}
