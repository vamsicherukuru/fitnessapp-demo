// lib/screens/group_info_screen.dart
//
// richer “Group info” – hero banner, leaderboard, streaks, admin tools
// ─────────────────────────────────────────────────────────────────────
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'chat_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  final String chatId; // chats/<id>
  final String name; // used for the hero animation label

  const GroupInfoScreen({Key? key, required this.chatId, required this.name})
    : super(key: key);

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

/*────────────────────────────────────────────────────────────*/
class _GroupInfoScreenState extends State<GroupInfoScreen> {
  final _me = FirebaseAuth.instance.currentUser!.uid;

  /* tiny in-mem user cache */
  final _u = <String, Map<String, dynamic>>{};

  Future<Map<String, dynamic>> _user(String uid) async {
    if (_u.containsKey(uid)) return _u[uid]!;

    final doc =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final now = DateTime.now();
    final todayId =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final daily =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('dailySteps')
            .doc(todayId)
            .get();

    final data = doc.data() ?? {};
    data['uid'] = uid;
    data['todaySteps'] = (daily.exists ? (daily['steps'] ?? 0) : 0);

    _u[uid] = data;
    return data;
  }

  String _initials(String n) {
    final p = n.trim().split(RegExp(r'\s+'));
    return p.length == 1
        ? p[0][0].toUpperCase()
        : (p[0][0] + p[1][0]).toUpperCase();
  }

  Color _pastel(String uid) {
    final h = uid.codeUnits.fold<int>(0, (p, c) => p + c);
    final hue = (h * 37) % 360;
    return HSLColor.fromAHSL(1, hue.toDouble(), .45, .75).toColor();
  }

