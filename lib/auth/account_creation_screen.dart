import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../onboarding/welcome_screen.dart';
import '../screens/home_screen.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'dart:io';

class AccountCreationScreen extends StatefulWidget {
  @override
  State<AccountCreationScreen> createState() => _AccountCreationScreenState();
}

class _AccountCreationScreenState extends State<AccountCreationScreen>
    with SingleTickerProviderStateMixin {
  bool isSignup = false;
  bool loading = false;
  bool usernameTaken = false;
  bool checkingUsername = false;
  bool isPrivate = false;

  final _usernameController = TextEditingController();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  late AnimationController _fadeController;
  late Animation<double> _fadeAnimation;
  Future<void> _registerTokenAfterLogin() async {
    if (Platform.isIOS) {
      print("❌ Skipping FCM token registration on iOS (APNs not set)");
      return;
    }

    final fcmToken = await FirebaseMessaging.instance.getToken();
    final currentUser = FirebaseAuth.instance.currentUser;

    if (currentUser != null && fcmToken != null) {
      final tokensRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);

      final doc = await tokensRef.get();
      final existingTokens = List<String>.from(doc.data()?['fcmTokens'] ?? []);

      if (!existingTokens.contains(fcmToken)) {
        existingTokens.add(fcmToken);
        await tokensRef.set({
          'fcmTokens': existingTokens,
        }, SetOptions(merge: true));
        print("✅ Token added to array!");
      } else {
        print("ℹ️ Token already exists in list");
      }
    } else {
      print("❌ Could not get current user or FCM token");
    }
  }

  @override
  void initState() {
    super.initState();
    _fadeController = AnimationController(
      vsync: this,
      duration: Duration(milliseconds: 800),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _fadeController,
      curve: Curves.easeInOut,
    );
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    super.dispose();
  }

  void _toggleMode() {
    setState(() {
      isSignup = !isSignup;
      usernameTaken = false;
      _usernameController.clear();
      _emailController.clear();
      _passwordController.clear();
    });
  }

  Future<void> _checkUsernameAvailability(String username) async {
    if (username.length < 6) {
      setState(() {
        usernameTaken = true;
        checkingUsername = false;
      });
      return;
    }
    setState(() => checkingUsername = true);
    final doc =
        await FirebaseFirestore.instance
            .collection('usernames')
            .doc(username.trim().toLowerCase().replaceAll("@", ""))
            .get();
    setState(() {
      usernameTaken = doc.exists;
      checkingUsername = false;
    });
  }

  Future<void> _submit() async {
    final username = _usernameController.text.trim().toLowerCase().replaceAll(
      "@",
      "",
    );
    final password = _passwordController.text.trim();
    final email = _emailController.text.trim();

    setState(() => loading = true);

    try {
      if (isSignup) {
        if (username.isEmpty || username.length < 6 || usernameTaken) {
          _showError("Username must be at least 6 characters and available");
          return;
        }

        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);

        final uid = credential.user!.uid;

        await FirebaseFirestore.instance.collection('users').doc(uid).set({
          'username': username,
          'email': email,
          'createdAt': Timestamp.now(),
          'followers': [],
          'following': [],
          'followRequests': [],
          'isPrivate': isPrivate,
          'onboardingCompleted': false,
          'currentStreak': 0,
          'longestStreak': 0,
        });
        await _registerTokenAfterLogin();
        await FirebaseFirestore.instance
            .collection('usernames')
            .doc(username)
            .set({'uid': uid, 'email': email});

        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => WelcomeScreen()),
        );
      } else {
        final snapshot =
            await FirebaseFirestore.instance
                .collection('usernames')
                .doc(username)
                .get();

        if (!snapshot.exists || snapshot.data()?['email'] == null) {
          _showError("Username not found");
          return;
        }

        final userEmail = snapshot.data()!['email'] as String;

        final credential = await FirebaseAuth.instance
            .signInWithEmailAndPassword(email: userEmail, password: password);
        await _registerTokenAfterLogin();
        final doc =
            await FirebaseFirestore.instance
                .collection('users')
                .doc(credential.user!.uid)
                .get();

        if (doc.exists && doc.data()?['onboardingCompleted'] == true) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => HomeScreen()),
          );
        } else {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(builder: (_) => WelcomeScreen()),
          );
        }
      }
    } catch (e) {
      _showError("Auth failed: ${e.toString()}");
    }

    setState(() => loading = false);
  }

  void _resetPassword() async {
    final username = _usernameController.text.trim().toLowerCase().replaceAll(
      "@",
      "",
    );
    if (username.isEmpty) {
      _showError("Enter your username to reset password");
      return;
    }

    final doc =
        await FirebaseFirestore.instance
            .collection('usernames')
            .doc(username)
            .get();

    if (!doc.exists) {
      _showError("Username not found");
      return;
    }

    final email = doc.data()?['email'];
    await FirebaseAuth.instance.sendPasswordResetEmail(email: email);
    _showError("Password reset email sent to $email");
  }

  void _showError(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        title: FadeTransition(
          opacity: _fadeAnimation,
          child: Text(
            "Hanumode",
            style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
          ),
        ),
      ),
      body: Center(
        child: FadeTransition(
          opacity: _fadeAnimation,
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  isSignup ? "Create Account" : "Login",
                  style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 20),
                TextField(
                  controller: _usernameController,
                  decoration: InputDecoration(
                    labelText: isSignup ? "Choose Username" : "Username",
                    prefixText: "@",
                    suffixIcon:
                        isSignup
                            ? (checkingUsername
                                ? CircularProgressIndicator(strokeWidth: 2)
                                : usernameTaken
                                ? Icon(Icons.close, color: Colors.red)
                                : Icon(Icons.check, color: Colors.green))
                            : null,
                  ),
                  onChanged: (val) {
                    if (isSignup && val.length >= 3) {
                      _checkUsernameAvailability(val);
                    }
                  },
                ),
                if (isSignup) ...[
                  const SizedBox(height: 12),
                  TextField(
                    controller: _emailController,
                    decoration: InputDecoration(labelText: "Email"),
                    keyboardType: TextInputType.emailAddress,
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Checkbox(
                        value: isPrivate,
                        onChanged: (val) => setState(() => isPrivate = val!),
                      ),
                      Expanded(
                        child: Text(
                          "Private Account (needs approval to follow)",
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 12),
                TextField(
                  controller: _passwordController,
                  decoration: InputDecoration(labelText: "Password"),
                  obscureText: true,
                ),
                if (!isSignup)
                  Align(
                    alignment: Alignment.centerRight,
                    child: TextButton(
                      onPressed: _resetPassword,
                      child: Text("Forgot Password?"),
                    ),
                  ),
                const SizedBox(height: 20),
                loading
                    ? CircularProgressIndicator()
                    : ElevatedButton(
                      onPressed: _submit,
                      style: ElevatedButton.styleFrom(
                        minimumSize: Size(double.infinity, 50),
                        backgroundColor: Colors.deepOrange,
                      ),
                      child: Text(isSignup ? "Sign Up" : "Login"),
                    ),
                TextButton(
                  onPressed: _toggleMode,
                  child: Text(
                    isSignup
                        ? "Already have an account? Login"
                        : "New here? Create account",
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
