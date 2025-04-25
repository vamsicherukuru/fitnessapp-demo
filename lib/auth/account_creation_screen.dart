/// lib/auth/account_creation_screen.dart
///
/// Compatible with the *friends / requestsIn / requestsOut* schema.
/// Deps: firebase_auth, cloud_firestore, firebase_messaging, flutter/material.

import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import '../onboarding/welcome_screen.dart';
import '../screens/home_screen.dart';

class AccountCreationScreen extends StatefulWidget {
  const AccountCreationScreen({super.key});
  @override
  State<AccountCreationScreen> createState() => _AccountCreationScreenState();
}

class _AccountCreationScreenState extends State<AccountCreationScreen>
    with SingleTickerProviderStateMixin {
  /* ── UI / state ───────────────────────────── */
  bool isSignup = false;
  bool loading = false;
  bool usernameTaken = false;
  bool checkingUsername = false;
  bool isPrivate = false;

  final _usernameC = TextEditingController();
  final _emailC = TextEditingController();
  final _pwC = TextEditingController();

  late final AnimationController _fadeCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final Animation<double> _fadeAnim = CurvedAnimation(
    parent: _fadeCtrl,
    curve: Curves.easeInOut,
  );

  /* ── FCM helper ───────────────────────────── */
  Future<void> _registerFcmToken() async {
    if (Platform.isIOS) return; // APNs not set
    final token = await FirebaseMessaging.instance.getToken();
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || token == null) return;

    final doc = FirebaseFirestore.instance.collection('users').doc(uid);
    await doc.set({
      'fcmTokens': FieldValue.arrayUnion([token]),
    }, SetOptions(merge: true));
  }

  /* ── username availability ─────────────────── */
  Future<void> _checkUsername(String uname) async {
    if (uname.length < 6) {
      setState(() => usernameTaken = true);
      return;
    }
    setState(() => checkingUsername = true);
    final snap =
        await FirebaseFirestore.instance
            .collection('usernames')
            .doc(uname.toLowerCase())
            .get();
    setState(() {
      usernameTaken = snap.exists;
      checkingUsername = false;
    });
  }

  /* ── create initial user-doc ───────────────── */
  Future<void> _writeCoreUserDoc({
    required String uid,
    required String username,
    required String email,
  }) async {
    await FirebaseFirestore.instance.collection('users').doc(uid).set({
      'username': username,
      'email': email,
      'createdAt': Timestamp.now(),
      'isPrivate': isPrivate,
      // NEW schema ↓↓↓
      'friends': [],
      'requestsIn': [],
      'requestsOut': [],
      // streaks
      'currentStreak': 0,
      'longestStreak': 0,
      // onboarding
      'onboardingCompleted': false,
    });
    // reverse index
    await FirebaseFirestore.instance.collection('usernames').doc(username).set({
      'uid': uid,
      'email': email,
    });
  }

  /* ── auth submit ───────────────────────────── */
  Future<void> _submit() async {
    final uname = _usernameC.text.trim().toLowerCase().replaceAll('@', '');
    final pw = _pwC.text.trim();
    final mail = _emailC.text.trim();

    if (isSignup && (uname.length < 6 || usernameTaken)) {
      _toast('Pick an available username (≥ 6 chars)');
      return;
    }
    if (pw.length < 6) {
      _toast('Password must be ≥ 6 characters');
      return;
    }

    setState(() => loading = true);

    try {
      if (isSignup) {
        final cred = await FirebaseAuth.instance.createUserWithEmailAndPassword(
          email: mail,
          password: pw,
        );
        await _writeCoreUserDoc(
          uid: cred.user!.uid,
          username: uname,
          email: mail,
        );
        await _registerFcmToken();
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => WelcomeScreen()),
        );
      } else {
        // login: resolve username → email
        final snap =
            await FirebaseFirestore.instance
                .collection('usernames')
                .doc(uname)
                .get();
        if (!snap.exists) {
          _toast('Username not found');
          return;
        }
        final userEmail = snap['email'] as String;
        final cred = await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: userEmail,
          password: pw,
        );
        await _registerFcmToken();
        final userDoc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(cred.user!.uid)
                .get();
        final onboardingDone = userDoc.data()?['onboardingCompleted'] == true;
        if (!mounted) return;
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (_) => onboardingDone ? HomeScreen() : WelcomeScreen(),
          ),
        );
      }
    } catch (e) {
      _toast('Auth failed: $e');
    }

    if (mounted) setState(() => loading = false);
  }

  /* ── utils ─────────────────────────────────── */
  void _toast(String msg) =>
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));

  /* ── UI ────────────────────────────────────── */
  @override
  void initState() {
    super.initState();
    _fadeCtrl.forward();
  }

  @override
  void dispose() {
    _fadeCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: Colors.white,
    appBar: AppBar(
      title: FadeTransition(
        opacity: _fadeAnim,
        child: const Text(
          'Hanumode',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
      ),
      centerTitle: true,
      elevation: 0,
      backgroundColor: Colors.white,
    ),
    body: Center(
      child: FadeTransition(
        opacity: _fadeAnim,
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                isSignup ? 'Create Account' : 'Login',
                style: const TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // username
              TextField(
                controller: _usernameC,
                decoration: InputDecoration(
                  labelText: isSignup ? 'Choose Username' : 'Username',
                  prefixText: '@',
                  suffixIcon:
                      isSignup
                          ? (checkingUsername
                              ? const SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                ),
                              )
                              : Icon(
                                usernameTaken ? Icons.close : Icons.check,
                                color:
                                    usernameTaken ? Colors.red : Colors.green,
                              ))
                          : null,
                ),
                onChanged: (v) {
                  if (isSignup && v.length >= 3) _checkUsername(v);
                },
              ),

              if (isSignup) ...[
                const SizedBox(height: 12),
                TextField(
                  controller: _emailC,
                  decoration: const InputDecoration(labelText: 'Email'),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Checkbox(
                      value: isPrivate,
                      onChanged: (v) => setState(() => isPrivate = v!),
                    ),
                    const Expanded(
                      child: Text('Private account (needs approval to add)'),
                    ),
                  ],
                ),
              ],

              const SizedBox(height: 12),
              TextField(
                controller: _pwC,
                decoration: const InputDecoration(labelText: 'Password'),
                obscureText: true,
              ),

              if (!isSignup)
                Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () async {
                      final uname = _usernameC.text
                          .trim()
                          .toLowerCase()
                          .replaceAll('@', '');
                      if (uname.isEmpty) {
                        _toast('Enter username first');
                        return;
                      }
                      final snap =
                          await FirebaseFirestore.instance
                              .collection('usernames')
                              .doc(uname)
                              .get();
                      if (!snap.exists) {
                        _toast('Username not found');
                        return;
                      }
                      await FirebaseAuth.instance.sendPasswordResetEmail(
                        email: snap['email'],
                      );
                      _toast('Password reset email sent');
                    },
                    child: const Text('Forgot password?'),
                  ),
                ),

              const SizedBox(height: 20),
              loading
                  ? const CircularProgressIndicator()
                  : ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size.fromHeight(50),
                      backgroundColor: Colors.deepOrange,
                    ),
                    onPressed: _submit,
                    child: Text(isSignup ? 'Sign Up' : 'Login'),
                  ),

              TextButton(
                onPressed: () {
                  setState(() => isSignup = !isSignup);
                },
                child: Text(
                  isSignup
                      ? 'Already have an account? Login'
                      : 'New here? Create account',
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
