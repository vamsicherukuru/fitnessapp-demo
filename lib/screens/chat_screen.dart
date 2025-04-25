import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

class ChatScreen extends StatefulWidget {
  final String name;
  final String uid;

  const ChatScreen({required this.name, required this.uid});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final String currentUserId = FirebaseAuth.instance.currentUser!.uid;
  List<DocumentSnapshot> localMessages = [];
  late String chatId;

  @override
  void initState() {
    super.initState();
    chatId = _getChatId(currentUserId, widget.uid);
    _loadMessagesLocally();
  }

  void _loadMessagesLocally() async {
    final snapshot =
        await FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .orderBy('timestamp')
            .get();
    setState(() {
      localMessages = snapshot.docs;
    });
    _scrollToBottom();
  }

  String _getChatId(String user1, String user2) {
    return (user1.compareTo(user2) < 0) ? '$user1-$user2' : '$user2-$user1';
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    HapticFeedback.mediumImpact();

    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);
    final chatSnapshot = await chatRef.get();

    if (!chatSnapshot.exists) {
      await chatRef.set({
        'participants': [currentUserId, widget.uid],
        'lastMessage': text,
        'lastTimestamp': Timestamp.now(),
        'typing': {currentUserId: false, widget.uid: false},
        'lastSenderId': currentUserId,
      });
    } else {
      await chatRef.update({
        'lastMessage': text,
        'lastTimestamp': Timestamp.now(),
        'typing': {currentUserId: false, widget.uid: false},
        'lastSenderId': currentUserId,
      });
    }

    await chatRef.collection('messages').add({
      'senderId': currentUserId,
      'receiverId': widget.uid,
      'text': text,
      'timestamp': Timestamp.now(),
      'read': false,
      'type': 'text',
    });

