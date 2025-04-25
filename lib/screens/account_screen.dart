import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../screens/splash_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';

class AccountScreen extends StatefulWidget {
  @override
  State<AccountScreen> createState() => _AccountScreenState();
}

class _AccountScreenState extends State<AccountScreen> {
  final user = FirebaseAuth.instance.currentUser;
  Map<String, dynamic>? userData;
  bool _isPrivate = false;

  @override
  void initState() {
    super.initState();
    _fetchUserData();
  }

  Future<void> _fetchUserData() async {
    if (user != null) {
      final doc =
          await FirebaseFirestore.instance
              .collection('users')
              .doc(user!.uid)
              .get();
      if (doc.exists) {
        final data = doc.data();
        setState(() {
          userData = data;
          _isPrivate = data?['isPrivate'] ?? false;
        });
      }
    }
  }

  Future<void> _togglePrivacy(bool value) async {
    setState(() => _isPrivate = value);
    await FirebaseFirestore.instance.collection('users').doc(user!.uid).update({
      'isPrivate': value,
    });
  }

  Future<void> _logout() async {
    // quick loader so the user sees feedback
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      // ─────────────  iOS  ─────────────
      if (Platform.isIOS) {
        await FirebaseAuth.instance.signOut();
      }
      // ─────────── Android / others ───────────
      else {
        final user = FirebaseAuth.instance.currentUser;
        final token = await FirebaseMessaging.instance.getToken();

        if (user != null && token != null) {
          final ref = FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid);

          try {
            await ref.update({
              'fcmTokens': FieldValue.arrayRemove([token]),
              'fcmToken': FieldValue.delete(), // legacy field
            });
          } catch (_) {
            /* ignore */
          }

          await FirebaseMessaging.instance.deleteToken();
        }

        await FirebaseAuth.instance.signOut();
      }
    } finally {
      if (mounted) Navigator.of(context).pop(); // close loader
    }

    // go to splash / login
    if (mounted) {
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => SplashScreen()),
        (_) => false,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final initials =
        userData?['name'] != null ? userData!['name'][0].toUpperCase() : 'U';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("My Profile", style: TextStyle(color: Colors.black)),
        centerTitle: true,
        elevation: 0.5,
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.black),
      ),
      body:
          userData == null
              ? Center(child: CircularProgressIndicator())
              : SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 24,
                ),
                child: Column(
                  children: [
                    _buildProfileHeader(initials),
                    const SizedBox(height: 24),
                    _buildStatsRow(),
                    const SizedBox(height: 20),
                    _buildDetailCard(),
                    const SizedBox(height: 24),
                    _buildBadgeSection(),
                    const SizedBox(height: 30),
                    _buildActionButtons(),
                  ],
                ),
              ),
    );
  }

  Widget _buildProfileHeader(String initials) {
    return Column(
      children: [
        AnimatedContainer(
          duration: Duration(milliseconds: 400),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.deepOrange.withOpacity(0.2),
                blurRadius: 10,
              ),
            ],
          ),
          child: CircleAvatar(
            radius: 46,
            backgroundColor: Colors.deepOrange.shade100,
            child: Text(
              initials,
              style: TextStyle(fontSize: 36, color: Colors.deepOrange),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          userData!['name'],
          style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
        ),
        Text(
          "@${userData!['username']}",
          style: TextStyle(color: Colors.grey.shade700),
        ),
        const SizedBox(height: 4),
        Text(
          user?.email ?? '',
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildStatsRow() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceAround,
      children: [
        _statItem("Posts", "0"),
        _statItem("Followers", "0"),
        _statItem("Following", "0"),
      ],
    );
  }

  Widget _statItem(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
        ),
      ],
    );
  }

  Widget _buildDetailCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: Colors.grey.shade200,
            blurRadius: 12,
            offset: Offset(0, 3),
          ),
        ],
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildDetailRow("Age", "${userData!['age'] ?? '--'}"),
          _buildDetailRow("Gender", "${userData!['gender'] ?? '--'}"),
          _buildDetailRow("Height", "${userData!['height']} cm"),
          _buildDetailRow("Weight", "${userData!['weight']} kg"),
          _buildDetailRow("Activity", "${userData!['activity'] ?? '--'}"),
          _buildDetailRow("Goal", "${userData!['goal'] ?? '--'}"),
          const SizedBox(height: 14),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                "Make account private",
                style: TextStyle(fontSize: 15, color: Colors.grey.shade800),
              ),
              Switch(
                value: _isPrivate,
                activeColor: Colors.deepOrange,
                onChanged: _togglePrivacy,
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey.shade600)),
          Text(value, style: TextStyle(fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  Widget _buildBadgeSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          "\ud83c\udfc5 Badges Achieved",
          style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 12,
          runSpacing: 10,
          children: [
            _badgeTile("\ud83d\udd25 Day 1 Warrior"),
            _badgeTile("\ud83d\udcaa 5 Days Streak"),
            _badgeTile("\ud83c\udfaf Goal Setter"),
            _badgeTile("\u26a1\ufe0f Beast Mode"),
          ],
        ),
      ],
    );
  }

  Widget _badgeTile(String title) {
    return Chip(
      label: Text(title),
      backgroundColor: Colors.orange.shade100,
      labelStyle: TextStyle(color: Colors.deepOrange.shade800),
      padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    );
  }

  Widget _buildActionButtons() {
    return Column(
      children: [
        ElevatedButton.icon(
          icon: Icon(Icons.edit, size: 20),
          label: Text("Edit Profile"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.teal,
            minimumSize: Size(double.infinity, 48),
            shape: StadiumBorder(),
          ),
          onPressed: () {},
        ),
        const SizedBox(height: 12),
        ElevatedButton.icon(
          icon: Icon(Icons.logout, size: 20),
          label: Text("Logout"),
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black87,
            minimumSize: Size(double.infinity, 48),
            shape: StadiumBorder(),
          ),
          onPressed: _logout,
        ),
      ],
    );
  }
}
