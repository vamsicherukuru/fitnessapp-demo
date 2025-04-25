// lib/screens/friends_screen.dart
//
// Deps: cloud_firestore, firebase_auth, intl, shared_preferences
// ChatScreen already exists; group-chat screen still “coming soon”.

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../screens/chat_screen.dart';

/*──────── Firestore field names ───────*/
class FriendDoc {
  static const friends = 'friends';
  static const requestsIn = 'requestsIn';
  static const requestsOut = 'requestsOut';
}

/*──────── current user id (hot-restart-safe) ───────*/
final String _me = FirebaseAuth.instance.currentUser?.uid ?? '';

/*──────────────── Screen ───────────────*/
class FriendsScreen extends StatefulWidget {
  const FriendsScreen({super.key});
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

/*──────────────── State ────────────────*/
class _FriendsScreenState extends State<FriendsScreen> {
  /* controllers */
  final _searchC = TextEditingController();

  /* runtime */
  List<Map<String, dynamic>> _chats = []; // groups + DMs
  List<Map<String, String>> _friends = []; // {uid, username}
  List<Map<String, dynamic>> _filter = []; // local hits
  List<Map<String, dynamic>> _remote = []; // global hits

  List<String> _reqIn = []; // incoming requests
  List<String> _reqOut = []; // I sent
  String _query = '';

  /* cache */
  static const _kCache = 'cached_chats_v3';

  /* streams */
  late final StreamSubscription _profileSub;
  late final StreamSubscription _chatSub;

  /*──────────────── life-cycle ───────────────*/
  @override
  void initState() {
    super.initState();
    _listenProfile();
    _loadCache();
    _listenChats();
  }

  @override
  void dispose() {
    _profileSub.cancel();
    _chatSub.cancel();
    _searchC.dispose();
    super.dispose();
  }

  /*──────── profile listener ───────*/
  void _listenProfile() {
    _profileSub = FirebaseFirestore.instance
        .collection('users')
        .doc(_me)
        .snapshots()
        .listen((snap) async {
          final d = snap.data() ?? {};
          final friends = List<String>.from(d[FriendDoc.friends] ?? []);
          final inReqs = List<String>.from(d[FriendDoc.requestsIn] ?? []);
          final outReqs = List<String>.from(d[FriendDoc.requestsOut] ?? []);

          /* resolve usernames (tiny fan-out) */
          final List<Map<String, String>> fr = [];
          for (final uid in friends) {
            final u =
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(uid)
                    .get();
            if (u.exists) fr.add({'uid': uid, 'username': u['username']});
          }

          if (!mounted) return;
          setState(() {
            _friends = fr;
            _reqIn = inReqs;
            _reqOut = outReqs;
          });
        });
  }

  /*──────── local cache ───────*/
  Future<void> _loadCache() async {
    final sp = await SharedPreferences.getInstance();
    final raw = sp.getString(_kCache);
    if (raw == null) return;

    final cached =
        (jsonDecode(raw) as List)
            .cast<Map<String, dynamic>>()
            .map(
              (m) => {
                ...m,
                'lastTs':
                    m['lastTs'] != null
                        ? Timestamp.fromMillisecondsSinceEpoch(m['lastTs'])
                        : null,
              },
            )
            .toList();

    if (mounted) setState(() => _chats = cached);
  }

  Future<void> _saveCache() async {
    final sp = await SharedPreferences.getInstance();
    await sp.setString(
      _kCache,
      jsonEncode(
        _chats
            .map(
              (m) => {
                ...m,
                'lastTs': (m['lastTs'] as Timestamp?)?.millisecondsSinceEpoch,
              },
            )
            .toList(),
      ),
    );
  }

