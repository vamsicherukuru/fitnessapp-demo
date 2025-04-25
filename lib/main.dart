import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hanumode/screens/chat_screen.dart';
import 'screens/splash_screen.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  await _initializeLocalNotifications();
  // ADD THIS

  runApp(HanumodeApp());
}

Future<void> _initializeLocalNotifications() async {
  const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');

  final iosInit = DarwinInitializationSettings(); // iOS setup

  final initSettings = InitializationSettings(
    android: androidInit,
    iOS: iosInit,
  );

  await flutterLocalNotificationsPlugin.initialize(
    initSettings,
    onDidReceiveNotificationResponse: (response) {
      if (response.payload != null) {
        final data = jsonDecode(response.payload!);
        navigatorKey.currentState?.pushNamed(
          '/chat',
          arguments: {'chatId': data['chatId'], 'senderId': data['senderId']},
        );
      }
    },
  );
}

class HanumodeApp extends StatefulWidget {
  @override
  State<HanumodeApp> createState() => _HanumodeAppState();
}

class _HanumodeAppState extends State<HanumodeApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setUserOnline(true);
    _handleForegroundNotifications();
    _handleNotificationTap();
    _requestNotificationPermissions();
    _waitForAuthAndRegisterToken();
  }

  void _waitForAuthAndRegisterToken() async {
    await Future.delayed(Duration(seconds: 1)); // give a small delay

    User? currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _registerToken(); // Now it will work
    } else {
      FirebaseAuth.instance.authStateChanges().listen((user) {
        if (user != null) {
          _registerToken();
        }
      });
    }
  }

  void _registerToken() async {
    print("📡 Trying to register FCM token...");

    final permission = await FirebaseMessaging.instance.requestPermission();
    print("🔐 Permission status: ${permission.authorizationStatus}");

    if (permission.authorizationStatus == AuthorizationStatus.authorized) {
      final fcmToken = await FirebaseMessaging.instance.getToken();
      print("📲 FCM Token: $fcmToken");

      final currentUser = FirebaseAuth.instance.currentUser;
      print("👤 Current User UID: ${currentUser?.uid}");

      if (currentUser != null && fcmToken != null) {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(currentUser.uid)
            .set({'fcmToken': fcmToken}, SetOptions(merge: true));
        print("✅ Token saved to Firestore!");
      } else {
        print("❌ Either user or token is null");
      }
    } else {
      print("❌ Notification permission denied");
    }
  }

  void _requestNotificationPermissions() async {
    await FirebaseMessaging.instance.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
  }

  void _handleForegroundNotifications() {
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      final notification = message.notification;
      final android = notification?.android;
      if (notification != null && android != null) {
        flutterLocalNotificationsPlugin.show(
          notification.hashCode,
          notification.title,
          notification.body,
          NotificationDetails(
            android: AndroidNotificationDetails(
              'hanumode_channel',
              'Hanumode Notifications',
              importance: Importance.max,
              priority: Priority.high,
            ),
          ),
          payload: jsonEncode(message.data),
        );
      }
    });
  }

  void _handleNotificationTap() async {
    // App launched from terminated state
    RemoteMessage? initialMessage =
        await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      final data = initialMessage.data;
      navigatorKey.currentState?.pushNamed(
        '/chat',
        arguments: {'chatId': data['chatId'], 'senderId': data['senderId']},
      );
    }

    // App resumed from background via notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final data = message.data;
      navigatorKey.currentState?.pushNamed(
        '/chat',
        arguments: {'chatId': data['chatId'], 'senderId': data['senderId']},
      );
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _setUserOnline(false);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final isOnline = state == AppLifecycleState.resumed;
    _setUserOnline(isOnline);
  }

  void _setUserOnline(bool isOnline) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'online': isOnline,
        'lastSeen': Timestamp.now(),
      }, SetOptions(merge: true));
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      title: 'Hanumode',
      theme: ThemeData(
        primarySwatch: Colors.teal,
        textTheme: GoogleFonts.poppinsTextTheme(),
      ),
      home: SplashScreen(),
      onGenerateRoute: (settings) {
        if (settings.name == '/chat') {
          final args = settings.arguments as Map<String, dynamic>;
          return MaterialPageRoute(
            builder:
                (context) => ChatScreen(
                  uid: args['senderId'],
                  name: 'From Push', // Replace with actual name if needed
                ),
          );
        }
        return null;
      },
    );
  }
}