    _messageController.clear();
    setTyping(false);
  }

  void setTyping(bool status) {
    FirebaseFirestore.instance.collection('chats').doc(chatId).set({
      'typing': {currentUserId: status},
    }, SetOptions(merge: true));
  }

  Widget typingIndicator() {
    return Padding(
      padding: const EdgeInsets.only(left: 16, bottom: 10),
      child: Row(
        children: [
          Dot(),
          SizedBox(width: 4),
          Dot(delay: 200),
          SizedBox(width: 4),
          Dot(delay: 400),
        ],
      ),
    );
  }

  Widget readReceipt(bool isRead) {
    return Padding(
      padding: const EdgeInsets.only(top: 4, left: 4),
      child: Icon(
        Icons.done_all,
        color: isRead ? Colors.green : Colors.grey,
        size: 16,
      ),
    );
  }

  String _getInitials(String name) {
    final parts = name.trim().split(' ');
    if (parts.length == 1) return parts[0][0].toUpperCase();
    return (parts[0][0] + parts[1][0]).toUpperCase();
  }

  Widget timeStamp(Timestamp ts) {
    final time = ts.toDate();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Text(
        DateFormat('hh:mm a').format(time),
        style: TextStyle(fontSize: 10, color: Colors.grey),
      ),
    );
  }

  @override
  void dispose() {
    _messageController.dispose();
    setTyping(false);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Color(0xFFF0F0F0),
      appBar: AppBar(
        backgroundColor: const Color.fromARGB(255, 255, 255, 255),
        iconTheme: const IconThemeData(color: Color.fromARGB(255, 0, 0, 0)),
        elevation: 0,
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.grey.shade300,
              radius: 20,
              child: Text(
                _getInitials(widget.name),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                  fontSize: 20,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.name,
                  style: const TextStyle(
                    color: Colors.black,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                StreamBuilder<DocumentSnapshot>(
                  stream:
                      FirebaseFirestore.instance
                          .collection('users')
                          .doc(widget.uid)
                          .snapshots(),
                  builder: (context, snapshot) {
                    if (!snapshot.hasData) {
                      return const SizedBox.shrink();
                    }
                    final data = snapshot.data!.data() as Map<String, dynamic>;
                    final isOnline = data['online'] ?? false;
                    final lastSeen = data['lastSeen'] as Timestamp?;

                    String statusText;
                    if (isOnline) {
                      statusText = "Online";
                    } else if (lastSeen != null) {
                      final lastSeenTime = lastSeen.toDate();
                      final formatted = DateFormat(
                        'hh:mm a',
                      ).format(lastSeenTime);
                      statusText = "Last seen at $formatted";
                    } else {
                      statusText = "Offline";
                    }

                    return Text(
                      statusText,
                      style: TextStyle(
                        color: isOnline ? Colors.green : Colors.grey,
                        fontSize: 12,
                      ),
                    );
                  },
                ),
              ],
            ),
          ],
        ),
      ),

      body: Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream:
                  FirebaseFirestore.instance
                      .collection('chats')
                      .doc(chatId)
                      .collection('messages')
                      .orderBy('timestamp')
                      .snapshots(),
              builder: (context, snapshot) {
                final messages =
                    snapshot.hasData ? snapshot.data!.docs : localMessages;

                WidgetsBinding.instance.addPostFrameCallback((_) {
                  _scrollToBottom();
                });

                return ListView.builder(
                  controller: _scrollController,
                  padding: EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index].data() as Map<String, dynamic>;
                    final isMe = msg['senderId'] == currentUserId;

                    if (!isMe && !msg['read']) {
                      FirebaseFirestore.instance
                          .collection('chats')
                          .doc(chatId)
                          .collection('messages')
                          .doc(messages[index].id)
                          .update({'read': true});
                      HapticFeedback.lightImpact();
                    }

                    return Align(
                      alignment:
                          isMe ? Alignment.centerRight : Alignment.centerLeft,
                      child: Column(
                        crossAxisAlignment:
                            isMe
                                ? CrossAxisAlignment.end
                                : CrossAxisAlignment.start,
                        children: [
                          Container(
                            margin: EdgeInsets.symmetric(vertical: 2),
                            padding: EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(maxWidth: 270),
                            decoration: BoxDecoration(
                              color: isMe ? Color(0xFFD2F5E3) : Colors.white,
                              borderRadius: BorderRadius.only(
                                topLeft: Radius.circular(14),
                                topRight: Radius.circular(14),
                                bottomLeft: Radius.circular(isMe ? 14 : 0),
                                bottomRight: Radius.circular(isMe ? 0 : 14),
                              ),
                            ),
                            child: Text(
                              msg['text'],
                              style: TextStyle(fontSize: 15),
                            ),
                          ),
                          Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              timeStamp(msg['timestamp']),
                              if (isMe) readReceipt(msg['read'] ?? false),
                            ],
                          ),
                        ],
                      ),
                    );
                  },
                );
              },
            ),
          ),
          StreamBuilder<DocumentSnapshot>(
            stream:
                FirebaseFirestore.instance
                    .collection('chats')
                    .doc(chatId)
                    .snapshots(),
            builder: (context, snapshot) {
              if (!snapshot.hasData) return SizedBox.shrink();
              final typing =
                  (snapshot.data!.data() as Map<String, dynamic>)['typing'];
              if (typing != null && typing[widget.uid] == true) {
                return typingIndicator();
              }
              return SizedBox.shrink();
            },
          ),
          Padding(
            padding: const EdgeInsets.only(left: 12, right: 12, bottom: 30),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(30),
                boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 6)],
              ),
              child: Row(
                children: [
                  Icon(Icons.emoji_emotions_outlined, color: Colors.grey),
                  SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      onChanged: (val) => setTyping(val.isNotEmpty),
                      decoration: InputDecoration(
                        hintText: "Message...",
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  // IconButton(
                  //   icon: Icon(Icons.image, color: Colors.grey),
                  //   onPressed: () {},
                  // ),
                  IconButton(
                    icon: Icon(Icons.send, color: Color(0xFF128C7E)),
                    onPressed: _sendMessage,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class Dot extends StatefulWidget {
  final int delay;
  const Dot({this.delay = 0});

  @override
  State<Dot> createState() => _DotState();
}

class _DotState extends State<Dot> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: Duration(milliseconds: 600),
      vsync: this,
    )..repeat(reverse: true);

    _animation = Tween<double>(
      begin: 0,
      end: 8,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _animation,
      builder:
          (context, child) => Container(
            width: 8,
            height: 8 + _animation.value,
            decoration: BoxDecoration(
              color: Colors.grey,
              borderRadius: BorderRadius.circular(8),
            ),
          ),
    );
  }
}