  /*──────── chats listener ───────*/
  void _listenChats() {
    _chatSub = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: _me)
        .snapshots()
        .listen((snap) async {
          final List<Map<String, dynamic>> list = [];

          for (final doc in snap.docs) {
            final d = doc.data();
            final parts = List<String>.from(d['participants']);
            final isGrp = d['isGroup'] == true;

            late String title;
            late Color avCol;
            late Widget avChild;
            int? streak;

            if (isGrp) {
              title = d['groupName'] ?? 'Group';
              avCol = Colors.teal.shade100;
              avChild = const Icon(Icons.group, color: Colors.teal);
              streak = null; // no streak for groups
            } else {
              final other = parts.firstWhere(
                (u) => u != _me,
                orElse: () => _me,
              );
              final u =
                  await FirebaseFirestore.instance
                      .collection('users')
                      .doc(other)
                      .get();
              title = u['username'];
              avCol = Colors.deepPurple.shade100;
              avChild = Text(
                title[0].toUpperCase(),
                style: const TextStyle(color: Colors.deepPurple),
              );
              streak = u['currentStreak'] ?? 0;
            }

            final lastSnap =
                await doc.reference
                    .collection('messages')
                    .orderBy('timestamp', descending: true)
                    .limit(1)
                    .get();
            final last =
                lastSnap.docs.isNotEmpty ? lastSnap.docs.first.data() : null;
            final ts = last?['timestamp'] ?? d['lastTs'] as Timestamp?;

            int unread = 0;
            final others = parts.where((u) => u != _me).toList();
            if (others.length <= 10) {
              unread =
                  (await doc.reference
                          .collection('messages')
                          .where('senderId', whereIn: others)
                          .where('read', isEqualTo: false)
                          .get())
                      .size;
            }

            list.add({
              'chatId': doc.id,
              'isGrp': isGrp,
              'uid':
                  isGrp
                      ? null
                      : parts.firstWhere((u) => u != _me, orElse: () => _me),
              'title': title,
              'avCol': avCol,
              'avChild': avChild,
              'streak': streak, // null for groups
              'lastMsg': last?['text'] ?? '',
              'lastTs': ts,
              'unread': unread,
            });
          }

          list.sort((a, b) {
            final ta = a['lastTs'] as Timestamp?;
            final tb = b['lastTs'] as Timestamp?;
            return (tb?.toDate() ?? DateTime(0)).compareTo(
              ta?.toDate() ?? DateTime(0),
            );
          });

          if (!mounted) return;
          setState(() => _chats = list);
          _saveCache();
          _applyQuery(_query);
        });
  }

  /*──────── friend-request helpers ───────*/
  Future<void> _sendRequest(String uid) async {
    final you = FirebaseFirestore.instance.collection('users').doc(uid);
    final me = FirebaseFirestore.instance.collection('users').doc(_me);

    final youOut = List<String>.from(
      (await you.get())[FriendDoc.requestsOut] ?? [],
    );

    if (youOut.contains(_me)) {
      // cross-request → auto-friend
      await you.update({
        FriendDoc.requestsOut: FieldValue.arrayRemove([_me]),
        FriendDoc.friends: FieldValue.arrayUnion([_me]),
      });
      await me.update({
        FriendDoc.requestsIn: FieldValue.arrayRemove([uid]),
        FriendDoc.friends: FieldValue.arrayUnion([uid]),
      });
    } else {
      await you.update({
        FriendDoc.requestsIn: FieldValue.arrayUnion([_me]),
      });
      await me.update({
        FriendDoc.requestsOut: FieldValue.arrayUnion([uid]),
      });
      if (mounted) setState(() => _reqOut.add(uid));
    }
  }

  Future<void> _cancelRequest(String uid) async {
    final you = FirebaseFirestore.instance.collection('users').doc(uid);
    final me = FirebaseFirestore.instance.collection('users').doc(_me);

    await you.update({
      FriendDoc.requestsIn: FieldValue.arrayRemove([_me]),
    });
    await me.update({
      FriendDoc.requestsOut: FieldValue.arrayRemove([uid]),
    });
    if (mounted) setState(() => _reqOut.remove(uid));
  }

