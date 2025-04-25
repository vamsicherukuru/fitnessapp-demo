import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'dart:async';
import 'chat_screen.dart';

class FriendsScreen extends StatefulWidget {
  @override
  State<FriendsScreen> createState() => _FriendsScreenState();
}

class _FriendsScreenState extends State<FriendsScreen> {
  final _searchController = TextEditingController();
  List<Map<String, dynamic>> searchResults = [];
  List<Map<String, dynamic>> myConversations = [];
  String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  List<String> myFollowing = [];
  List<String> myFollowRequests = [];
  Map<String, String> followingUsernames = {}; // uid -> username
  late StreamSubscription<QuerySnapshot> _chatSubscription;

  @override
  void initState() {
    super.initState();
    _fetchMyData();
    _subscribeToChats();
  }

  Future<void> _fetchMyData() async {
    final doc =
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUserId)
            .get();
    if (doc.exists) {
      final data = doc.data()!;
      final following = List<String>.from(data['following'] ?? []);
      final requests = List<String>.from(data['followRequests'] ?? []);

      Map<String, String> fetchedUsernames = {};
      for (final uid in following) {
        final userSnap =
            await FirebaseFirestore.instance.collection('users').doc(uid).get();
        if (userSnap.exists) {
          fetchedUsernames[uid] = userSnap.data()?['username'] ?? 'User';
        }
      }

      setState(() {
        myFollowing = following;
        myFollowRequests = requests;
        followingUsernames = fetchedUsernames;
      });
    }
  }

  void _subscribeToChats() {
    _chatSubscription = FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: currentUserId)
        .snapshots()
        .listen((snapshot) async {
          List<Map<String, dynamic>> updatedConversations = [];
          for (var doc in snapshot.docs) {
            final otherUserId = (doc['participants'] as List).firstWhere(
              (id) => id != currentUserId,
            );

            final userDoc =
                await FirebaseFirestore.instance
                    .collection('users')
                    .doc(otherUserId)
                    .get();
            if (userDoc.exists) {
              final userData = userDoc.data()!;

              final lastMessageId =
                  await FirebaseFirestore.instance
                      .collection('chats')
                      .doc(doc.id)
                      .collection('messages')
                      .orderBy('timestamp', descending: true)
                      .limit(1)
                      .get();

              bool isUnread = false;
              if (lastMessageId.docs.isNotEmpty) {
                final lastMsg = lastMessageId.docs.first.data();
                isUnread =
                    lastMsg['senderId'] != currentUserId &&
                    !(lastMsg['read'] ?? false);
              }

              updatedConversations.add({
                'uid': otherUserId,
                'username': userData['username'],
                'currentStreak': userData['currentStreak'] ?? 0,
                'lastMessage': doc['lastMessage'] ?? '',
                'lastTimestamp': doc['lastTimestamp'],
                'unread': isUnread,
              });
            }
          }

          updatedConversations.sort((a, b) {
            final tsA = a['lastTimestamp'] as Timestamp?;
            final tsB = b['lastTimestamp'] as Timestamp?;
            return (tsB?.toDate() ?? DateTime(0)).compareTo(
              tsA?.toDate() ?? DateTime(0),
            );
          });

          setState(() {
            myConversations = updatedConversations;
          });
        });
  }

  void _searchUsers(String query) async {
    if (query.isEmpty || query.length < 3) {
      setState(() => searchResults.clear());
      return;
    }

    final usernamesRef = FirebaseFirestore.instance.collection('usernames');
    final snapshot = await usernamesRef.get();
    List<Map<String, dynamic>> results = [];

    for (var doc in snapshot.docs) {
      final docId = doc.id.toLowerCase();
      if (docId.contains(query.toLowerCase())) {
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(doc.data()['uid'])
                .get();
        if (userDoc.exists) {
          final data = userDoc.data()!;
          results.add({
            'uid': doc.data()['uid'],
            'username': data['username'],
            'isPrivate': data['isPrivate'],
          });
        }
      }
    }

    setState(() {
      searchResults = results;
    });
  }

  Future<void> _followUser(String targetUid, bool isPrivate) async {
    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId);
    final targetRef = FirebaseFirestore.instance
        .collection('users')
        .doc(targetUid);

    if (isPrivate) {
      await targetRef.update({
        'followRequests': FieldValue.arrayUnion([currentUserId]),
      });
    } else {
      await targetRef.update({
        'followers': FieldValue.arrayUnion([currentUserId]),
      });
      await myRef.update({
        'following': FieldValue.arrayUnion([targetUid]),
      });
    }

    await _fetchMyData();
    _searchUsers(_searchController.text);
  }

  Future<void> _unfollowUser(String targetUid) async {
    final myRef = FirebaseFirestore.instance
        .collection('users')
        .doc(currentUserId);
    final targetRef = FirebaseFirestore.instance
        .collection('users')
        .doc(targetUid);

    await targetRef.update({
      'followers': FieldValue.arrayRemove([currentUserId]),
    });
    await myRef.update({
      'following': FieldValue.arrayRemove([targetUid]),
    });

    await _fetchMyData();
    _searchUsers(_searchController.text);
  }

  bool _alreadyFollowing(String uid) => myFollowing.contains(uid);
  bool _alreadyRequested(String uid) => myFollowRequests.contains(uid);

  Future<void> _startChat(String uid, String username) async {
    final chatQuery =
        await FirebaseFirestore.instance
            .collection('chats')
            .where('participants', arrayContains: currentUserId)
            .get();

    String? existingChatId;

    for (var doc in chatQuery.docs) {
      final participants = List<String>.from(doc['participants']);
      if (participants.contains(uid)) {
        existingChatId = doc.id;
        break;
      }
    }

    String _getChatId(String user1, String user2) {
      return (user1.compareTo(user2) < 0) ? '$user1-$user2' : '$user2-$user1';
    }

    if (existingChatId == null) {
      String chatId = _getChatId(currentUserId, uid);
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId);
      final chatSnap = await chatRef.get();

      if (!chatSnap.exists) {
        await chatRef.set({
          'participants': [currentUserId, uid],
          'createdAt': FieldValue.serverTimestamp(),
          'typing': {currentUserId: false, uid: false},
          'lastMessage': '',
          'lastTimestamp': FieldValue.serverTimestamp(),
          'lastSenderId': '',
        });
      }
    }

    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => ChatScreen(name: username, uid: uid)),
    );
  }

  String formatTimestamp(Timestamp? timestamp) {
    if (timestamp == null) return '';
    final dt = timestamp.toDate();
    final now = DateTime.now();
    if (dt.day == now.day && dt.month == now.month && dt.year == now.year) {
      return DateFormat('hh:mm a').format(dt);
    } else {
      return DateFormat('dd MMM').format(dt);
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    _chatSubscription.cancel();
    super.dispose();
  }

  Widget _buildStoryTile({required String label, bool isAdd = false}) {
    return Container(
      width: 70,
      margin: const EdgeInsets.only(right: 12),
      child: Column(
        children: [
          Stack(
            alignment: Alignment.bottomRight,
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.deepPurple.shade100,
                child: Icon(Icons.person, color: Colors.deepPurple),
              ),
              if (isAdd)
                CircleAvatar(
                  radius: 10,
                  backgroundColor: Colors.white,
                  child: Icon(Icons.add, size: 16, color: Colors.green),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 11),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Your Circle")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: "Search by username...",
                suffixIcon: Icon(Icons.search),
              ),
              onChanged: _searchUsers,
            ),
            const SizedBox(height: 20),
            Container(
              height: 90,
              margin: const EdgeInsets.only(bottom: 16),
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _buildStoryTile(label: 'Your Story', isAdd: true),
                  ...myFollowing.map((uid) {
                    final username = followingUsernames[uid] ?? 'user';
                    return _buildStoryTile(label: '@$username');
                  }).toList(),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (searchResults.isNotEmpty)
              Expanded(
                child: ListView.builder(
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    final user = searchResults[index];
                    final isMe = user['uid'] == currentUserId;
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Text(user['username'][0].toUpperCase()),
                        ),
                        title: Text('@${user['username']}'),
                        trailing:
                            isMe
                                ? null
                                : _alreadyFollowing(user['uid'])
                                ? Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    IconButton(
                                      icon: Icon(
                                        Icons.chat_bubble_outline,
                                        color: Colors.deepOrange,
                                      ),
                                      onPressed:
                                          () => _startChat(
                                            user['uid'],
                                            user['username'],
                                          ),
                                    ),
                                    IconButton(
                                      icon: Icon(
                                        Icons.remove_circle_outline,
                                        color: Colors.grey,
                                      ),
                                      onPressed:
                                          () => _unfollowUser(user['uid']),
                                    ),
                                  ],
                                )
                                : _alreadyRequested(user['uid'])
                                ? OutlinedButton(
                                  onPressed: null,
                                  child: Text("Requested"),
                                )
                                : ElevatedButton(
                                  onPressed:
                                      () => _followUser(
                                        user['uid'],
                                        user['isPrivate'],
                                      ),
                                  child: Text(
                                    user['isPrivate'] ? "Request" : "Follow",
                                  ),
                                ),
                      ),
                    );
                  },
                ),
              ),
            if (searchResults.isEmpty && myConversations.isNotEmpty)
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      "Chats",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 18,
                      ),
                    ),
                    Expanded(
                      child: ListView.builder(
                        itemCount: myConversations.length,
                        itemBuilder: (context, index) {
                          final friend = myConversations[index];
                          return InkWell(
                            onTap:
                                () => _startChat(
                                  friend['uid'],
                                  friend['username'],
                                ),
                            child: Container(
                              margin: EdgeInsets.only(bottom: 12),
                              padding: EdgeInsets.symmetric(
                                horizontal: 14,
                                vertical: 14,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFF9F9FB),
                                borderRadius: BorderRadius.circular(14),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black12,
                                    blurRadius: 6,
                                    offset: Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Row(
                                children: [
                                  CircleAvatar(
                                    radius: 22,
                                    backgroundColor: Colors.deepPurple.shade100,
                                    child: Text(
                                      friend['username'][0].toUpperCase(),
                                      style: TextStyle(
                                        color: Colors.deepPurple,
                                      ),
                                    ),
                                  ),
                                  SizedBox(width: 14),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          '@${friend['username']}',
                                          style: TextStyle(
                                            fontWeight:
                                                friend['unread'] == true
                                                    ? FontWeight.w900
                                                    : FontWeight.w600,
                                            fontSize: 16,
                                          ),
                                        ),
                                        SizedBox(height: 4),
                                        Text(
                                          friend['lastMessage'] ?? '',
                                          style: TextStyle(
                                            fontSize: 13,
                                            color:
                                                friend['unread'] == true
                                                    ? Colors.deepOrange
                                                    : Colors.grey[700],
                                            fontWeight:
                                                friend['unread'] == true
                                                    ? FontWeight.bold
                                                    : FontWeight.normal,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        formatTimestamp(
                                          friend['lastTimestamp'],
                                        ),
                                        style: TextStyle(
                                          fontSize: 12,
                                          color: Colors.grey[600],
                                        ),
                                      ),
                                      Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.local_fire_department,
                                            color: Colors.deepOrange,
                                            size: 18,
                                          ),
                                          SizedBox(width: 4),
                                          Text(
                                            '${friend['currentStreak']}-day',
                                            style: TextStyle(
                                              fontSize: 12,
                                              color: Colors.black87,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
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
