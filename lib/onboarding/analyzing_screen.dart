import 'dart:async';
import 'package:flutter/material.dart';
import '../screens/home_screen.dart';

class AnalyzingScreen extends StatefulWidget {
  @override
  State<AnalyzingScreen> createState() => _AnalyzingScreenState();
}

class _AnalyzingScreenState extends State<AnalyzingScreen> {
  final List<String> messages = [
    "Analyzing your body...",
    "Gathering warrior stats...",
    "Preparing your path...",
    "Loading battle gear...",
    "Almost there...",
  ];

  int currentMsg = 0;

  @override
  void initState() {
    super.initState();
    Timer.periodic(Duration(seconds: 1), (timer) {
      if (currentMsg < messages.length - 1) {
        setState(() => currentMsg++);
      } else {
        timer.cancel();
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (_) => HomeScreen()),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Text(messages[currentMsg], style: TextStyle(fontSize: 20)),
      ),
    );
  }
}