  Future<void> _respondRequest(String uid, bool accept) async {
    final you = FirebaseFirestore.instance.collection('users').doc(uid);
    final me = FirebaseFirestore.instance.collection('users').doc(_me);

    await me.update({
      FriendDoc.requestsIn: FieldValue.arrayRemove([uid]),
      if (accept) FriendDoc.friends: FieldValue.arrayUnion([uid]),
    });
    await you.update({
      FriendDoc.requestsOut: FieldValue.arrayRemove([_me]),
      if (accept) FriendDoc.friends: FieldValue.arrayUnion([_me]),
    });

    if (!mounted) return;
    setState(() => _reqIn.remove(uid));
    if (_reqIn.isEmpty && Navigator.canPop(context)) Navigator.pop(context);
  }

  /*──────── search helpers ───────*/
  void _applyQuery(String q) {
    if (q.isEmpty) {
      setState(() => _filter = _remote = []);
      return;
    }

    final loc =
        _chats
            .where(
              (c) => (c['title'] as String).toLowerCase().contains(
                q.toLowerCase(),
              ),
            )
            .toList();

    if (loc.isNotEmpty) {
      setState(() => _filter = loc);
      _remote = [];
    } else {
      setState(() => _filter = []);
      _runRemoteSearch(q);
    }
  }

  Future<void> _runRemoteSearch(String q) async {
    final res = <Map<String, dynamic>>[];
    final snap =
        await FirebaseFirestore.instance
            .collection('usernames')
            .where(
              FieldPath.documentId,
              isGreaterThanOrEqualTo: q.toLowerCase(),
            )
            .where(
              FieldPath.documentId,
              isLessThanOrEqualTo: '${q.toLowerCase()}\uf8ff',
            )
            .limit(20)
            .get();

    for (final d in snap.docs) {
      final uid = d['uid'];
      if (uid == _me) continue;
      final u =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (u.exists) res.add({'uid': uid, 'username': u['username']});
    }
    if (mounted) setState(() => _remote = res);
  }

  /*──────── group-creator sheet ───────*/
  void _openGroupCreator() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        final nameC = TextEditingController();
        String q = '';
        final pick = <String>{};

        List<Map<String, String>> list() =>
            _friends
                .where(
                  (f) => f['username']!.toLowerCase().contains(q.toLowerCase()),
                )
                .toList();

        return StatefulBuilder(
          builder:
              (ctx, setLocal) => Padding(
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
                      'New group',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: TextField(
                        controller: nameC,
                        decoration: const InputDecoration(
                          labelText: 'Group name',
                          border: OutlineInputBorder(),
                        ),
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: TextField(
                        decoration: const InputDecoration(
                          prefixIcon: Icon(Icons.search),
                          hintText: 'Search friends',
                        ),
                        onChanged: (v) => setLocal(() => q = v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      height: math.min(list().length * 56 + 10, 300),
                      child: ListView.builder(
                        itemCount: list().length,
                        itemBuilder: (_, i) {
                          final u = list()[i];
                          final uid = u['uid']!;
                          final checked = pick.contains(uid);
                          return CheckboxListTile(
                            value: checked,
                            dense: true,
                            title: Text('@${u['username']}'),
                            controlAffinity: ListTileControlAffinity.leading,
                            onChanged:
                                (v) => setLocal(
                                  () => v! ? pick.add(uid) : pick.remove(uid),
                                ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.all(16),
                      child: ElevatedButton.icon(
                        icon: const Icon(Icons.check),
                        label: const Text('Create'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                          ),
                        ),
                        onPressed: () async {
                          if (nameC.text.trim().isEmpty || pick.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('Give name & members'),
                              ),
                            );
                            return;
                          }
                          await _createGroup(nameC.text.trim(), pick.toList());
                          if (!mounted) return;
                          Navigator.pop(ctx);
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
  }

  Future<void> _createGroup(String name, List<String> members) async {
    final id = FirebaseFirestore.instance.collection('chats').doc().id;
    final all = [_me, ...members];
    await FirebaseFirestore.instance.collection('chats').doc(id).set({
      'isGroup': true,
      'groupName': name,
      'participants': all,
      'admins': [_me], // you are admin
      'createdAt': Timestamp.now(),
      'lastTs': Timestamp.now(),
      'typing': {for (final u in all) u: false},
    });
  }

  /*──────── navigation helpers ───────*/
  void _openChatTile(Map<String, dynamic> c) {
    if (c['isGrp'] as bool) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Group chat screen coming soon!')),
      );
    } else {
      _openChat(c['uid'] as String, c['title'] as String);
    }
  }

  void _openChat(String uid, String uname) {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(name: uname, uid: uid)),
    );
  }

  /*──────── build ───────*/
  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: const Color(0xFFF6F6F6),
    body: CustomScrollView(
      slivers: [
        _appBar(),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
            child: _searchField(),
          ),
        ),
        SliverToBoxAdapter(child: _storiesRibbon()),
        if (_filter.isNotEmpty)
          _chatList(_filter)
        else if (_remote.isNotEmpty)
          _remoteList()
        else
          _chatList(_chats),
      ],
    ),
  );