  /*──────────────────────── rename ───────────────────────*/
  Future<void> _rename(String current) async {
    final c = TextEditingController(text: current);
    final newName = await showDialog<String>(
      context: context,
      builder:
          (_) => AlertDialog(
            title: const Text('Rename group'),
            content: TextField(
              controller: c,
              decoration: const InputDecoration(
                border: OutlineInputBorder(),
                hintText: 'Group name',
              ),
              autofocus: true,
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context),
                child: const Text('Cancel'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, c.text.trim()),
                child: const Text('Save'),
              ),
            ],
          ),
    );
    if (newName == null || newName.isEmpty || newName == current) return;

    final chat = FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId);
    await chat.update({'groupName': newName});

    final actor = (await _user(_me))['username'];
    await chat.collection('messages').add({
      'type': 'system',
      'text': '$actor renamed the group to “$newName”',
      'timestamp': Timestamp.now(),
    });
  }

  Future<void> _handleRefresh() async {
    setState(() {
      _u.clear(); // 🔥 This clears user cache and forces rebuild
    });
  }

  /*─────────────────── admin pop-menu ───────────────────*/
  void _memberAdminSheet({
    required String uid,
    required bool isAdmin,
    required bool viewerAdmin,
    required String uname,
  }) {
    if (!viewerAdmin || uid == _me) return;
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder:
          (_) => Column(
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
              ListTile(
                leading: Icon(isAdmin ? Icons.star_outline : Icons.star),
                title: Text(isAdmin ? 'Remove admin' : 'Make admin'),
                onTap: () async {
                  final f = FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId);
                  await f.update({
                    'admins':
                        isAdmin
                            ? FieldValue.arrayRemove([uid])
                            : FieldValue.arrayUnion([uid]),
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                leading: const Icon(
                  Icons.remove_circle_outline,
                  color: Colors.red,
                ),
                title: const Text(
                  'Remove from group',
                  style: TextStyle(color: Colors.red),
                ),
                onTap: () async {
                  final chat = FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId);
                  await chat.update({
                    'participants': FieldValue.arrayRemove([uid]),
                    'admins': FieldValue.arrayRemove([uid]),
                  });
                  final actor = (await _user(_me))['username'];
                  await chat.collection('messages').add({
                    'type': 'system',
                    'text': '$actor removed @$uname',
                    'timestamp': Timestamp.now(),
                  });
                  Navigator.pop(context);
                },
              ),
              const SizedBox(height: 16),
            ],
          ),
    );
  }

  /*──────────────────────── build ───────────────────────*/
  @override
  Widget build(
    BuildContext context,
  ) => StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
    stream:
        FirebaseFirestore.instance
            .collection('chats')
            .doc(widget.chatId)
            .snapshots(),
    builder: (_, snap) {
      if (!snap.hasData) {
        return const Scaffold(body: Center(child: CircularProgressIndicator()));
      }

      final g = snap.data!.data()!;
      final name = g['groupName'] as String? ?? 'Group';
      final creator = g['creatorId'] as String? ?? '';
      final admins = List<String>.from(g['admins'] ?? []);
      final members = List<String>.from(g['participants'] ?? []);

      final viewerIsAdmin = admins.contains(_me) || creator == _me;

      /* fetch all member-docs once for leaderboard */
      return FutureBuilder<List<Map<String, dynamic>>>(
        future: Future.wait(members.map(_user)),
        builder: (_, allSnap) {
          final allUsers = allSnap.data ?? [];
          final bySteps = [...allUsers]..sort(
            (a, b) => (b['todaySteps'] ?? 0).compareTo(a['todaySteps'] ?? 0),
          );
          final king = bySteps.isNotEmpty ? bySteps.first : null;
          final joker = bySteps.length > 1 ? bySteps.last : null;
          final maxSteps = king?['todaySteps'] ?? 0;
          final minSteps = joker?['todaySteps'] ?? 0;

          /* split friend / others for nicer grouping */
          final myData = allUsers.firstWhere(
            (e) => e['uid'] == _me,
            orElse: () => {},
          );
          final myFriends = List<String>.from(myData['friends'] ?? []);
          members.sort((a, b) {
            final af = myFriends.contains(a) ? 0 : 1;
            final bf = myFriends.contains(b) ? 0 : 1;
            return af.compareTo(bf);
          });

          Widget leaderboardCard(
            String label,
            Map<String, dynamic>? u,
            int steps,
            Color colour,
          ) {
            if (u == null) return const SizedBox.shrink();
            return Card(
              color: colour.withOpacity(.12),
              margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: ListTile(
                leading: CircleAvatar(
                  backgroundColor: colour,
                  child: Text(
                    _initials(u['username']),
                    style: const TextStyle(color: Colors.white),
                  ),
                ),
                title: Text('$label @${u['username']}'),
                subtitle: Text('$steps steps today'),
              ),
            );
          }

          /* UI */
          return Scaffold(
            backgroundColor: const Color(0xFFF6F6F6),
            appBar: AppBar(
              title: const Text('Group info'),
              backgroundColor: Colors.white,
              foregroundColor: Colors.black,
              elevation: 0,
            ),
            body: RefreshIndicator(
              onRefresh: _handleRefresh,

              child: ListView(
                children: [
                  /* hero banner */
                  Material(
                    color: Colors.white,
                    elevation: 1,
                    child: ListTile(
                      leading: const CircleAvatar(
                        radius: 26,
                        backgroundColor: Color(0xFFB2DFDB),
                        child: Icon(Icons.group, color: Colors.teal, size: 28),
                      ),
                      title: Text(
                        name,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 18,
                        ),
                      ),
                      subtitle: Text('${members.length} members'),
                      trailing: IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => _rename(name),
                      ),
                    ),
                  ),

                  const SizedBox(height: 12),
                  leaderboardCard(
                    '👑  King of the day',
                    king,
                    maxSteps,
                    Colors.amber,
                  ),
                  leaderboardCard(
                    '🤡  Joker of the day',
                    joker,
                    minSteps,
                    Colors.blueGrey,
                  ),

                  const SizedBox(height: 20),
                  _sectionHeader('Friends in group'),
                  ...members
                      .where((u) => myFriends.contains(u))
                      .map(
                        (u) => _MemberTile(
                          uid: u,
                          me: _me,
                          creator: creator,
                          viewerIsAdmin: viewerIsAdmin,
                          admins: admins,
                          requested: List<String>.from(
                            myData['requestsOut'] ?? [],
                          ),
                          colourOf: _pastel,
                          initialsOf: _initials,
                          onAdminAction: _memberAdminSheet,
                        ),
                      ),
                  _sectionHeader('Others'),
                  ...members
                      .where((u) => !myFriends.contains(u))
                      .map(
                        (u) => _MemberTile(
                          uid: u,
                          me: _me,
                          creator: creator,
                          viewerIsAdmin: viewerIsAdmin,
                          admins: admins,
                          requested: List<String>.from(
                            myData['requestsOut'] ?? [],
                          ),
                          colourOf: _pastel,
                          initialsOf: _initials,
                          onAdminAction: _memberAdminSheet,
                        ),
                      ),

                  const SizedBox(height: 60),
                ],
              ),
            ),
          );
        },
      );
    },
  );

  Widget _sectionHeader(String t) => Padding(
    padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
    child: Text(
      t.toUpperCase(),
      style: const TextStyle(
        letterSpacing: .6,
        fontWeight: FontWeight.w600,
        color: Colors.grey,
      ),
    ),
  );
}