  /*──────── app-bar ───────*/
  SliverAppBar _appBar() => SliverAppBar(
    pinned: true,
    backgroundColor: Colors.white,
    elevation: 0,
    title: const Text('Friends', style: TextStyle(fontWeight: FontWeight.w700)),
    actions: [
      Stack(
        alignment: Alignment.center,
        children: [
          IconButton(
            tooltip: 'Requests',
            icon: const Icon(Icons.person_add),
            onPressed: _reqIn.isEmpty ? null : _showRequestsSheet,
          ),
          if (_reqIn.isNotEmpty)
            Positioned(
              right: 8,
              top: 12,
              child: CircleAvatar(
                radius: 9,
                backgroundColor: Colors.deepOrange,
                child: Text(
                  '${_reqIn.length}',
                  style: const TextStyle(fontSize: 11, color: Colors.white),
                ),
              ),
            ),
        ],
      ),
      IconButton(
        tooltip: 'New group',
        icon: const Icon(Icons.group_add_outlined),
        onPressed: _openGroupCreator,
      ),
    ],
  );

  /*──────── search bar ───────*/
  Widget _searchField() => TextField(
    controller: _searchC,
    decoration: InputDecoration(
      hintText: 'Search friends / people',
      prefixIcon: const Icon(Icons.search),
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(26),
        borderSide: BorderSide.none,
      ),
    ),
    onChanged: (v) {
      _query = v.trim();
      _applyQuery(_query);
    },
  );

  /*──────── stories ribbon ───────*/
  Widget _storiesRibbon() => SizedBox(
    height: 100,
    child: ListView(
      padding: const EdgeInsets.only(left: 16),
      scrollDirection: Axis.horizontal,
      children: [
        _storyTile('You', Icons.account_circle),
        ..._friends.map(
          (f) => _storyTile('@${f['username']}', null, txt: f['username']![0]),
        ),
      ],
    ),
  );

  Widget _storyTile(String label, IconData? ico, {String? txt}) => Container(
    width: 72,
    margin: const EdgeInsets.only(right: 12),
    child: Column(
      children: [
        CircleAvatar(
          radius: 28,
          backgroundColor: Colors.deepPurple.shade100,
          child:
              ico != null
                  ? Icon(ico, color: Colors.deepPurple)
                  : Text(
                    txt!,
                    style: const TextStyle(color: Colors.deepPurple),
                  ),
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

  /*──────── requests sheet ───────*/
  void _showRequestsSheet() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder:
          (_) => ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.all(16),
            children: [
              const Center(
                child: Text(
                  'Friend requests',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700),
                ),
              ),
              const SizedBox(height: 12),
              for (final uid in _reqIn)
                FutureBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  future:
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(uid)
                          .get(),
                  builder: (ctx, s) {
                    if (!s.hasData) return const SizedBox.shrink();
                    final uname = s.data!['username'];
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(uname[0].toUpperCase()),
                        ),
                        title: Text('@$uname'),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(Icons.close),
                              onPressed: () => _respondRequest(uid, false),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.check,
                                color: Colors.green,
                              ),
                              onPressed: () => _respondRequest(uid, true),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
            ],
          ),
    );
  }

  /*──────── chat list ───────*/
  SliverList _chatList(List<Map<String, dynamic>> src) => SliverList(
    delegate: SliverChildBuilderDelegate((_, i) {
      if (i == 0)
        return const Padding(
          padding: EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Text(
            'Chats',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18),
          ),
        );
      final c = src[i - 1];
      return TweenAnimationBuilder<double>(
        duration: const Duration(milliseconds: 400),
        tween: Tween(begin: 0, end: 1),
        curve: Curves.easeOutBack,
        builder:
            (ctx, v, child) => Transform.translate(
              offset: Offset(0, 30 * (1 - v)),
              child: Opacity(opacity: (v).clamp(0.0, 1.0), child: child),
            ),
        child: _chatTile(c),
      );
    }, childCount: src.length + 1),
  );

  Widget _chatTile(Map<String, dynamic> c) => InkWell(
    onTap: () => _openChatTile(c),
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
            backgroundColor: c['avCol'],
            child: c['avChild'],
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  c['isGrp'] ? c['title'] : '@${c['title']}',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight:
                        c['unread'] > 0 ? FontWeight.w900 : FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  c['lastMsg'],
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color:
                        c['unread'] > 0 ? Colors.deepOrange : Colors.grey[700],
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
                _fmt(c['lastTs'] as Timestamp?),
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              if (c['streak'] != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.local_fire_department,
                      color: Colors.deepOrange,
                      size: 18,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      '${c['streak']}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              if (c['unread'] > 0) ...[
                const SizedBox(height: 6),
                CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.deepOrange,
                  child: Text(
                    '${c['unread']}',
                    style: const TextStyle(fontSize: 11, color: Colors.white),
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    ),
  );

  /*──────── remote list ───────*/
  SliverList _remoteList() => SliverList(
    delegate: SliverChildBuilderDelegate((_, i) {
      final u = _remote[i];
      final uid = u['uid'] as String;
      final requested = _reqOut.contains(uid);
      final friend = _friends.any((f) => f['uid'] == uid);

      Widget trailing;
      if (friend) {
        trailing = IconButton(
          tooltip: 'Chat',
          icon: const Icon(Icons.chat_bubble_outline),
          onPressed: () => _openChat(uid, u['username']),
        );
      } else if (requested) {
        trailing = ElevatedButton(
          onPressed: () => _cancelRequest(uid),
          style: ElevatedButton.styleFrom(backgroundColor: Colors.grey),
          child: const Text('Requested'),
        );
      } else {
        trailing = ElevatedButton(
          onPressed: () => _sendRequest(uid),
          child: const Text('Add'),
        );
      }

      return Card(
        margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
        child: ListTile(
          leading: CircleAvatar(
            child: Text((u['username'] as String)[0].toUpperCase()),
          ),
          title: Text('@${u['username']}'),
          trailing: trailing,
        ),
      );
    }, childCount: _remote.length),
  );
}

/*──────── util: friendly date label ───────*/
String _fmt(Timestamp? ts) {
  if (ts == null) return '';
  final d = ts.toDate(), n = DateTime.now();
  return d.day == n.day && d.month == n.month && d.year == n.year
      ? DateFormat('h:mm a').format(d)
      : DateFormat('dd MMM').format(d);
}