/*────────────────── member tile with streak & long-press ─────────────────*/
class _MemberTile extends StatelessWidget {
  const _MemberTile({
    required this.uid,
    required this.me,
    required this.creator,
    required this.viewerIsAdmin,
    required this.admins,
    required this.requested,
    required this.colourOf,
    required this.initialsOf,
    required this.onAdminAction,
  });

  final String uid, me, creator;
  final bool viewerIsAdmin;
  final List<String> admins, requested;
  final Color Function(String) colourOf;
  final String Function(String) initialsOf;
  final void Function({
    required String uid,
    required bool isAdmin,
    required bool viewerAdmin,
    required String uname,
  })
  onAdminAction;

  Future<Map<String, dynamic>> _fetchUserWithTodaySteps(String uid) async {
    final userSnap =
        await FirebaseFirestore.instance.collection('users').doc(uid).get();
    final userData = userSnap.data() ?? {};

    final now = DateTime.now();
    final todayId =
        '${now.year.toString().padLeft(4, '0')}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

    final stepsSnap =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .collection('dailySteps')
            .doc(todayId)
            .get();

    final stepsData = stepsSnap.data();
    userData['todaySteps'] = stepsData != null ? (stepsData['steps'] ?? 0) : 0;

    return userData;
  }

  @override
  Widget build(BuildContext context) => FutureBuilder<Map<String, dynamic>>(
    future: _fetchUserWithTodaySteps(uid),
    builder: (_, snap) {
      if (!snap.hasData) return const SizedBox.shrink();
      final u = snap.data!;
      final uname = u['username'] as String;
      final streak = u['currentStreak'] ?? 0;
      final steps = u['todaySteps'] ?? 0;
      final isMe = uid == me;
      final isAdmin = admins.contains(uid);
      final isCreator = uid == creator;

      /* trailing chips / buttons */
      Widget trailing;
      if (isMe) {
        trailing = const Chip(label: Text('You'));
      } else if (requested.contains(uid)) {
        trailing = const Chip(label: Text('Requested'));
      } else {
        trailing = IconButton(
          tooltip: 'Chat',
          icon: const Icon(Icons.chat_bubble_outline),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => ChatScreen(name: uname, uid: uid),
              ),
            );
          },
        );
      }

      /* streak row */
      final streakRow = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.local_fire_department,
            color: Colors.deepOrange,
            size: 18,
          ),
          const SizedBox(width: 2),
          Text(
            '$streak',
            style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500),
          ),
        ],
      );

      return GestureDetector(
        onLongPress:
            () => onAdminAction(
              uid: uid,
              isAdmin: isAdmin,
              viewerAdmin: viewerIsAdmin,
              uname: uname,
            ),
        child: TweenAnimationBuilder<double>(
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOutCubic,
          tween: Tween(begin: 0, end: 1),
          builder:
              (_, v, child) => Opacity(
                opacity: v,
                child: Transform.translate(
                  offset: Offset(0, 20 * (1 - v)),
                  child: child,
                ),
              ),
          child: Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
            child: ListTile(
              leading: CircleAvatar(
                backgroundColor: colourOf(uid),
                child: Text(
                  initialsOf(uname),
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              title: Text(
                '@$uname',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
              subtitle: Text('$steps steps today'),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  streakRow,
                  const SizedBox(width: 8),
                  if (isCreator)
                    const Chip(
                      label: Text('Creator'),
                      visualDensity: VisualDensity.compact,
                    )
                  else if (isAdmin)
                    const Chip(
                      label: Text('Admin'),
                      visualDensity: VisualDensity.compact,
                    ),
                  trailing,
                ],
              ),
            ),
          ),
        ),
      );
    },
  );
}
